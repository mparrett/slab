( shift2.fy - frequency shifter and ring modulator. )
include "../../kernels/07-effects/shift.fy"
include "../lib/manifest.fy"

: manifest
  "Sideband" effect-block machine*
  "k-shift-tick" render!  "shift-block-prepare" block-prepare!
  ShiftState.size state-size!  ShiftParams.size params-size!
  440.0 panel-w!  stereo
  2.0 tail!
  "SHIFT" "HZ" "shift-hz" ShiftParams.hz -4000.0 4000.0 40.0 curve-lin knob
  "SHIFT" "SPREAD" "shift-spread" ShiftParams.spread -200.0 200.0 0.0 curve-lin knob
  "SHIFT" "MODE" "shift-mode" ShiftParams.mode 0.0 switch
    "SHIFT" 0.0 opt "RING" 1.0 opt as-radio
  "SHIFT" 3 strip
  "LOOP" "FB" "shift-fb" ShiftParams.feedback 0.0 0.85 0.0 curve-pow knob
  "LOOP" "TONE" "shift-tone" ShiftParams.tone 800.0 20000.0 16000.0 curve-exp knob
  "LOOP" 2 strip
  "OUT" "MIX" "shift-mix" ShiftParams.mix 0.0 1.0 0.5 curve-lin knob
  "OUT" "LEVEL" "shift-out" ShiftParams.out -24.0 12.0 0.0 curve-lin knob
  "OUT" 2 strip
  1.0 row
    1.5 cell "SHIFT" 1.0 item
    1.0 cell "LOOP" 1.0 item
    1.0 cell "OUT" 1.0 item
  machine-desc
;
