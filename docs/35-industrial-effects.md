# 35 — Live buffers, modal resonators and frequency shifting

Three native fy effects extend Slab's audio manipulation palette. They
use the normal insert/send routing, presets and automation; no new project
format or plugin host is involved. Source changes take effect in newly
loaded instances, as with the existing machines.

| ID | Panel | Role |
|---|---|---|
| `buffer2` | Buffer Loom | Live stereo capture, granular scatter, reverse grains, repeat/stutter |
| `resonator2` | Modal Bank | Eight tuned, damped modes per channel, excited by incoming audio |
| `shift2` | Sideband | Signed frequency shifting in Hz, ring modulation, shifted feedback |

Exact parameter IDs, ranges, switch indices and preset descriptions are
generated in [20-machine-reference.md](20-machine-reference.md). A preset
stores switch **indices**, while slabkit accepts labels. All three process
true stereo in one pass; left/right audio history remains independent.

## Buffer Loom

Put it after a foley kit, break, percussion bus or texture. The input is
recorded into two host-allocated rings. **FREEZE** stops writes and holds
the write head; it does not mute the dry input. Capture first, then freeze.
A new/reset instance frozen before capture is silent on its wet path.
Captured audio is live state: presets/projects do not store the rings, and
transport reset clears them.

**GRAINS** launches up to eight Hann-windowed grains. **SIZE MS** is each
grain's length, **DENSITY** launches per second, and **POS** chooses its
lookback within **SPAN** (0 is newest safe history, 1 is oldest).
**SPRAY** scatters that position; **PITCH** is semitones, **JITTER** is
per-grain pitch variation in semitones, and **REVERSE** changes reading
direction. **WIDTH** distributes grains in stereo without summing the
input channels. Grain position, speed, size, reverse and pan are latched
at launch; edits affect subsequent grains. Sounding grains finish.

With **SYNC**, **DIV** governs the launch interval instead of DENSITY.
SPAN remains the history window. The launch clock runs from reset;
SYNC sets its interval, rather than re-anchoring its phase to a locator.
Launch rate is capped at 32 Hz. Size
is capped by available history, reading speed and the eight-slot overlap
budget, so short captures and high pitches may produce shorter grains
than requested. Overlap gain is compensated. Arbitrary grain positions
can interfere on sustained tones; this is a texture processor, rather
than transparent monophonic pitch correction (audio clips offer VOICE).

**REPEAT** captures a recent window and loops it. Free SPAN determines
the window length; SYNC uses DIV. Each loop latches its window and reverse
direction at its boundary, with seam fades up to 2 ms. PITCH changes the
read speed and loop duration. FREEZE holds the recorded source, while
pitch/repeat/grain controls remain playable. Mode changes crossfade over
approximately 5 ms.

FB recirculates a bounded wet signal into capture; it has no effect on a
frozen ring. TONE filters incoming capture with a four-pole lowpass. The
capture cutoff also falls for upward pitch/jitter. Four-point Hermite
interpolation reads grains and loops. Changing pitch upwards after
freezing cannot refilter the stored recording, so bright frozen material
can alias at high rates; record with a lower TONE for that use.

The two rings reserve 4.1 seconds at the host's 96 kHz buffer allocation
rate (about 6.3 MB total). The accessible history window is at most four
seconds. Audio processing allocates nothing. A negative declared tail
keeps the machine processing through silence, retaining frozen captures
and preparing future live input.

Start with `steel-scrambler` for chopped industrial hits,
`pneumatic-repeat` for clocked stutter, or `capture-cloud` and then FREEZE
for a sustained texture. `reverse-grains` and `half-speed-loop` explore
different reading directions/rates.

## Modal Bank

Incoming audio excites eight parallel damped complex resonators.
**HZ** sets the fundamental. **STRING** uses harmonics 1–8; **PIPE** uses
odd harmonics 1–15; **PLATE** uses a stylized inharmonic series. These are
sound-design families, not measured models of a particular physical object.
**INHARM** stretches upper mode frequencies further.

