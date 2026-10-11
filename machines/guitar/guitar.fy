( guitar.fy - Fretwire Guitar: a waveguide electric guitar.

  The same plucked string as the bass [kernels/06-voices/string.fy], strung
  as a six-string guitar: six voices, one per string, and its own tuning,
  stiffness and pickups.  Fitted against Karoryfer's Emily [flatwounds,
  both pickups, direct] with tools/fit/string_fit.py.  Pitch curves bend
  or slide [MOTION].  Put Ampstack after it. )

include "../../kernels/06-voices/string.fy"
include "../lib/manifest.fy"

: manifest
  "Fretwire Guitar" voice-sample machine*
  "k-string-voice"       render!
  "string-note-on"       note-on!
  "string-note-off"      note-off!
  "string-note-expr"     note-expr!
  "string-block-prepare" block-prepare!
  "string-control" 64    control!
  6 voices!
  ( overlapping single notes up to a fourth apart: hammer-ons, pull-offs )
  5.0 legato-span!
  StringState.size  state-size!
  StringParams.size params-size!
  "ring" StringState.buf StringState.buf-len 0.03 buffer
  ( a six-string guitar in standard tuning; HF DEC, SOFT, THUMP and B
    are stated at its low E )
  StringParams.ref-hz 82.41 const-f64
  StringParams.b-ref 82.41 const-f64
  StringParams.hf-track 0.0 const-f64
  StringParams.out-g 0.75 const-f64
  StringParams.o1 82.41 const-f64   StringParams.o2 110.0 const-f64
  StringParams.o3 146.83 const-f64  StringParams.o4 196.0 const-f64
  StringParams.o5 246.94 const-f64  StringParams.o6 329.63 const-f64
  520.0 panel-w!

  "STRING" "DECAY"   "gt-decay"   StringParams.decay    0.3 40.0 12.0 curve-exp knob
  "STRING" "HF DEC"  "gt-hfdec"   StringParams.hf-decay 0.05 10.0 0.8 curve-exp knob
  "STRING" "KNEE"    "gt-knee"    StringParams.knee     1.0 32.0 5.0  curve-exp knob
  "STRING" "STIFF"   "gt-stiff"   StringParams.stiff    0.0 10.0 1.2  curve-lin knob
  "STRING" "RELEASE" "gt-release" StringParams.release  0.02 2.0 0.12 curve-exp knob
  "STRING" 3 strip

  "PLUCK" "POS"    "gt-pos"    StringParams.pos    0.04 0.5 0.17 curve-lin knob
  "PLUCK" "SOFT"   "gt-soft"   StringParams.soft   0.05 6.0 1.0  curve-exp knob
  "PLUCK" "SHAPE"  "gt-shape"  StringParams.shape  0.0 1.0 0.4   curve-lin knob
  "PLUCK" "NOISE"  "gt-noise"  StringParams.noise  0.0 1.0 0.15  curve-pow knob
  "PLUCK" 2 strip

  "PICKUP" "POS"  "gt-pickup" StringParams.pickup 0.04 0.5 0.24  curve-lin knob
  "PICKUP" "HAND" "gt-hand"   StringParams.hand   0.0 12.0 0.0  curve-lin knob
  "PICKUP" "TONE" "gt-tone"   StringParams.tone   300.0 12000.0 4500.0 curve-exp knob
  "PICKUP" "RES"  "gt-res"    StringParams.res    0.0 1.0 0.4   curve-lin knob
  "PICKUP" 2 strip

  "FEEL" "THUMP" "gt-thump" StringParams.thump 0.0 1.0 0.3 curve-lin knob
  "FEEL" "BUZZ"  "gt-buzz"  StringParams.buzz  0.0 1.0 0.0 curve-lin knob
  "FEEL" "MOTION" "gt-motion" StringParams.motion 0.0 switch
    "AUTO" 0.0 opt  "BEND" 1.0 opt  "SLIDE" 2.0 opt  as-list
  "FEEL" "SLIDE" "gt-slide" StringParams.slide 0.0 1.0 0.4 curve-lin knob
  "FEEL" "LEVEL" "gt-level" StringParams.level 0.0 1.0 0.5 curve-pow knob
  "FEEL" 3 strip

  1.0 row
    1.0 cell  "STRING" 1.0 item
    1.0 cell  "PLUCK" 1.0 item
  1.0 row
    1.0 cell  "PICKUP" 1.0 item
    1.0 cell  "FEEL" 1.0 item

  machine-desc
;
