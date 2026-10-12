( resonator2.fy - tunable modal bank for drums, noise and foley. )
include "../../kernels/07-effects/resonator.fy"
include "../lib/manifest.fy"
: manifest
  "Modal Bank" effect-block machine*
  "k-resonator-tick" render! "resonator-block-prepare" block-prepare!
  ResonatorState.size state-size! ResonatorParams.size params-size!
  480.0 panel-w! stereo
  18.0 tail!
  "BODY" "HZ" "rs-hz" ResonatorParams.hz 30.0 2000.0 110.0 curve-exp knob
  "BODY" "MATERIAL" "rs-material" ResonatorParams.material 1.0 switch
    "STRING" 0.0 opt "PLATE" 1.0 opt "PIPE" 2.0 opt as-radio
  "BODY" "INHARM" "rs-inharm" ResonatorParams.inharm 0.0 1.0 0.1 curve-lin knob
  "BODY" 3 strip
  "RING" "DECAY" "rs-decay" ResonatorParams.decay 0.08 12.0 1.4 curve-exp knob
  "RING" "DAMP" "rs-damp" ResonatorParams.damp 0.0 1.0 0.4 curve-lin knob
  "RING" "SPREAD" "rs-spread" ResonatorParams.spread 0.0 8.0 0.0 curve-lin knob
  "RING" 3 strip
  "OUT" "EXCITE" "rs-drive" ResonatorParams.drive 0.0 24.0 6.0 curve-lin knob
  "OUT" "MIX" "rs-mix" ResonatorParams.mix 0.0 1.0 0.5 curve-lin knob
  "OUT" "LEVEL" "rs-out" ResonatorParams.out -24.0 24.0 6.0 curve-lin knob
  "OUT" 3 strip
  1.0 row
    1.0 cell "BODY" 1.0 item
    1.0 cell "RING" 1.0 item
    1.0 cell "OUT" 1.0 item
  machine-desc
;
