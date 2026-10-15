//! Render workers (docs/07 §Parallel rendering): threads that help the
//! audio thread render a block's ready nodes. Each block the audio thread
//! wakes up to one worker per node it could hand out (`begin`), renders
//! and mixes alongside them, and closes the block (`end`) once every node
//! is mixed, waiting only for workers still inside it.
//!
//! Idle workers sleep; the rendering thread sleeps for completions only
//! when no ready node can be claimed. Live callbacks only enlist
//! workers admitted to realtime scheduling and the current I/O workgroup.
//! Pool setup allocates on control; block dispatch/completion do not allocate
//! or acquire control-thread mutexes. The work function must obey the audio
//! contract too. Audio can render unclaimed nodes itself, but a helper that
//! has claimed a node must finish before the callback can complete.
//!
//! Workers request Mach time-constraint policy and join the device's I/O
//! workgroup. Admission failure makes live callbacks render serially. These
//! requests do not guarantee core placement or that DSP meets its deadline.
//! With `--no-rt-workers`, QoS workers are used for offline rendering only.

const std = @import("std");

extern "c" var mach_task_self_: u32;
extern "c" fn semaphore_create(task: u32, sem: *u32, policy: c_int, value: c_int) c_int;
extern "c" fn semaphore_destroy(task: u32, sem: u32) c_int;
extern "c" fn semaphore_signal(sem: u32) c_int;
extern "c" fn semaphore_wait(sem: u32) c_int;
extern "c" fn pthread_set_qos_class_self_np(qos: c_uint, relative: c_int) c_int;
extern "c" fn pthread_self() std.c.pthread_t;
extern "c" fn pthread_mach_thread_np(t: std.c.pthread_t) u32;
extern "c" fn thread_policy_set(thread: u32, flavor: c_uint, policy: *const TimeConstraint, count: c_uint) c_int;
extern "c" fn mach_timebase_info(info: *TimebaseInfo) c_int;
extern "c" fn os_workgroup_join(wg: *anyopaque, token: *JoinToken) c_int;
extern "c" fn os_workgroup_leave(wg: *anyopaque, token: *JoinToken) void;
extern "c" fn os_release(obj: *anyopaque) void;
extern "c" fn os_workgroup_max_parallel_threads(wg: *anyopaque, attr: ?*anyopaque) c_int;
extern "c" fn usleep(us: c_uint) c_int;
extern "c" fn sysctlbyname(name: [*:0]const u8, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*anyopaque, newlen: usize) c_int;
const QOS_CLASS_USER_INTERACTIVE: c_uint = 0x21;
const SYNC_POLICY_FIFO: c_int = 0;
const THREAD_TIME_CONSTRAINT_POLICY: c_uint = 2;

const TimeConstraint = extern struct {
    period: u32,
    computation: u32,
    constraint: u32,
    preemptible: c_int,
};
const TimebaseInfo = extern struct { numer: u32, denom: u32 };
/// os_workgroup_join_token_s: a signature and 36 opaque bytes.
const JoinToken = extern struct { sig: u32 = 0, bytes: [36]u8 = @splat(0) };

/// Real-time scheduling for the workers: the device's block period.
pub const Rt = struct {
    period_ns: u64,
};

/// Give the calling thread Mach's time-constraint policy: up to half of
/// every `period_ns`, finished within the period. False if refused.
fn setTimeConstraint(period_ns: u64) bool {
    var tb: TimebaseInfo = undefined;
    if (mach_timebase_info(&tb) != 0 or tb.numer == 0) return false;
    const period: u32 = @intCast(@min(period_ns * tb.denom / tb.numer, std.math.maxInt(u32)));
    const policy: TimeConstraint = .{
        .period = period,
        .computation = period / 2,
        .constraint = period,
        .preemptible = 1,
    };
    return thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_TIME_CONSTRAINT_POLICY, &policy, 4) == 0;
}

pub const MAX_WORKERS = 7;
/// Consecutive slow live blocks before the watchdog drops to serial.
pub const STRIKES = 2;

extern "c" fn mach_absolute_time() u64;

fn nsToTicks(ns: u64) u64 {
    var tb: TimebaseInfo = undefined;
    if (mach_timebase_info(&tb) != 0 or tb.numer == 0) return ns;
    return ns * tb.denom / tb.numer;
}

