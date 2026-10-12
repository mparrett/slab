( phaser2.fy - Moog/MXR-inspired allpass phaser; original Slab DSP. )
include "../../kernels/07-effects/phaser.fy"
include "../lib/manifest.fy"
: manifest
  "Phaser" effect-block machine*
  "k-phaser-tick" render! "phaser-block-prepare" block-prepare!
  PhaserState.size state-size! PhaserParams.size params-size!
  560.0 panel-w! stereo
  20.0 tail!
  "PHASE" "STAGES" "ph-stages" PhaserParams.stages 1.0 switch
    "4" 0.0 opt "6" 1.0 opt "12" 2.0 opt as-radio
  "PHASE" "SWEEP HZ" "ph-hz" PhaserParams.hz 30.0 8000.0 800.0 curve-exp knob
  "PHASE" "DEPTH OCT" "ph-depth" PhaserParams.depth 0.0 3.0 2.0 curve-lin knob
  "PHASE" "RES" "ph-feedback" PhaserParams.feedback -0.9 0.9 0.25 curve-lin knob
  "PHASE" 4 strip
  "LFO" "RATE HZ" "ph-rate" PhaserParams.rate 0.01 250.0 0.3 curve-exp knob
  "LFO" "SYNC" "ph-sync" PhaserParams.sync 0.0 switch
    "FREE" 0.0 opt "SYNC" 1.0 opt as-button
  "LFO" "DIV" "ph-div" PhaserParams.div 4.0 switch
    "4 BAR" 16.0 opt "2 BAR" 8.0 opt "1 BAR" 4.0 opt
    "1/2" 2.0 opt "1/4" 1.0 opt "1/8" 0.5 opt
    "1/16" 0.25 opt "1/32" 0.125 opt
    "1/4D" 1.5 opt "1/8D" 0.75 opt "1/8T" 0.3333333333333333 opt as-display
  "LFO" "SHAPE" "ph-shape" PhaserParams.shape 0.0 switch
    "SINE" 0.0 opt "TRI" 1.0 opt as-radio
  "LFO" 4 strip
  "OUT" "SPREAD DEG" "ph-spread" PhaserParams.spread 0.0 180.0 90.0 curve-lin knob
  "OUT" "DRIVE DB" "ph-drive" PhaserParams.drive 0.0 24.0 0.0 curve-lin knob
  "OUT" "MODE" "ph-mode" PhaserParams.mode 0.0 switch
    "MAIN" 0.0 opt "AUX" 1.0 opt as-radio
  "OUT" "MIX" "ph-mix" PhaserParams.mix 0.0 1.0 1.0 curve-lin knob
  "OUT" "LEVEL DB" "ph-out" PhaserParams.out -24.0 12.0 0.0 curve-lin knob
  "OUT" 5 strip
  1.0 row
    1.0 cell "PHASE" 1.0 item
    1.0 cell "LFO" 1.0 item
  1.0 row
    1.0 cell "OUT" 1.0 item
  machine-desc
;
