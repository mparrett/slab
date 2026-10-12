# 36 — Phaser

`phaser2` is a native stereo allpass phaser with four, six or twelve
stages, signed resonance, manual sweep and a free/tempo-locked LFO.
It uses normal inserts, sends, automation and presets. It adds no project
format changes, assets or external dependencies.

## Design references

The [Moog MF-103S manual](https://moogconnect.net/m/mfs/mf-103s.html)
describes six/twelve-stage phasing, sweep and resonance, a wide-rate LFO,
and complementary main/aux outputs. The
[MXR Phase 95 description](https://www.jimdunlop.com/mxr-phase-95/)
explains four-stage Phase 90 operation and the feedback-free Script
character. Those topologies and performance controls informed this
machine. The fy algorithm is original Slab code, not a measured component
model, circuit emulation or reproduction of either manufacturer's DSP.

## Controls

Exact parameter IDs, ranges, switch indices and nine factory presets are
in [20-machine-reference.md](20-machine-reference.md#phaser2).

- **STAGES** selects the four-, six- or twelve-stage tap. All twelve
  stages keep processing; tap selection crossfades over roughly 10 ms.
- **SWEEP HZ** is each stage's center frequency. **DEPTH OCT** is the LFO
  excursion in octaves either side of that center. Zero depth gives a
  static phaser for manual/automated sweep. The instantaneous frequency
  stays between 20 Hz and 0.45 of the sample rate.
- **RES** is signed feedback, limited to ±0.9. Positive feedback sharpens
  MAIN peaks; negative feedback changes the emphasis. Resonance has
  compensation: the maximum static linear gain is unity, rather than
  allowing resonant peaks to become progressively louder. Strong
  resonance can reduce average loudness; use LEVEL or a return fader.
- **RATE HZ** spans 0.01–250 Hz in FREE mode. Above about 20 Hz, try it
  as a metallic timbre effect. **SYNC** uses DIV instead: cycle durations
  from four bars to 1/32, including dotted/triplet options. Synced phase
  follows the host's quarter-note position, including nonzero starts and
  seeks, and stays aligned during automation sub-blocks. Free phase
  persists between blocks and starts at zero after reset.
- **SHAPE** chooses sine or triangle. **SPREAD DEG** offsets the right
  LFO by 0–180 degrees. Zero retains mono for identical inputs; 180 gives
  opposite sweeps. Audio channels never cross-feed.
- **DRIVE DB** adds a tanh input curve to the processed path, with
  compensation that preserves small-signal gain. Zero is exactly linear.
  This optional curve is not oversampled: very bright, strongly driven
  material can alias. For heavier, oversampled distortion use Saturator
  before the phaser instead.
- **MAIN** adds dry and allpass signals; **AUX** subtracts them, exchanging
  peaks and notches. **MIX** blends original input with that completed
  phaser response. At 1 it is already the characteristic dry/allpass mix;
  it is not an isolated allpass/vibrato output. MIX zero and LEVEL zero
  are exact sample bypass after the control transition settles.
- **LEVEL DB** trims the final blend. Continuous controls also have a
  per-sample 10 ms smoother; a continuous automation curve has this
  additional lag. Polarity switches crossfade. SHAPE, SYNC and DIV are
  stepped; changing them can alter the modulation phase immediately.

Start with `four-stage-silk` for a restrained pedal-like sweep,
`six-stage-keys` for electric piano, `twelve-stage-orbit` for wide synth
motion, or `steel-vortex` for industrial foley. `clockwork-funk` follows
the song clock; `audio-rate-metal` explores fast modulation.

## DSP and verification

Each stage is a normalized first-order lattice. Its rotation conserves
input/state energy even as the frequency changes. A bilinear prewarp maps
the center to the current sample rate. The feedback loop is solved
algebraically per sample, avoiding a sample-delay error in its resonance.
Inactive taps remain warm; crossfaded feedback uses the same tap weights
as the audible signal. All state is fixed size. Tiny lattice tails are
flushed below 1e-24; the 20-second declared tail allows the slowest
high-resonance response to decay before idle skipping.

The raw adapter now gives block-prepare the actual beat and frame count
of each automation/smoothing sub-block. Previously every sub-block saw
the outer block's beat, which would restart beat-relative modulation.

Tests check predicted notch positions and static feedback transfer at
44.1/48/96 kHz, exact dry bypass, mono/stereo behavior, complementary
outputs, block partition invariance, beat-periodic sweeps, clock
alignment under no-op automation at a nonzero beat, factory presets,
extreme parameter/stage changes and the declared tail. Run:

```sh
zig build test
zig build bench -Doptimize=ReleaseFast -- machines/phaser2 --no-sheets
PYTHONPATH=tools python3 tools/demo_phaser.py --render
zig-out/bin/slab scratch/phaser-audition/demo.slab
```

The demo prints one native Rhodes/synth/foley phrase, then reuses its
exact audio for dry and nine preset sections. The foley is Slab's
synthetic CC0 factory anvil. Audition compensation uses track faders,
limited to ±18 dB; it is written to `audition-trims.json` and never changes
the preset files. Generated projects and audio stay in scratch. Numeric
tests and level matching do not substitute for listening.