/// Workers to run by default: one fewer than the performance cores (the
/// audio thread is the other), at most MAX_WORKERS.
pub fn defaultWorkers() usize {
    var n: c_int = 0;
    var len: usize = @sizeOf(c_int);
    const cores: usize = if (sysctlbyname("hw.perflevel0.logicalcpu", &n, &len, null, 0) == 0 and n > 0)
        @intCast(n)
    else
        std.Thread.getCpuCount() catch 1;
    return @min(cores -| 1, MAX_WORKERS);
}

/// A pool running `work(ctx, scratch, render_slot)` until the block closes; `work`
/// returns false when it found nothing to do. `Scratch` lives on each
/// worker's stack.
pub fn Pool(comptime Ctx: type, comptime Scratch: type, comptime work: fn (*Ctx, *Scratch, usize) bool) type {
    return struct {
        const Self = @This();

        threads: [MAX_WORKERS]std.Thread = undefined,
        n: usize = 0,
        sem: u32 = 0,
        completion: u32 = 0,
        waiting: std.atomic.Value(bool) = .init(false),
        rt_ready: std.atomic.Value(u32) = .init(0),
        wg_ready: std.atomic.Value(u32) = .init(0),
        ctx: *Ctx,
        /// A block is open: workers may take its nodes.
        active: std.atomic.Value(bool) = .init(false),
        /// Workers inside a block, which `end` waits out.
        inflight: std.atomic.Value(u32) = .init(0),
        quit: std.atomic.Value(bool) = .init(false),
        rt: ?Rt = null,
        /// The I/O workgroup workers belong to (owned: one retain), and
        /// its generation; workers rejoin when it moves and ack.
        wg: std.atomic.Value(?*anyopaque) = .init(null),
        wg_gen: std.atomic.Value(u32) = .init(0),
        wg_acks: std.atomic.Value(u32) = .init(0),
        /// Workers a live block may wake: the workgroup's parallel-thread
        /// limit, less the I/O thread itself.
        wg_helpers: std.atomic.Value(u32) = .init(0),
        /// The I/O thread of the workgroup the workers joined, taken from
        /// the first live block after a move (0: not seen yet). A live block
        /// on any other thread (miniaudio rerouted the device on its own)
        /// renders serially and asks for a rejoin.
        io_thread: std.atomic.Value(usize) = .init(0),
        /// Set from audio or control: the UI should move the workers again
        /// (`setWorkgroup`) — the device moved, or an offline render may have
        /// cost the workers their real-time policy.
        rejoin: std.atomic.Value(bool) = .init(false),
        /// Watchdog (rendering thread only). A live block's waits on
        /// helpers, in mach ticks; `wait_limit` is a quarter of the block
        /// period. STRIKES blocks in a row over it and live blocks render
        /// serially until the workers move again (a demoted worker gives
        /// no other sign).
        live_block: bool = false,
        block_wait: u64 = 0,
        wait_limit: u64 = std.math.maxInt(u64),
        strikes: u8 = 0,
        watchdog_trips: std.atomic.Value(u32) = .init(0),
        /// The device's block period, ns: the workers' time-constraint
        /// period, read when they (re)join. Rt's until the device says.
        period_ns: std.atomic.Value(u64) = .init(0),

        pub fn create(alloc: std.mem.Allocator, ctx: *Ctx, workers: usize, rt: ?Rt) !*Self {
            const self = try alloc.create(Self);
            errdefer alloc.destroy(self);
            self.* = .{ .ctx = ctx, .rt = rt };
            if (rt) |r| {
                self.period_ns.store(r.period_ns, .seq_cst);
                self.wait_limit = nsToTicks(r.period_ns / 4);
            }
            if (semaphore_create(mach_task_self_, &self.sem, SYNC_POLICY_FIFO, 0) != 0) return error.SemaphoreCreate;
            errdefer _ = semaphore_destroy(mach_task_self_, self.sem);
            if (semaphore_create(mach_task_self_, &self.completion, SYNC_POLICY_FIFO, 0) != 0) return error.SemaphoreCreate;
            errdefer _ = semaphore_destroy(mach_task_self_, self.completion);
            const n = @min(workers, MAX_WORKERS);
            errdefer self.stopWorkers();
            while (self.n < n) : (self.n += 1) {
                self.threads[self.n] = try std.Thread.spawn(.{}, run, .{ self, self.n + 1 });
            }
            return self;
        }

        pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
            self.stopWorkers();
            if (self.wg.load(.seq_cst)) |wg| os_release(wg);
            _ = semaphore_destroy(mach_task_self_, self.sem);
            _ = semaphore_destroy(mach_task_self_, self.completion);
            alloc.destroy(self);
        }

        /// Device stopped, UI thread: move the workers into the I/O workgroup `wg` (taking
        /// over its retain; null: none), each as it next wakes, and have them
        /// re-request real-time policy. Waits until every worker has left the
        /// old one, then releases it. Without real-time workers, `wg` is
        /// released at once. Refused (false, `wg` released, rejoin left
        /// pending) while a block is open: a render is still running.
        /// Device stopped, UI thread: the period the device actually runs.
        /// Workers take it on their next setWorkgroup move; the watchdog
        /// budget at once.
        pub fn setPeriod(self: *Self, ns: u64) void {
            if (self.rt == null or ns == 0) return;
            self.period_ns.store(ns, .seq_cst);
            self.wait_limit = nsToTicks(ns / 4);
        }

        pub fn setWorkgroup(self: *Self, wg: ?*anyopaque) bool {
            if (self.active.load(.seq_cst)) {
                if (wg) |w| os_release(w);
                self.rejoin.store(true, .seq_cst);
                return false;
            }
            self.rejoin.store(false, .seq_cst);
            self.strikes = 0;
            if (self.rt == null or self.n == 0) {
                if (wg) |w| os_release(w);
                return true;
            }
            self.wg_ready.store(0, .seq_cst);
            self.rt_ready.store(0, .seq_cst);
            self.io_thread.store(0, .seq_cst);
            const limit: u32 = if (wg) |w| @intCast(@max(os_workgroup_max_parallel_threads(w, null), 1)) else 1;
            self.wg_helpers.store(@min(limit - 1, @as(u32, @intCast(self.n))), .seq_cst);
            const old = self.wg.swap(wg, .seq_cst);
            self.wg_acks.store(0, .seq_cst);
            _ = self.wg_gen.fetchAdd(1, .seq_cst);
            // A worker takes any wake-up, so keep waking until all have
            // acked; a spare wake-up finds no block open and sleeps again.
            const n: u32 = @intCast(self.n);
            while (self.wg_acks.load(.seq_cst) < n) {
                for (0..self.n) |_| _ = semaphore_signal(self.sem);
                _ = usleep(500);
            }
            if (old) |w| os_release(w);
            return true;
        }

        /// Any thread: ask the UI to move the workers again.
        pub fn requestRejoin(self: *Self) void {
            self.rejoin.store(true, .seq_cst);
        }

        pub fn rejoinRequested(self: *const Self) bool {
            return self.rejoin.load(.seq_cst);
        }

        fn stopWorkers(self: *Self) void {
            self.quit.store(true, .seq_cst);
            for (0..self.n) |_| _ = semaphore_signal(self.sem);
            for (self.threads[0..self.n]) |t| t.join();
            self.n = 0;
        }

        /// Open a block with `nodes` nodes and wake up to nodes - 1
        /// workers. False when none were woken: no `end` needed.
        pub fn begin(self: *Self, nodes: usize, realtime: bool) bool {
            if (realtime and !(self.liveReady() and self.onIoThread())) return false;
            const cap: usize = if (realtime) self.wg_helpers.load(.monotonic) else self.n;
            const k = @min(cap, nodes -| 1);
            if (k == 0) return false;
            self.live_block = realtime;
            self.block_wait = 0;
            self.active.store(true, .seq_cst);
            for (0..k) |_| _ = semaphore_signal(self.sem);
            return true;
        }

        /// Close the block (all its nodes are done): wait for the workers
        /// still inside it to leave.
        pub fn end(self: *Self) void {
            self.active.store(false, .seq_cst);
            while (true) {
                const n = self.inflight.load(.seq_cst);
                if (n == 0) break;
                self.waitForChange(&self.inflight, n);
            }
            if (self.live_block) self.judgeBlock();
        }

        /// Live block closed: count it against the watchdog. Tripping
        /// clears workgroup admission, so `liveReady` fails from the next
        /// block on, and asks the UI to move the workers (which re-requests
        /// their real-time policy and re-admits them).
        fn judgeBlock(self: *Self) void {
            if (self.block_wait <= self.wait_limit) {
                self.strikes = 0;
                return;
            }
            self.strikes += 1;
            if (self.strikes < STRIKES) return;
            self.strikes = 0;
            self.wg_ready.store(0, .seq_cst);
            self.rejoin.store(true, .seq_cst);
            _ = self.watchdog_trips.fetchAdd(1, .monotonic);
        }

        /// A live callback may depend only on workers that obtained both
        /// realtime scheduling and membership in the current I/O workgroup.
        pub fn liveReady(self: *const Self) bool {
            if (self.rt == null or self.wg.load(.seq_cst) == null) return false;
            const mask = (@as(u32, 1) << @intCast(self.n)) - 1;
            return self.rt_ready.load(.seq_cst) == mask and self.wg_ready.load(.seq_cst) == mask;
        }

        /// The calling live callback runs on the I/O thread the workers'
        /// workgroup belongs to. The first live block after a move names
        /// it; a block on another thread asks for a rejoin. pthread_self
        /// reads a register: no call into the kernel.
        fn onIoThread(self: *Self) bool {
            const me = @intFromPtr(pthread_self());
            const seen = self.io_thread.load(.monotonic);
            if (seen == me) return true;
            if (seen == 0 and self.io_thread.cmpxchgStrong(0, me, .monotonic, .monotonic) == null) return true;
            self.rejoin.store(true, .monotonic);
            return false;
        }

        fn notifyProgress(self: *Self) void {
            if (self.waiting.swap(false, .seq_cst)) _ = semaphore_signal(self.completion);
        }

        /// The rendering thread alone waits here. Arm before rechecking a
        /// seq_cst counter: a completion either changes the counter before
        /// the check, or observes the waiter and signals. No lost wakeup.
        pub fn waitForChange(self: *Self, counter: anytype, observed: anytype) void {
            self.waiting.store(true, .seq_cst);
            if (counter.load(.seq_cst) == observed) {
                // mach_absolute_time reads the commpage: no kernel call.
                const t0 = if (self.live_block) mach_absolute_time() else 0;
                _ = semaphore_wait(self.completion);
                if (self.live_block) self.block_wait +|= mach_absolute_time() - t0;
            }
            self.waiting.store(false, .seq_cst);
        }

        fn run(self: *Self, my_slot: usize) void {
            _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
            if (self.rt != null) {
                if (setTimeConstraint(self.period_ns.load(.seq_cst))) {
                    _ = self.rt_ready.fetchOr(@as(u32, 1) << @intCast(my_slot - 1), .seq_cst);
                } else std.log.warn("render worker {}: real-time scheduling refused; live callbacks use serial rendering", .{my_slot});
            }
            var scratch: Scratch = undefined;
            var joined: ?*anyopaque = null;
            var token: JoinToken = .{};
            var gen: u32 = 0;
            while (true) {
                _ = semaphore_wait(self.sem);
                if (self.quit.load(.seq_cst)) {
                    if (joined) |w| os_workgroup_leave(w, &token);
                    return;
                }
                const g = self.wg_gen.load(.seq_cst);
                if (g != gen) {
                    gen = g;
                    // XNU demotes a time-constraint thread that overruns
                    // its budget (an offline render runs workers flat
                    // out); every move re-requests the policy.
                    if (self.rt != null) {
                        if (setTimeConstraint(self.period_ns.load(.seq_cst)))
                            _ = self.rt_ready.fetchOr(@as(u32, 1) << @intCast(my_slot - 1), .seq_cst);
                    }
                    if (joined) |w| os_workgroup_leave(w, &token);
                    joined = self.wg.load(.seq_cst);
                    if (joined) |w| {
                        token = .{};
                        if (os_workgroup_join(w, &token) != 0) {
                            std.log.warn("render worker {}: could not join the audio workgroup", .{my_slot});
                            joined = null;
                        } else _ = self.wg_ready.fetchOr(@as(u32, 1) << @intCast(my_slot - 1), .seq_cst);
                    }
                    _ = self.wg_acks.fetchAdd(1, .seq_cst);
                }
                // Enter, then look: `end` either sees us inside or we see
                // the block closed (one total order over both atomics).
                _ = self.inflight.fetchAdd(1, .seq_cst);
                while (self.active.load(.seq_cst)) {
                    if (!work(self.ctx, &scratch, my_slot)) break;
                    self.notifyProgress();
                }
                _ = self.inflight.fetchSub(1, .seq_cst);
                self.notifyProgress();
            }
        }
    };
}

