( cs80.fy - C-Beam 80: the Yamaha CS-80, eight notes of two channels.

  The voice is kernels/06-voices/cs80.fy and the circuit study behind it
  docs/38-cs80.md.  The panel is the CS-80's, slider for slider and in
  its order: the VOICE page carries Channel I over Channel II [VCO, VCF
  with its IL/AL envelope, VCA, touch], the CONTROL page the levers under
  the original's keyboard lid [sub oscillator, touch response, keyboard
  control, ring modulator, chorus/tremolo, MIX, BRILLIANCE, RESONANCE,
  pitch, portamento and sustain].  Sliders read 0..10 as the original's
  do; times are seconds.

  Play it with pressure: after touch is per note [slabkit's pressure
  lane, resting at 0.5], the CS-80's signature.  The famous brass is
  IL and AL both up, AFTER BRILLIANCE and LEVEL up, and the sub
  oscillator's sine to the VCO through TOUCH RESPONSE VCO. )

include "../../kernels/06-voices/cs80.fy"
include "../lib/manifest.fy"

( a channel's field offset )
: c1  CbParams.p1 + ;
: c2  CbParams.p2 + ;
: cb-feet
  "16'" 0.5 opt  "8'" 1.0 opt  "5 1/3'" 1.5 opt  "4'" 2.0 opt  "2 2/3'" 3.0 opt  "2'" 4.0 opt
  as-display ;
: cb-onoff  "OFF" 0.0 opt  "ON" 1.0 opt  as-button ;

( module prefix offset-fn -- : one channel's 27 sliders.  The strips are
  named "VCO I" .. "TOUCH II"; ids "cb1-.." and "cb2-..". )
: cb-chan-i
  "VCO I" "FEET"  "cb1-feet"    CbChanParams.feet c1 1 switch cb-feet
  "VCO I" "SPEED" "cb1-pwm-spd" CbChanParams.pwm-spd c1 0.2 200.0 6.0 curve-exp knob as-fader
  "VCO I" "PWM"   "cb1-pwm"     CbChanParams.pwm c1 0.0 10.0 0.0 curve-lin knob as-fader
  "VCO I" "PW"    "cb1-pw"      CbChanParams.pw c1 0.0 10.0 0.0 curve-lin knob as-fader
  "VCO I" "SQR"   "cb1-sqr"     CbChanParams.sqr c1 0 switch cb-onoff
  "VCO I" "SAW"   "cb1-saw"     CbChanParams.saw c1 1 switch cb-onoff
  "VCO I" "NOISE" "cb1-noise"   CbChanParams.noise-l c1 0.0 10.0 0.0 curve-pow knob as-fader
  "VCF I" "HPF"   "cb1-hpf"     CbChanParams.hpf c1 0.0 10.0 0.0 curve-lin knob as-fader
  "VCF I" "RES"   "cb1-res-h"   CbChanParams.res-h c1 0.0 10.0 0.0 curve-lin knob as-fader
  "VCF I" "LPF"   "cb1-lpf"     CbChanParams.lpf c1 0.0 10.0 5.5 curve-lin knob as-fader
  "VCF I" "RES"   "cb1-res-l"   CbChanParams.res-l c1 0.0 10.0 3.0 curve-lin knob as-fader
  "VCF I" "IL"    "cb1-il"      CbChanParams.il c1 0.0 10.0 6.0 curve-lin knob as-fader
  "VCF I" "AL"    "cb1-al"      CbChanParams.al c1 0.0 10.0 6.0 curve-lin knob as-fader
  "VCF I" "A"     "cb1-f-a"     CbChanParams.f-a c1 0.001 1.024 0.09 curve-exp knob as-fader
  "VCF I" "D"     "cb1-f-d"     CbChanParams.f-d c1 0.01 10.24 0.7 curve-exp knob as-fader
  "VCF I" "R"     "cb1-f-r"     CbChanParams.f-r c1 0.01 10.24 0.4 curve-exp knob as-fader
  "VCA I" "VCF"   "cb1-vcf-lvl" CbChanParams.vcf-lvl c1 0.0 10.0 9.0 curve-lin knob as-fader
  "VCA I" "SINE"  "cb1-sine"    CbChanParams.sine-l c1 0.0 10.0 0.0 curve-lin knob as-fader
  "VCA I" "A"     "cb1-a-a"     CbChanParams.a-a c1 0.001 1.024 0.03 curve-exp knob as-fader
  "VCA I" "D"     "cb1-a-d"     CbChanParams.a-d c1 0.01 10.24 3.0 curve-exp knob as-fader
  "VCA I" "S"     "cb1-a-s"     CbChanParams.a-s c1 0.0 10.0 9.0 curve-lin knob as-fader
  "VCA I" "R"     "cb1-a-r"     CbChanParams.a-r c1 0.01 10.24 0.4 curve-exp knob as-fader
  "VCA I" "LEVEL" "cb1-level"   CbChanParams.level c1 0.0 10.0 9.0 curve-lin knob as-fader
  "TOUCH I" "I BRIL" "cb1-i-bril" CbChanParams.i-bril c1 0.0 10.0 2.0 curve-lin knob
  "TOUCH I" "I LVL"  "cb1-i-lvl"  CbChanParams.i-lvl c1 0.0 10.0 5.0 curve-lin knob
  "TOUCH I" "A BRIL" "cb1-a-bril" CbChanParams.a-bril c1 0.0 10.0 5.0 curve-lin knob
  "TOUCH I" "A LVL"  "cb1-a-lvl"  CbChanParams.a-lvl c1 0.0 10.0 5.0 curve-lin knob
;

: cb-chan-ii
  "VCO II" "FEET"  "cb2-feet"    CbChanParams.feet c2 1 switch cb-feet
  "VCO II" "SPEED" "cb2-pwm-spd" CbChanParams.pwm-spd c2 0.2 200.0 6.0 curve-exp knob as-fader
  "VCO II" "PWM"   "cb2-pwm"     CbChanParams.pwm c2 0.0 10.0 0.0 curve-lin knob as-fader
  "VCO II" "PW"    "cb2-pw"      CbChanParams.pw c2 0.0 10.0 0.0 curve-lin knob as-fader
  "VCO II" "SQR"   "cb2-sqr"     CbChanParams.sqr c2 0 switch cb-onoff
  "VCO II" "SAW"   "cb2-saw"     CbChanParams.saw c2 1 switch cb-onoff
  "VCO II" "NOISE" "cb2-noise"   CbChanParams.noise-l c2 0.0 10.0 0.0 curve-pow knob as-fader
  "VCF II" "HPF"   "cb2-hpf"     CbChanParams.hpf c2 0.0 10.0 0.0 curve-lin knob as-fader
  "VCF II" "RES"   "cb2-res-h"   CbChanParams.res-h c2 0.0 10.0 0.0 curve-lin knob as-fader
  "VCF II" "LPF"   "cb2-lpf"     CbChanParams.lpf c2 0.0 10.0 5.0 curve-lin knob as-fader
  "VCF II" "RES"   "cb2-res-l"   CbChanParams.res-l c2 0.0 10.0 2.0 curve-lin knob as-fader
  "VCF II" "IL"    "cb2-il"      CbChanParams.il c2 0.0 10.0 6.0 curve-lin knob as-fader
  "VCF II" "AL"    "cb2-al"      CbChanParams.al c2 0.0 10.0 5.0 curve-lin knob as-fader
  "VCF II" "A"     "cb2-f-a"     CbChanParams.f-a c2 0.001 1.024 0.12 curve-exp knob as-fader
  "VCF II" "D"     "cb2-f-d"     CbChanParams.f-d c2 0.01 10.24 0.9 curve-exp knob as-fader
  "VCF II" "R"     "cb2-f-r"     CbChanParams.f-r c2 0.01 10.24 0.5 curve-exp knob as-fader
  "VCA II" "VCF"   "cb2-vcf-lvl" CbChanParams.vcf-lvl c2 0.0 10.0 9.0 curve-lin knob as-fader
  "VCA II" "SINE"  "cb2-sine"    CbChanParams.sine-l c2 0.0 10.0 0.0 curve-lin knob as-fader
  "VCA II" "A"     "cb2-a-a"     CbChanParams.a-a c2 0.001 1.024 0.05 curve-exp knob as-fader
  "VCA II" "D"     "cb2-a-d"     CbChanParams.a-d c2 0.01 10.24 3.0 curve-exp knob as-fader
  "VCA II" "S"     "cb2-a-s"     CbChanParams.a-s c2 0.0 10.0 8.5 curve-lin knob as-fader
  "VCA II" "R"     "cb2-a-r"     CbChanParams.a-r c2 0.01 10.24 0.5 curve-exp knob as-fader
  "VCA II" "LEVEL" "cb2-level"   CbChanParams.level c2 0.0 10.0 8.5 curve-lin knob as-fader
  "TOUCH II" "I BRIL" "cb2-i-bril" CbChanParams.i-bril c2 0.0 10.0 2.0 curve-lin knob
  "TOUCH II" "I LVL"  "cb2-i-lvl"  CbChanParams.i-lvl c2 0.0 10.0 3.0 curve-lin knob
  "TOUCH II" "A BRIL" "cb2-a-bril" CbChanParams.a-bril c2 0.0 10.0 5.0 curve-lin knob
  "TOUCH II" "A LVL"  "cb2-a-lvl"  CbChanParams.a-lvl c2 0.0 10.0 6.0 curve-lin knob
;

: manifest
  "C-Beam 80" voice-sample machine*
  "k-cb-voice"         render!
  "cb-note-on"         note-on!
  "cb-note-expr"       note-expr!
  "cb-note-off"        note-off!
  "cb-block-prepare"   block-prepare!
  8 voices!
  stereo
  CbState.size  state-size!
  CbParams.size params-size!
  1090.0 panel-w!
  "bbd" CbState.buf CbState.buf-len 0.02 buffer

  cb-chan-i
  cb-chan-ii

  "SUB OSC" "FUNC"  "cb-sub-fn"  CbParams.sub-fn 0 switch
    "SINE" 0.0 opt  "SAW DN" 1.0 opt  "SAW UP" 2.0 opt  "SQUARE" 3.0 opt  "NOISE" 4.0 opt  as-display
  "SUB OSC" "SPEED" "cb-sub-spd" CbParams.sub-spd 0.7 60.0 5.5 curve-exp knob as-fader
  "SUB OSC" "VCO"   "cb-sub-vco" CbParams.sub-vco-l 0.0 10.0 0.0 curve-pow knob as-fader
  "SUB OSC" "VCF"   "cb-sub-vcf" CbParams.sub-vcf-l 0.0 10.0 0.0 curve-pow knob as-fader
  "SUB OSC" "VCA"   "cb-sub-vca" CbParams.sub-vca-l 0.0 10.0 0.0 curve-pow knob as-fader

  "TOUCH RESPONSE" "PITCH" "cb-tr-pitch" CbParams.tr-pitch 0.0 10.0 0.0 curve-lin knob as-fader
  "TOUCH RESPONSE" "SPEED" "cb-tr-speed" CbParams.tr-speed 0.0 10.0 0.0 curve-lin knob as-fader
  "TOUCH RESPONSE" "VCO"   "cb-tr-vco"   CbParams.tr-vco 0.0 10.0 4.0 curve-lin knob as-fader
  "TOUCH RESPONSE" "VCF"   "cb-tr-vcf"   CbParams.tr-vcf 0.0 10.0 0.0 curve-lin knob as-fader

  "KEYBOARD" "BRIL LO" "cb-kb-bl" CbParams.kb-bl -5.0 5.0 0.0 curve-lin knob as-fader
  "KEYBOARD" "BRIL HI" "cb-kb-bh" CbParams.kb-bh -5.0 5.0 0.0 curve-lin knob as-fader
  "KEYBOARD" "LVL LO"  "cb-kb-ll" CbParams.kb-ll -5.0 5.0 0.0 curve-lin knob as-fader
  "KEYBOARD" "LVL HI"  "cb-kb-lh" CbParams.kb-lh -5.0 5.0 0.0 curve-lin knob as-fader

  "RING MOD" "SPEED"  "cb-ring-spd"   CbParams.ring-spd 0.2 200.0 6.7 curve-exp knob as-fader
  "RING MOD" "MOD"    "cb-ring-mod"   CbParams.ring-mod 0.0 10.0 0.0 curve-lin knob as-fader
  "RING MOD" "DEPTH"  "cb-ring-depth" CbParams.ring-depth 0.0 10.0 0.0 curve-lin knob as-fader
  "RING MOD" "ATTACK" "cb-ring-a"     CbParams.ring-a 0.001 1.024 0.03 curve-exp knob as-fader
  "RING MOD" "DECAY"  "cb-ring-d"     CbParams.ring-d 0.01 10.24 0.5 curve-exp knob as-fader

  "CHORUS" "MODE"  "cb-cho-mode"  CbParams.cho-mode 0 switch
    "OFF" 0.0 opt  "CHORUS" 1.0 opt  "TREMOLO" 2.0 opt  as-list
  "CHORUS" "SPEED" "cb-cho-spd"   CbParams.cho-spd 0.0 10.0 4.0 curve-lin knob as-fader
  "CHORUS" "DEPTH" "cb-cho-depth" CbParams.cho-depth 0.0 10.0 5.0 curve-lin knob as-fader

  "MASTER" "MIX I-II"   "cb-mix"    CbParams.mix 0.0 10.0 5.0 curve-lin knob as-fader
  "MASTER" "BRILLIANCE" "cb-bril"   CbParams.bril -5.0 5.0 0.0 curve-lin knob as-fader
  "MASTER" "RESONANCE"  "cb-reso"   CbParams.reso 0.0 10.0 0.0 curve-lin knob as-fader
  "MASTER" "VOLUME"     "cb-vol"    CbParams.vol 0.0 1.0 0.7 curve-pow knob as-fader

  "PITCH" "PITCH"  "cb-pitch"   CbParams.pitch -5.0 7.0 0.0 curve-lin knob
  "PITCH" "DETUNE" "cb-detune"  CbParams.detune -1.0 1.0 0.08 curve-lin knob
  "PITCH" "PORTA"  "cb-porta"   CbParams.porta 0 switch
    "OFF" 0.0 opt  "PORTA" 1.0 opt  "GLISS" 2.0 opt  as-list
  "PITCH" "TIME"   "cb-porta-t" CbParams.porta-t 0.00017 0.16 0.01 curve-exp knob
  "SUSTAIN" "MODE" "cb-sus-mode" CbParams.sus-mode 0 switch
    "OFF" 0.0 opt  "I" 1.0 opt  "II" 2.0 opt  as-list
  "SUSTAIN" "TIME" "cb-sus-t"    CbParams.sus-t 0.01 10.24 2.0 curve-exp knob
  "MASTER" "AGE"   "cb-age"      CbParams.age 0.0 1.0 0.5 curve-lin knob

  "VCO I" 7 strip  "VCF I" 9 strip  "VCA I" 7 strip  "TOUCH I" 2 strip
  "VCO II" 7 strip  "VCF II" 9 strip  "VCA II" 7 strip  "TOUCH II" 2 strip
  "SUB OSC" 5 strip  "TOUCH RESPONSE" 4 strip  "KEYBOARD" 4 strip
  "RING MOD" 5 strip  "CHORUS" 3 strip  "MASTER" 5 strip
  "PITCH" 4 strip  "SUSTAIN" 2 strip
  "SCOPE" scope-display

  ( VOICE: the two channels as the CS-80's top panel stacks them )
  "VOICE" page
    1.0 row
      0.7 cell  "VCO I" 1.0 item
      0.9 cell  "VCF I" 1.0 item
      0.7 cell  "VCA I" 1.0 item
      0.26 cell  "TOUCH I" 1.0 item
    1.0 row
      0.7 cell  "VCO II" 1.0 item
      0.9 cell  "VCF II" 1.0 item
      0.7 cell  "VCA II" 1.0 item
      0.26 cell  "TOUCH II" 1.0 item
  ( CONTROL: the levers under the keyboard lid )
  "CONTROL" page
    1.0 row
      1.0 cell  "SUB OSC" 1.0 item
      0.8 cell  "TOUCH RESPONSE" 1.0 item
      0.8 cell  "KEYBOARD" 1.0 item
      1.0 cell  "RING MOD" 1.0 item
    1.0 row
      0.55 cell  "CHORUS" 1.0 item
      0.75 cell  "MASTER" 1.0 item
      0.75 cell  "PITCH" 1.0 item
      0.55 cell  "SUSTAIN" 1.0 item
      0.6 cell  "SCOPE" 1.0 item

  machine-desc
;