**DECAY** is the fundamental's T60: seconds to decay by 60 dB in amplitude.
**DAMP** shortens higher modes' decay. Pole radius is derived from sample
rate and T60; **SPREAD** offsets left/right modal frequencies by a small
number of Hz while preserving pole radius. Modes above 0.45 of sample rate
are omitted. State is independent per channel; SPREAD detunes the modes
without cross-feeding audio. Set SPREAD to zero to retain a mono source.

EXCITE is input drive in dB into a bounded tanh excitation. Modal peak
gains and weights are normalized before summing, so long decays ring
without an uncontrolled resonance gain. Consequently an isolated impulse
can be quiet on the wet path. Noise bursts, rattles, brushed metal and
longer foley excite it more strongly; use LEVEL or a return gain to bring
up a fully wet part. LEVEL affects both dry and wet. An 18-second declared
tail protects the maximum 12-second decay from idle skipping.

`steel-body` and `short-iron` suit percussion. `harmonic-string` makes
tuned harmonic ringing; `pipe-chamber` introduces odd modes;
`drone-body` uses long low resonances.

## Sideband

In **SHIFT** mode, HZ adds the same frequency offset to each partial.
Positive values shift upwards; negative values shift downwards. A 1 kHz
tone at +250 Hz becomes 1.25 kHz, without the equally strong 750 Hz
sideband of ring modulation. This changes harmonic relationships, unlike
pitch transposition. Frequencies crossing zero reflect when represented
as real audio.

An IIR quadrature pair creates the single-sideband signal. Its rejection
is approximate, particularly near DC and Nyquist. It also has
frequency-dependent phase; a 0 Hz fully wet shift is not a phase-neutral
bypass. MIX at zero and LEVEL at 0 dB pass the original samples exactly.
SPREAD offsets the two channels' carrier frequencies symmetrically around
HZ, retaining independent input signals.

**RING** mode multiplies input by a sinusoidal carrier, retaining both
sum and difference sidebands. FB sends bounded wet audio back into the
processor. A DC blocker and four-pole lowpass control that loop; TONE also
limits bandwidth before shifting. The lowpass cutoff automatically leaves
space below Nyquist for the largest carrier offset. Oscillator phase
persists between blocks and is normalized at block boundaries.

Use `slow-sidebands` for slow movement, `warped-steel` for inharmonic
foley, `ring-machine` for two-sided modulation, or the spiral/smear presets
for shifted feedback. Output level applies after the dry/wet blend.

The quadrature topology and pole values follow
[Olli Niemitalo's allpass-pair design](https://yehar.com/blog/?p=368).
The general frequency-shifting method is described in
[Miller Puckette's single-sideband modulation chapter](https://msp.ucsd.edu/techniques/v0.06/book-html/node148.html).
The fy recurrence and machine implementation are authored in this repo.

## Audition and verification

Generate a short comparison project and render it with the native engine:

```sh
zig build -Doptimize=ReleaseFast
PYTHONPATH=tools python3 tools/demo_industrial_machines.py --render
zig-out/bin/slab scratch/industrial-machines/demo.slab
```

The five four-bar sections use the same foley phrase: dry, buffer,
resonator, shifter, then a combined chain. All sources are collected into
the scratch package. The CC0 factory foley was generated with Stable
Audio, as identified in its factory preset notes; it is not field audio.
Fixed output trims bring the sections to roughly similar loudness. The
demo is a patch audition, not a mastered song or a blind instrument
fidelity comparison.

Adapter tests check signed sideband suppression at 44.1/48/96 kHz, ring
sidebands, exact dry bypass, modal pitch and T60, independent channels,
freeze retention, reset/ring reinjection, granular octave transposition,
block partition invariance, preset loading, declared tails, and bounded
output under dense/jittered feedback settings. The normal headless bench
also supplies impulse, sine, sweep, ladder and burst reports:

```sh
zig build test
zig build bench -Doptimize=ReleaseFast -- machines/buffer2 machines/resonator2 machines/shift2 --no-sheets
```

Measurements establish numerical behavior and cost; they do not replace
auditioning the presets and automation in a mix.