test "realtime: a live block on another I/O thread renders serially and asks for a rejoin" {
    const Ctx = struct {};
    const Scratch = struct {};
    const P = Pool(Ctx, Scratch, struct {
        fn work(_: *Ctx, _: *Scratch, _: usize) bool {
            return false;
        }
    }.work);
    var ctx: Ctx = .{};
    const p = try P.create(std.testing.allocator, &ctx, 0, null);
    defer p.destroy(std.testing.allocator);

    // The first live block names the I/O thread; later ones on it pass.
    try std.testing.expect(p.onIoThread());
    try std.testing.expect(p.onIoThread());
    try std.testing.expect(!p.rejoinRequested());

    // A rerouted device calls back on a new thread: no workers, rejoin.
    var other_ok = true;
    const t = try std.Thread.spawn(.{}, struct {
        fn run(pp: *P, ok: *bool) void {
            ok.* = pp.onIoThread();
        }
    }.run, .{ p, &other_ok });
    t.join();
    try std.testing.expect(!other_ok);
    try std.testing.expect(p.rejoinRequested());

    // Moving the workers clears the request.
    try std.testing.expect(p.setWorkgroup(null));
    try std.testing.expect(!p.rejoinRequested());
}

test "realtime: the device's actual period moves the watchdog's budget and the workers' policy" {
    const Ctx = struct {};
    const Scratch = struct {};
    const P = Pool(Ctx, Scratch, struct {
        fn work(_: *Ctx, _: *Scratch, _: usize) bool {
            return false;
        }
    }.work);
    var ctx: Ctx = .{};
    const p = try P.create(std.testing.allocator, &ctx, 0, .{ .period_ns = 256 * std.time.ns_per_s / 48_000 });
    defer p.destroy(std.testing.allocator);
    const asked = p.wait_limit;
    // A Bluetooth output that runs 1024 frames whatever was asked.
    p.setPeriod(1024 * std.time.ns_per_s / 48_000);
    try std.testing.expectEqual(@as(u64, 1024 * std.time.ns_per_s / 48_000), p.period_ns.load(.seq_cst));
    try std.testing.expect(p.wait_limit > 3 * asked);
}

