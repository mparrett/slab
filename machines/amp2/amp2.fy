( amp2.fy - Ampstack: an instrument amplifier and its cabinet.

  DSP in kernels/07-effects/amp.fy; this file declares the machine.
  Dual mono, 4x oversampled through the preamp and the power amp.  Put it
  after a bass or a guitar: VOICE picks the amp, CAB the speaker box, and
  BLEND brings the clean DI back in under it. )

include "../../kernels/07-effects/amp.fy"
include "../lib/manifest.fy"

: manifest
  "Ampstack" effect-block machine*
  "k-amp-tick"        render!
  "amp-block-prepare" block-prepare!
  AmpState.size  state-size!
  AmpParams.size params-size!
  AmpParams.lat latency!
  560.0 panel-w!

  "PREAMP" "VOICE" "amp-voice" AmpParams.voice 1.0 switch
    "BASS" 0.0 opt  "CLEAN" 1.0 opt  "BRIT" 2.0 opt  "HIGAIN" 3.0 opt  as-list span-rows
  "PREAMP" "GAIN"  "amp-gain"  AmpParams.gain  0.0 1.0 0.3 curve-lin knob
  "PREAMP" "TIGHT" "amp-tight" AmpParams.tight 10.0 400.0 20.0 curve-exp knob
  "PREAMP" 2 strip

  "TONE" "BASS"   "amp-bass"   AmpParams.bass     0.0 1.0 0.5 curve-lin knob
  "TONE" "MID"    "amp-mid"    AmpParams.mid      0.0 1.0 0.5 curve-lin knob
  "TONE" "TREBLE" "amp-treble" AmpParams.treble   0.0 1.0 0.5 curve-lin knob
  "TONE" "PRES"   "amp-pres"   AmpParams.presence 0.0 1.0 0.25 curve-lin knob
  "TONE" 4 strip

  "POWER" "MASTER" "amp-master" AmpParams.master 0.0 1.0 0.3 curve-lin knob
  "POWER" "SAG"    "amp-sag"    AmpParams.sag    0.0 1.0 0.3 curve-lin knob
  "POWER" 2 strip

  "CAB" "CAB" "amp-cab" AmpParams.cab 1.0 switch
    "OFF" 0.0 opt  "1x12" 1.0 opt  "4x12" 2.0 opt  "1x15" 3.0 opt  "8x10" 4.0 opt  "4x10" 5.0 opt  as-list span-rows
  "CAB" "MIC" "amp-mic" AmpParams.mic 0.0 1.0 0.2 curve-lin knob
  "CAB" 1 strip

  "OUT" "BLEND" "amp-blend" AmpParams.blend    0.0 1.0 0.0 curve-lin knob
  "OUT" "LEVEL" "amp-level" AmpParams.level-db -24.0 24.0 0.0 curve-lin knob
  "OUT" 1 strip

  1.0 row
    1.5 cell  "PREAMP" 1.0 item
    2.0 cell  "TONE" 1.0 item
  1.0 row
    1.0 cell  "POWER" 1.0 item
    1.5 cell  "CAB" 1.0 item
    1.0 cell  "OUT" 1.0 item

  machine-desc
;
