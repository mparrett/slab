( bass.fy — Fretwire: a waveguide electric bass.

  The voice is the plucked-string waveguide in kernels/06-voices/string.fy;
  this file declares the machine.  Every voice owns a string: its delay
  loop is a host buffer, one per voice.

  Panel: STRING [how it rings] | PLUCK [how it is played] | PICKUP [where
  it is heard] | FEEL. )

include "../../kernels/06-voices/string.fy"
include "../lib/manifest.fy"

: manifest
  "Fretwire" voice-sample machine*
  "k-string-voice"       render!
  "string-note-on"       note-on!
  "string-note-off"      note-off!
  "string-note-expr"     note-expr!
  "string-block-prepare" block-prepare!
  "string-control" 64    control!
  4 voices!
  StringState.size  state-size!
  StringParams.size params-size!
  "ring" StringState.buf StringState.buf-len 0.045 buffer
  ( a four-string bass in standard tuning; B, HF DEC, SOFT, THUMP stated at its low end )
  StringParams.ref-hz 41.2 const-f64
  StringParams.b-ref 36.71 const-f64
  StringParams.hf-track 0.75 const-f64
  StringParams.out-g 2.25 const-f64
  StringParams.o1 41.2 const-f64   StringParams.o2 55.0 const-f64
  StringParams.o3 73.42 const-f64  StringParams.o4 98.0 const-f64
  StringParams.o5 1000000000.0 const-f64  StringParams.o6 1000000000.0 const-f64
  520.0 panel-w!

  "STRING" "DECAY"   "bs-decay"   StringParams.decay    0.3 40.0 12.0 curve-exp knob
  "STRING" "HF DEC"  "bs-hfdec"   StringParams.hf-decay 0.05 10.0 1.2 curve-exp knob
  "STRING" "KNEE"    "bs-knee"    StringParams.knee     1.0 32.0 9.0  curve-exp knob
  "STRING" "STIFF"   "bs-stiff"   StringParams.stiff    0.0 10.0 4.0  curve-lin knob
  "STRING" "RELEASE" "bs-release" StringParams.release  0.02 2.0 0.12 curve-exp knob
  "STRING" 3 strip

  "PLUCK" "POS"    "bs-pos"    StringParams.pos    0.04 0.5 0.14 curve-lin knob
  "PLUCK" "SOFT"   "bs-soft"   StringParams.soft   0.05 6.0 2.0  curve-exp knob
  "PLUCK" "SHAPE"  "bs-shape"  StringParams.shape  0.0 1.0 0.0   curve-lin knob
  "PLUCK" "NOISE"  "bs-noise"  StringParams.noise  0.0 1.0 0.15  curve-pow knob
  "PLUCK" 2 strip

  "PICKUP" "POS"  "bs-pickup" StringParams.pickup 0.04 0.5 0.2   curve-lin knob
  "PICKUP" "HAND" "bs-hand"   StringParams.hand   0.0 12.0 5.0  curve-lin knob
  "PICKUP" "TONE" "bs-tone"   StringParams.tone   300.0 12000.0 3200.0 curve-exp knob
  "PICKUP" "RES"  "bs-res"    StringParams.res    0.0 1.0 0.3   curve-lin knob
  "PICKUP" 2 strip

  "FEEL" "THUMP" "bs-thump" StringParams.thump 0.0 1.0 0.5 curve-lin knob
  "FEEL" "BUZZ"  "bs-buzz"  StringParams.buzz  0.0 1.0 0.0 curve-lin knob
  "FEEL" "MOTION" "bs-motion" StringParams.motion 0.0 switch
    "AUTO" 0.0 opt  "BEND" 1.0 opt  "SLIDE" 2.0 opt  as-list
  "FEEL" "SLIDE" "bs-slide" StringParams.slide 0.0 1.0 0.4 curve-lin knob
  "FEEL" "LEVEL" "bs-level" StringParams.level 0.0 1.0 0.55 curve-pow knob
  "FEEL" 3 strip

  1.0 row
    1.0 cell  "STRING" 1.0 item
    1.0 cell  "PLUCK" 1.0 item
  1.0 row
    1.0 cell  "PICKUP" 1.0 item
    1.0 cell  "FEEL" 1.0 item

  machine-desc
;