test "realtime: watchdog drops slow live blocks to serial and asks for a rejoin" {
    const Ctx = struct {};
    const Scratch = struct {};
    const P = Pool(Ctx, Scratch, struct {
        fn work(_: *Ctx, _: *Scratch, _: usize) bool {
            return false;
        }
    }.work);
    var ctx: Ctx = .{};
    // 256 frames at 48 kHz: a 1.33 ms wait limit.
    const p = try P.create(std.testing.allocator, &ctx, 0, .{ .period_ns = 256 * std.time.ns_per_s / 48_000 });
    defer p.destroy(std.testing.allocator);
    const all: u32 = 0b11;

    // A real wait on the completion semaphore is measured.
    var counter = std.atomic.Value(u32).init(0);
    p.live_block = true;
    p.block_wait = 0;
    const t = try std.Thread.spawn(.{}, struct {
        fn run(pp: *P, c: *std.atomic.Value(u32)) void {
            var ts: std.c.timespec = .{ .sec = 0, .nsec = 20 * std.time.ns_per_ms };
            _ = std.c.nanosleep(&ts, null);
            _ = c.fetchAdd(1, .seq_cst);
            pp.notifyProgress();
        }
    }.run, .{ p, &counter });
    p.waitForChange(&counter, 0);
    t.join();
    try std.testing.expect(p.block_wait > p.wait_limit);

    // One slow block, then a quick one: no trip.
    p.wg_ready.store(all, .seq_cst);
    p.judgeBlock();
    p.block_wait = 0;
    p.judgeBlock();
    try std.testing.expectEqual(all, p.wg_ready.load(.seq_cst));
    try std.testing.expect(!p.rejoinRequested());

    // STRIKES slow blocks in a row: admission cleared, rejoin requested.
    for (0..STRIKES) |_| {
        p.block_wait = p.wait_limit + 1;
        p.judgeBlock();
    }
    try std.testing.expectEqual(@as(u32, 0), p.wg_ready.load(.seq_cst));
    try std.testing.expect(p.rejoinRequested());
    try std.testing.expectEqual(@as(u32, 1), p.watchdog_trips.load(.monotonic));

    // Moving the workers clears the request and the strikes.
    try std.testing.expect(p.setWorkgroup(null));
    try std.testing.expect(!p.rejoinRequested());
    try std.testing.expectEqual(@as(u8, 0), p.strikes);
}
