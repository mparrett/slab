( buffer.fy - live stereo capture, eight bounded grains, or repeat/stutter.
  Two 4.1-second host rings; no allocation, locks or run-time loops.
  A grain stores its own position, speed, length and pan on launch.
  Changes therefore affect new grains without moving sounding grains.
  FREEZE stops capture, retaining the same write head and valid history.
  Grain duration is capped to the available history and eight-slot budget. )
include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"
include "../00-primitives/rand.fy"
include "../04-filters/tpt_svf.fy"

ustruct: BfGrain f64 pos f64 age f64 length f64 speed f64 pan ;
ustruct: BufferState
  f64 bl f64 br f64 len f64 len-r f64 write f64 filled
  f64 timer f64 next f64 rng
  BfGrain g0 BfGrain g1 BfGrain g2 BfGrain g3
  BfGrain g4 BfGrain g5 BfGrain g6 BfGrain g7
  f64 phase f64 loop-start f64 loop-len f64 loop-reverse f64 mode-z
  f64 wet-l f64 wet-r
  f64 ll1 f64 ll2 f64 ll3 f64 ll4
  f64 rl1 f64 rl2 f64 rl3 f64 rl4
;
ustruct: BufferParams
  f64 mode f64 freeze f64 span f64 position f64 grain-ms f64 density
  f64 sync f64 div f64 pitch f64 spray f64 jitter f64 reverse
  f64 width f64 feedback f64 tone f64 mix f64 out
  f64 span-n f64 grain-n f64 period f64 rate f64 gain f64 lp-g
  f64 edge f64 mode-a
;

dsp: bf-wrap | pos len -- i | pos len f/ ffrac len f* ;

( Four-point Hermite interpolation, with every neighbour wrapped. )
dsp: bf-read | buf len pos -- y |
  pos len bf-wrap | p | p floor | i | p i f- | f |
  buf i 1.0 f- len bf-wrap f@i | xm |
  buf i f@i | x0 |
  buf i 1.0 f+ len bf-wrap f@i | x1 |
  buf i 2.0 f+ len bf-wrap f@i | x2 |
  x1 xm f- 0.5 f* | c1 |
  xm x0 2.5 f* f- x1 2.0 f* f+ x2 0.5 f* f- | c2 |
  x2 xm f- 0.5 f* x0 x1 f- 1.5 f* f+ | c3 |
  c3 f f* c2 f+ f f* c1 f+ f f* x0 f+
;

dsp: buffer-block-prepare | ctx:Ctx state p:BufferParams -- |
  60.0 ctx.tempo 20.0 999.0 fclamp f/ p.div f* | synced |
  p.mode 0.5 f< p.span p.sync 0.5 f< p.span synced select select
    0.01 4.0 fclamp ctx.sr f* -> p.span-n
  p.sync 0.5 f< p.density 1.0 synced f/ select 1.0 32.0 fclamp | density |
  ctx.sr density f/ -> p.period
  p.grain-ms 0.001 f* ctx.sr f* p.period 7.8 f* fmin -> p.grain-n
  p.pitch 12.0 f/ exp2 -> p.rate
  p.out fabs 0.00001 f< 1.0 p.out db>lin select -> p.gain
  ctx.sr 0.002 f* -> p.edge
  1.0 -1.0 ctx.sr 0.005 f* f/ exp f- -> p.mode-a
  ( Filter capture before up-pitched reading; frozen material keeps its
    recorded bandwidth. New pitch settings do not rewrite a frozen ring. )
  p.pitch p.jitter f+ 12.0 f/ exp2 1.0 fmax | fastest |
  p.tone ctx.sr 0.45 f* fastest f/ fmin
    3.141592653589793 f* ctx.sr f/ tan-warp -> p.lp-g
;

dsp: bf-grain | g:BfGrain s:BufferState p:BufferParams slot launch r1 r2 r3 -- l r |
  s.filled p.span-n fmin | history |
  p.pitch r2 p.jitter f* f+ 12.0 f/ exp2 | rate |
  p.grain-n history 8.0 f- 0.0 fmax rate f/ fmin 2.0 fmax | gn |
  p.reverse 0.5 f< | forward |
  forward gn rate f* 4.0 f+ 4.0 select | youngest |
  forward history 4.0 f- history gn rate f* f- 4.0 f- select | oldest |
  p.position r1 p.spray f* f+ 0.0 1.0 fclamp | position |
  youngest oldest youngest f- 0.0 fmax position f* f+ | delay |
  launch s.next slot f= and | fire |
  fire s.write delay f- g.pos select -> g.pos
  fire 0.0 g.age select -> g.age
  fire gn g.length select -> g.length
  fire forward rate rate fneg select g.speed select -> g.speed
  fire r3 p.width f* g.pan select -> g.pan
  g.age g.length f< g.length 1.0 f> and mask>f | on |
  g.age g.length 1.0 fmax f/ | phase |
  1.0 phase 6.283185307179586 f* cos f- 0.5 f* on f* | env |
  g.length p.period f/ 0.5 f* 1.0 fmax | norm |
  env norm f/ | amp |
  g.pos g.age g.speed f* f+ | pos |
  s.bl& p@64 s.len pos bf-read amp f* 1.0 g.pan f- fsqrt f*
  s.br& p@64 s.len pos bf-read amp f* 1.0 g.pan f+ fsqrt f*
  g.age 1.0 f+ g.length 1.0 f+ fmin -> g.age
