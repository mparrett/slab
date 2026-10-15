( jp8.fy - Juniper-8: the Roland Jupiter-8, eight voices of two VCOs.

  The voice is kernels/06-voices/jp8.fy and the circuit study behind it
  docs/39-jp8.md.  The panel is the Jupiter's, left to right: LFO, VCO
  MODULATOR, VCO-1, VCO-2, PWM and SOURCE MIX over the HPF, VCF, VCA and
  the two envelopes, with the bender and portamento beside them.  Sliders
  read 0..10 as the original's do; times are seconds.

  The sounds it is known for: VCO-1 and VCO-2 on saw, a little detuned
  with FINE, the 24 dB VCF swept by ENV-1 [the brass and the strings];
  SYNC with ENV-1 on VCO-2 through the VCO MODULATOR [the sync sweep];
  CROSS MOD for clang and bells. )

include "../../kernels/06-voices/jp8.fy"
include "../lib/manifest.fy"

: jp-onoff  "OFF" 0.0 opt  "ON" 1.0 opt  as-button ;

: manifest
  "Juniper-8" voice-sample machine*
  "k-jp-voice"         render!
  "jp-note-on"         note-on!
  "jp-note-expr"       note-expr!
  "jp-note-off"        note-off!
  "jp-block-prepare"   block-prepare!
  8 voices!
  JpState.size  state-size!
  JpParams.size params-size!
  1000.0 panel-w!

  "LFO" "RATE"  "jp-lfo-rate"  JpParams.lfo-rate 0.05 40.0 4.0 curve-exp knob as-fader
  "LFO" "DELAY" "jp-lfo-delay" JpParams.lfo-delay 0.0 4.0 0.0 curve-pow knob as-fader
  "LFO" "WAVE"  "jp-lfo-wave"  JpParams.lfo-wave 0 switch
    "SINE" 0.0 opt  "SAW" 1.0 opt  "SQUARE" 2.0 opt  "RANDOM" 3.0 opt  as-list

  "VCO MOD" "LFO" "jp-lfo-vco" JpParams.lfo-vco 0.0 10.0 0.0 curve-lin knob as-fader
  "VCO MOD" "ENV" "jp-env-vco" JpParams.env-vco 0.0 10.0 0.0 curve-lin knob as-fader
  "VCO MOD" "TO"  "jp-vmod-dst" JpParams.vmod-dst 1 switch
    "VCO-1" 0.0 opt  "BOTH" 1.0 opt  "VCO-2" 2.0 opt  as-list

  "VCO-1" "CROSS" "jp-cross"  JpParams.cross 0.0 10.0 0.0 curve-lin knob as-fader
  "VCO-1" "RANGE" "jp-range1" JpParams.range1 1 switch
    "16'" 0.5 opt  "8'" 1.0 opt  "4'" 2.0 opt  "2'" 4.0 opt  as-list
  "VCO-1" "WAVE"  "jp-wave1"  JpParams.wave1 1 switch
    "TRI" 0.0 opt  "SAW" 1.0 opt  "PULSE" 2.0 opt  "SQUARE" 3.0 opt  as-list

  "VCO-2" "RANGE" "jp-range2" JpParams.range2 -12.0 24.0 0.0 int-step
  "VCO-2" "FINE"  "jp-fine2"  JpParams.fine2 -50.0 50.0 6.0 curve-lin knob
  "VCO-2" "WAVE"  "jp-wave2"  JpParams.wave2 1 switch
    "SINE" 0.0 opt  "SAW" 1.0 opt  "PULSE" 2.0 opt  "NOISE" 3.0 opt  as-list
  "VCO-2" "SYNC"  "jp-sync"   JpParams.sync 0 switch jp-onoff
  "VCO-2" "LOW"   "jp-low2"   JpParams.low2 0 switch jp-onoff

  "PWM" "PWM"    "jp-pwm"     JpParams.pwm 0.0 10.0 0.0 curve-lin knob as-fader
  "PWM" "SOURCE" "jp-pwm-src" JpParams.pwm-src 1 switch
    "LFO" 0.0 opt  "MAN" 1.0 opt  "ENV-1" 2.0 opt  as-list
  "MIX" "VCO-1:2" "jp-mix"    JpParams.mix 0.0 10.0 5.0 curve-lin knob as-fader

  "HPF" "CUTOFF" "jp-hpf" JpParams.hpf 0.0 10.0 0.0 curve-lin knob as-fader

  "VCF" "SLOPE"  "jp-slope"   JpParams.slope 0 switch
    "24 dB" 0.0 opt  "12 dB" 1.0 opt  as-list
  "VCF" "CUTOFF" "jp-cutoff"  JpParams.cutoff 0.0 10.0 5.0 curve-lin knob as-fader
  "VCF" "RES"    "jp-res"     JpParams.res 0.0 10.0 0.0 curve-lin knob as-fader
  "VCF" "ENV"    "jp-env-src" JpParams.env-src 0 switch
    "ENV-1" 0.0 opt  "ENV-2" 1.0 opt  as-list
  "VCF" "ENV MOD" "jp-env-mod" JpParams.env-mod 0.0 10.0 4.0 curve-lin knob as-fader
  "VCF" "LFO"    "jp-lfo-vcf" JpParams.lfo-vcf 0.0 10.0 0.0 curve-lin knob as-fader
  "VCF" "KEY"    "jp-kf"      JpParams.kf 0.0 10.0 5.0 curve-lin knob as-fader

  "VCA" "LFO"   "jp-vca-lfo" JpParams.vca-lfo 0 switch
    "0" 0.0 opt  "1" 1.0 opt  "2" 2.0 opt  "3" 3.0 opt  as-list
  "VCA" "LEVEL" "jp-level"   JpParams.level 0.0 10.0 8.0 curve-lin knob as-fader

  "ENV-1" "A"   "jp-e1-a"   JpParams.e1-a 0.0015 6.0 0.005 curve-exp knob as-fader
  "ENV-1" "D"   "jp-e1-d"   JpParams.e1-d 0.0015 12.0 0.6 curve-exp knob as-fader
  "ENV-1" "S"   "jp-e1-s"   JpParams.e1-s 0.0 10.0 3.0 curve-lin knob as-fader
  "ENV-1" "R"   "jp-e1-r"   JpParams.e1-r 0.0015 12.0 0.4 curve-exp knob as-fader
  "ENV-1" "KEY" "jp-e1-kf"  JpParams.e1-kf 0 switch jp-onoff
  "ENV-1" "POL" "jp-e1-pol" JpParams.e1-pol 0 switch
    "NORM" 0.0 opt  "INV" 1.0 opt  as-button

  "ENV-2" "A"   "jp-e2-a"   JpParams.e2-a 0.0015 6.0 0.003 curve-exp knob as-fader
  "ENV-2" "D"   "jp-e2-d"   JpParams.e2-d 0.0015 12.0 0.8 curve-exp knob as-fader
  "ENV-2" "S"   "jp-e2-s"   JpParams.e2-s 0.0 10.0 8.0 curve-lin knob as-fader
  "ENV-2" "R"   "jp-e2-r"   JpParams.e2-r 0.0015 12.0 0.4 curve-exp knob as-fader
  "ENV-2" "KEY" "jp-e2-kf"  JpParams.e2-kf 0 switch jp-onoff

  "BENDER" "LEVER" "jp-bend"     JpParams.bend -1.0 1.0 0.0 curve-lin knob
  "BENDER" "VCO"   "jp-bend-vco" JpParams.bend-vco 0.0 10.0 2.0 curve-lin knob
  "BENDER" "VCF"   "jp-bend-vcf" JpParams.bend-vcf 0.0 10.0 0.0 curve-lin knob
  "BENDER" "VCO-1" "jp-bend-v1"  JpParams.bend-v1 1 switch jp-onoff
  "BENDER" "VCO-2" "jp-bend-v2"  JpParams.bend-v2 1 switch jp-onoff

  "PORTA" "ON"   "jp-porta"   JpParams.porta 0 switch jp-onoff
  "PORTA" "TIME" "jp-porta-t" JpParams.porta-t 0.0 3.0 0.15 curve-pow knob
  "MASTER" "TUNE"   "jp-tune" JpParams.tune -50.0 50.0 0.0 curve-lin knob
  "MASTER" "AGE"    "jp-age"  JpParams.age 0.0 1.0 0.3 curve-lin knob
  "MASTER" "VOLUME" "jp-vol"  JpParams.vol 0.0 1.0 0.7 curve-pow knob

  "LFO" 3 strip  "VCO MOD" 3 strip  "VCO-1" 3 strip  "VCO-2" 5 strip
  "PWM" 2 strip  "MIX" 1 strip  "HPF" 1 strip  "VCF" 7 strip  "VCA" 2 strip
  "ENV-1" 6 strip  "ENV-2" 5 strip
  "BENDER" 3 strip  "PORTA" 1 strip  "MASTER" 1 strip

  ( the Jupiter's face: sources over the filter, VCA and envelopes )
  1.0 row
    0.6 cell  "LFO" 1.0 item
    0.6 cell  "VCO MOD" 1.0 item
    0.6 cell  "VCO-1" 1.0 item
    0.9 cell  "VCO-2" 1.0 item
    0.45 cell  "PWM" 1.0 item
    0.25 cell  "MIX" 1.0 item
    0.6 cell  "BENDER" 1.0 item
    0.3 cell  "MASTER" 1.0 item
  1.0 row
    0.25 cell  "HPF" 1.0 item
    1.2 cell  "VCF" 1.0 item
    0.45 cell  "VCA" 1.0 item
    1.0 cell  "ENV-1" 1.0 item
    0.9 cell  "ENV-2" 1.0 item
    0.3 cell  "PORTA" 1.0 item

  machine-desc
;