;

dsp: bf-repeat | s:BufferState p:BufferParams -- l r |
  s.phase 1.0 f>= s.loop-len 1.0 f< or | restart |
  s.filled p.span-n fmin 4.0 fmax | length |
  restart s.write length f- s.loop-start select -> s.loop-start
  restart length s.loop-len select -> s.loop-len
  restart p.reverse s.loop-reverse select -> s.loop-reverse
  restart s.phase ffrac s.phase select | phase |
  s.loop-reverse 0.5 f< phase 1.0 phase f- select | read-phase |
  s.loop-start read-phase s.loop-len 3.0 f- f* f+ | pos |
  ( Two ms seam fades, capped to 1/4 of short loops. )
  s.loop-len 0.25 f* p.edge fmin 1.0 fmax | edge |
  phase 1.0 phase f- fmin s.loop-len f* edge f/ 0.0 1.0 fclamp
    s.filled 16.0 f> mask>f f* | amp |
  s.bl& p@64 s.len pos bf-read amp f*
  s.br& p@64 s.len pos bf-read amp f*
  phase p.rate s.loop-len 1.0 fmax f/ f+ -> s.phase
;

dsp: k-buffer-tick | io:Io ctx s:BufferState p:BufferParams -- |
  s.filled 16.0 f> s.timer 0.0 f<= and | launch |
  s.rng rand-next | r1 | r1 rand-next | r2 | r2 rand-next | r3 |
  r3 -> s.rng
  r1 2.0 f* 1.0 f- | r1 | r2 2.0 f* 1.0 f- | r2 |
  r3 2.0 f* 1.0 f- | r3 |
  s.g0& s p 0.0 launch r1 r2 r3 bf-grain | l0 r0 |
  s.g1& s p 1.0 launch r1 r2 r3 bf-grain | l1 r1g |
  s.g2& s p 2.0 launch r1 r2 r3 bf-grain | l2 r2g |
  s.g3& s p 3.0 launch r1 r2 r3 bf-grain | l3 r3g |
  s.g4& s p 4.0 launch r1 r2 r3 bf-grain | l4 r4 |
  s.g5& s p 5.0 launch r1 r2 r3 bf-grain | l5 r5 |
  s.g6& s p 6.0 launch r1 r2 r3 bf-grain | l6 r6 |
  s.g7& s p 7.0 launch r1 r2 r3 bf-grain | l7 r7 |
  l0 l1 f+ l2 f+ l3 f+ l4 f+ l5 f+ l6 f+ l7 f+ | gl |
  r0 r1g f+ r2g f+ r3g f+ r4 f+ r5 f+ r6 f+ r7 f+ | gr |
  launch s.next 1.0 f+ 8.0 f/ ffrac 8.0 f* s.next select -> s.next
  launch s.timer p.period f+ s.timer select 1.0 f- -1.0 fmax -> s.timer
  s p bf-repeat | rl rr |
  s.mode-z p.mode s.mode-z f- p.mode-a f* f+ | mode |
  mode -> s.mode-z
  gl 1.0 mode f- f* rl mode f* f+ | wl |
  gr 1.0 mode f- f* rr mode f* f+ | wr |
  wl tanh-fast -> s.wet-l  wr tanh-fast -> s.wet-r
  io.in-l s.wet-l p.feedback f* f+ | xl |
  io.in-r s.wet-r p.feedback f* f+ | xr |
  p.feedback 0.00001 f> xl tanh-fast xl select | xl |
  p.feedback 0.00001 f> xr tanh-fast xr select | xr |
  s.ll1& s.ll2& xl p.lp-g 0.923879532511287 tpt-svf-lp-step | xl |
  s.ll3& s.ll4& xl p.lp-g 0.38268343236509 tpt-svf-lp-step | xl |
  s.rl1& s.rl2& xr p.lp-g 0.923879532511287 tpt-svf-lp-step | xr |
  s.rl3& s.rl4& xr p.lp-g 0.38268343236509 tpt-svf-lp-step | xr |
  p.freeze 0.5 f<
  [ xl s.bl& p@64 s.write f!i  xr s.br& p@64 s.write f!i
    ( Keep the write index integral; a fractional wrap would accumulate
      roundoff and could write the same cell twice at an integer edge. )
    s.write 1.0 f+ | w1 |
    w1 s.len w1 0.0 fsel-lt -> s.write
    s.filled 1.0 f+ s.len 4.0 f- fmin -> s.filled ]
  [ ] ifte
  io.in-l 1.0 p.mix f- f* wl p.mix f* f+ p.gain f* -> io.out-l
  io.in-r 1.0 p.mix f- f* wr p.mix f* f+ p.gain f* -> io.out-r
;
