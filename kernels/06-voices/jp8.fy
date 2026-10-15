( jp8.fy - Juniper-8: the Roland Jupiter-8 [1981], one voice as the
  original's voice board plays it.  docs/39-jp8.md is the circuit study
  this follows; the numbers are Roland's [Owner's Manual spec page, the
  Service Notes' voice schematic and adjustment procedure] unless the
  doc marks them as our guess.

    VCO-1 [tri saw pulse square, 16'..2'] <-- CROSS MOD [VCO-2, expo]
      |  sync master                            |
    VCO-2 [sine saw pulse noise, 16'..2' in semitones, FINE, LOW FREQ]
      '--> SOURCE MIX [one crossfade] -> HPF [6 dB OTA]
             -> IR3109 [4 OTA poles, 24 dB at pole 4, 12 dB at pole 2,
                        resonance from pole 4 through a 3.4 Hz cap]
             -> VCA [ENV-2 x LEVEL, LFO 0..3] -> out

  What makes it a Jupiter-8 and not a generic 2-VCO poly:
  - cross mod is exponential, VCO-2 into VCO-1's pitch summer: a square
    at CROSS MOD 5 moves VCO-1 three octaves [the Service Notes' trim],
    and it pulls the pitch up as the real one does;
  - sync runs the other way to a Prophet: VCO-2 follows VCO-1;
  - PWM is one control for both VCOs' pulses, from the LFO, by hand or
    from ENV-1, and at 10 the pulse thins to 30 us: nearly gone;
  - the 12 dB slope is the IR3109's second pole with the resonance loop
    still closed round all four: brighter, thinner, peaky;
  - the input divider puts a 10 Vpp VCO at about 80 mV on the first OTA,
    where its tanh just starts to bend;
  - the LFO is one per layer, shared by every voice: it runs on the host
    clock [ctx.clock], and DELAY fades it in from the first key down after
    all keys were up;
  - ENV-1 inverts, and both envelopes shorten up the keyboard with KEY
    FOLLOW.  No velocity, no aftertouch: the original has neither.

  Rates: the VCOs run at 4x [hb4 down to 2x], the HPF and the IR3109 at
  2x [hb9 down], envelopes, LFO and cutoff once per sample. )

include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"
include "../00-primitives/oversample.fy"
include "../01-oscillators/primitives/phase.fy"
include "../01-oscillators/primitives/blep.fy"
include "../01-oscillators/primitives/shapes.fy"
include "../01-oscillators/primitives/vco.fy"
include "../03-envelopes/primitives/env_rc.fy"
include "../04-filters/ota_cascade.fy"
include "../08-analog/analog.fy"

:: JP-OCTC 8.031359713524661 ;      ( log2 261.63 Hz: C2 on Roland's keyboard, middle C )
:: JP-LOWB 1.0313597135246610 ;     ( log2 2.04 Hz: VCO-2 LOW at 8', our guess )
:: JP-IN 0.48 ;                     ( 10 Vpp -> 80 mV: a VCO at +-1 bends the OTAs like the original )
:: JP-OUT 2.0833333333333335 ;      ( 1 / JP-IN )

ustruct: JpEnv  f64 level  f64 stage ;

ustruct: JpVcf
  f64 s0  f64 s1  f64 s2  f64 s3
  f64 t0  f64 t1  f64 t2  f64 t3
  f64 y-prev  f64 fb
  f64 hp-x  f64 hp-y                 ( the resonance loop's 0.47 uF coupling cap )
;

ustruct: JpState
  f64 ph1  f64 ph2                   ( VCO phases )
  f64 v2                             ( VCO-2's last sample: the cross mod source )
  f64 t                              ( this voice's sample clock )
  f64 oct  f64 target-oct            ( key pitch, log2 Hz; portamento glides it )
  f64 ekf                            ( envelope KEY FOLLOW: rate multiplier for this key )
  f64 noise-rng
  f64 hpf-lp                         ( the 6 dB HPF's integrator )
  f64 dc-x  f64 dc-y                 ( the VCA's output coupling )
  f64 curve1  f64 curve2             ( saw bow, from AGE )
  f64 cut-sp                         ( cutoff spread, octaves, from AGE )
  JpEnv e1
  JpEnv e2
  JpVcf vcf
  Hb4 h4
  Hb9 h9
  Drift dr1  Drift dr2
;

ustruct: JpParams
  ( LFO )
  f64 lfo-rate  f64 lfo-delay  f64 lfo-wave       ( Hz, s, 0 sine 1 saw 2 square 3 random )
  ( VCO MODULATOR )
  f64 lfo-vco  f64 env-vco  f64 vmod-dst          ( 0..10, 0..10, 0 VCO-1 1 BOTH 2 VCO-2 )
  ( VCO-1 )
  f64 cross  f64 range1  f64 wave1                ( 0..10, feet ratio, 0 tri 1 saw 2 pulse 3 square )
  ( VCO-2 )
  f64 sync  f64 range2  f64 fine2  f64 wave2  f64 low2   ( 0/1, semitones, cents, 0 sine 1 saw 2 pulse 3 noise, 0/1 )
  ( PWM )
  f64 pwm  f64 pwm-src                            ( 0..10, 0 LFO 1 MAN 2 ENV-1 )
  ( SOURCE MIX, HPF )
  f64 mix  f64 hpf                                ( 0..10 )
  ( VCF )
  f64 slope  f64 cutoff  f64 res  f64 env-src  f64 env-mod  f64 lfo-vcf  f64 kf   ( 0 24 dB 1 12 dB, 0..10, 0..10, 0 ENV-1 1 ENV-2, 0..10 .. )
  ( VCA )
  f64 vca-lfo  f64 level                          ( 0..3, 0..10 )
  ( ENV-1, ENV-2 )
  f64 e1-a  f64 e1-d  f64 e1-s  f64 e1-r  f64 e1-kf  f64 e1-pol   ( s, s, 0..10, s, 0/1, 0 normal 1 inverse )
  f64 e2-a  f64 e2-d  f64 e2-s  f64 e2-r  f64 e2-kf
  ( performance )
  f64 bend  f64 bend-vco  f64 bend-v1  f64 bend-v2  f64 bend-vcf   ( lever -1..1, 0..10, 0/1, 0/1, 0..10 )
  f64 porta  f64 porta-t  f64 tune  f64 age  f64 vol              ( 0/1, s, cents, 0..1, 0..1 )
  ( shared state the note hooks keep )
  f64 gates 16
  f64 lfo-trig
  ( derived by jp-block-prepare )
  f64 clk0  f64 lfo-ph0  f64 lfo-n  f64 lfo-inc  f64 lfo-amp
  f64 inv-osr4  f64 osr2
  f64 glide-c
  f64 r1  f64 r2  f64 lowk  f64 lowo
  f64 vl1  f64 vl2  f64 ve1  f64 ve2
  f64 b1  f64 b2  f64 bvcf
  f64 xm
  f64 pw-man  f64 pw-lfo  f64 pw-env
  f64 m1  f64 m2
  f64 hpa
  f64 cut0  f64 kfo  f64 envc  f64 lfoc  f64 res-k  f64 p2w  f64 vcf-hpa
  f64 e1s
  f64 e1ca  f64 e1cd  f64 e1sus  f64 e1cr
  f64 e2ca  f64 e2cd  f64 e2sus  f64 e2cr
  f64 trem  f64 lvl
  f64 dc-a  f64 drift-c  f64 drift-m  f64 bleed  f64 gain
;

( --- the voice board's parts ------------------------------------------------ )

( e ca cd sus cr m -- y : one sample of an IR3R01 envelope.  The RC curve
  of env_rc.fy, its rates scaled by m for KEY FOLLOW. )
dsp: jp-env | e:JpEnv ca cd sus cr m -- y |
  e.stage | st |
  e.level | l |
  st 0.5 f<  0.0  st 1.5 f<  1.2  sus  select  select | tgt |
  st 0.5 f<  cr  st 1.5 f<  ca  cd  select  select  m f*  1.0 fmin | c |
  l  tgt l f- c f*  f+ | n |
  st 0.5 f>  st 1.5 f< and  n 1.0 f>= and | top |
  top 2.0 st select -> e.stage
  top 1.0 n select | y |
  y -> e.level
  y
;

( e fresh -- : key down; a legato note keeps the stage it is in. )
dsp: jp-env-on | e:JpEnv fresh -- |  fresh 1.0 e.stage select -> e.stage ;

( e -- : key up. )
dsp: jp-env-off | e:JpEnv -- |  0.0 -> e.stage ;

( one 4x substep: VCO-1, cross-modulated by VCO-2's last sample, then
  VCO-2, synced to VCO-1; the SOURCE MIX crossfade. )
dsp: jp-osc | state:JpState params:JpParams dt1 dt2 pw -- x |
  params.cross 0.0 f=
    [ dt1 ]
    [ state.v2 params.xm f* exp2 dt1 f* ]
  ifte 0.0 0.45 fclamp | d1 |
  state.ph1 d1 f+ | q1 |
  q1 wrap01 | p1 |
  p1 -> state.ph1
  1.0 q1 f<= | w1 |
  ( VCO-1: every wave comes from the one saw core, the waveform converter
    picks; square is the pulse at 50 % )
  params.wave1 | wv |
  p1 d1 state.curve1 vco-saw | sw |
  p1 tri-raw | tw |
  p1 d1  wv 2.5 f<  pw 0.5 select  pulse-polyblep | pu |
  wv 0.5 f<  tw  wv 1.5 f<  sw pu  select  select | a |
  ( VCO-2: SYNC resets it when VCO-1 wraps, at VCO-1's fraction )
  state.ph2 dt2 phase-advance01 | f2 |
  params.sync 0.5 f>  w1 and
    p1 dt2 f* d1 0.000001 fmax f/ ffrac  f2  select | p2 |
  p2 -> state.ph2
  params.wave2 | wb |
  p2 tri-raw | t2 |
  t2  1.5  t2 t2 f* 0.5 f*  f-  f* | sn |
  p2 dt2 state.curve2 vco-saw | s2 |
  p2 dt2 pw pulse-polyblep | u2 |
  state.noise-rng& rand-b | nz |
  wb 0.5 f<  sn  wb 1.5 f<  s2  wb 2.5 f<  u2 nz  select  select  select | b |
  b -> state.v2
  a params.m1 f*  b params.m2 f*  f+
;

( m x g k hpa -- p2 p4 : one 2x step of the IR3109.  Four OTA poles,
  each through its pair's tanh [as ota_cascade.fy]; the resonance comes
  from pole 4 through the resonance OTA [a plain tanh] and the 0.47 uF
  coupling cap, 3.4 Hz.  Pole 2 is the 12 dB tap, the loop still closed
  round all four. )
dsp: jp-vcf | m:JpVcf x g k hpa -- p2 p4 |
  m.fb tanh-fast | fs |
  m.hp-y fs f+ m.hp-x f- hpa f* | fh |
  fs -> m.hp-x
  fh -> m.hp-y
  x k fh f* f- | v |
  v OTA-THERMAL f* tanh-fast | u |
  m.s0  u m.t0 f- g f* f+ | s0 |
  s0 OTA-THERMAL f* tanh-fast | t0 |
  m.s1  t0 m.t1 f- g f* f+ | s1 |
  s1 OTA-THERMAL f* tanh-fast | t1 |
  m.s2  t1 m.t2 f- g f* f+ | s2 |
  s2 OTA-THERMAL f* tanh-fast | t2 |
  m.s3  t2 m.t3 f- g f* f+ | s3 |
  s3 OTA-THERMAL f* tanh-fast | t3 |
  s0 -> m.s0  s1 -> m.s1  s2 -> m.s2  s3 -> m.s3
  t0 -> m.t0  t1 -> m.t1  t2 -> m.t2  t3 -> m.t3
  s3 m.y-prev f+ 0.5 f* -> m.fb
  s3 -> m.y-prev
  s1 s3
;

( one 2x step after the oscillators: the HPF, then the IR3109 at the
  slope's tap. )
dsp: jp-filt | state:JpState params:JpParams x g k -- y |
  state.hpf-lp | l0 |
  l0  x l0 f- params.hpa f*  f+ | l |
  l -> state.hpf-lp
  state.vcf&  x l f- JP-IN f*  g k  params.vcf-hpa jp-vcf | p2 p4 |
  p4  p2 p4 f- params.p2w f*  f+
;

( --- block rate ---------------------------------------------------------------- )

( ctx state params -- )
dsp: jp-block-prepare | ctx:Ctx state params:JpParams -- |
  ctx.sr | sr |
  ctx.inv-sr | inv |
  ( the LFO runs on the host clock: carry its phase and its cycle count
    over the samples since the last call )
  ctx.clock params.clk0 f- 0.0 fmax | dt |
  params.lfo-ph0  dt params.lfo-inc f*  f+ | lp |
  lp ffrac | lf |
  params.lfo-n  lp lf f-  f+ 65536.0 f/ ffrac 65536.0 f* -> params.lfo-n
  lf -> params.lfo-ph0
  ctx.clock -> params.clk0
  params.lfo-rate inv f* -> params.lfo-inc
  ( DELAY: the LFO fades in from the first key after all were up )
  ctx.clock params.lfo-trig f- inv f* | rt |
  params.lfo-delay 0.001 f<  1.0  rt params.lfo-delay f/ 0.0 1.0 fclamp  select -> params.lfo-amp
  1.0 sr 4.0 f* f/ -> params.inv-osr4
  sr 2.0 f* | osr2 |
  osr2 -> params.osr2
  ( portamento: an RC lag, TIME to 99 % )
  params.porta 0.5 f>  params.porta-t 0.001 f> and
    1.0  -4.6  params.porta-t sr f* f/  exp  f-
    1.0
  select -> params.glide-c
  ( pitch: TUNE, the feet, VCO-2's semitone RANGE and FINE; LOW FREQ
    drops VCO-2 off the keyboard into LFO range )
  params.tune 0.0008333333333333334 f* | tn |
  params.range1 log2 tn f+ -> params.r1
  params.range2 0.08333333333333333 f*  params.fine2 0.0008333333333333334 f* f+  tn f+ | r2 |
  r2 -> params.r2
  params.low2 0.5 f>  0.0 1.0 select -> params.lowk
  params.low2 0.5 f>  JP-LOWB tn f- 0.0 select -> params.lowo
  ( VCO MODULATOR: LFO and ENV-1 to VCO-1, BOTH or VCO-2.  ENV at 10
    moves 3 octaves [Service Notes]; the LFO's depth is our guess,
    a pot-law octave at 10 )
  params.vmod-dst | vd |
  vd 1.5 f< 1.0 0.0 select | to1 |
  vd 0.5 f> 1.0 0.0 select | to2 |
  params.lfo-vco 0.1 f* | lv |
  lv lv f* | lv2 |
  lv2 to1 f* -> params.vl1
  lv2 to2 f* -> params.vl2
  params.env-vco 0.3 f* | ev |
  ev to1 f* -> params.ve1
  ev to2 f* -> params.ve2
  ( bender: VCO up to an octave, VCF up to 4 octaves, both guesses )
  params.bend params.bend-vco f* 0.1 f* | bo |
  bo params.bend-v1 f* -> params.b1
  bo params.bend-v2 f* -> params.b2
  params.bend params.bend-vcf f* 0.4 f* -> params.bvcf
  ( cross mod: 3 octaves at 5 for a square, so 0.6 octave per step )
  params.cross 0.6 f* -> params.xm
  ( PWM: 0 is the square, 10 thins the pulse to 30 us )
  params.pwm 0.0492 f* | pd |
  params.pwm-src | ps |
  ps 0.5 f<  pd 0.0 select -> params.pw-lfo
  ps 0.5 f>  ps 1.5 f< and  pd 0.0 select -> params.pw-man
  ps 1.5 f>  pd 0.0 select -> params.pw-env
  ( SOURCE MIX: one pot between the two )
  params.mix 0.1 f* | mx |
  1.0 mx f- -> params.m1
  mx -> params.m2
  ( HPF: 6 dB, 15 Hz to ~2.7 kHz, our guess at the slider's law )
  params.hpf 0.75 f* exp2 15.0 f* 6.283185307179586 f* osr2 f/ | wh |
  1.0  wh fneg exp  f- -> params.hpa
  ( VCF: CUTOFF 0..10 is 100 Hz .. 20 kHz at C2 [Service Notes]; ENV MOD
    10 is 500 Hz -> 20 kHz, 5.3 octaves; KEY FOLLOW 0..120 % round C2 )
  params.cutoff 0.7643856189774724 f* 6.643856189774724 f+ -> params.cut0
  params.kf 0.12 f* -> params.kfo
  params.env-mod 0.532 f* -> params.envc
  params.lfo-vcf 0.1 f* | lc |
  lc lc f* 4.0 f* -> params.lfoc
  ( RES 10 rings just short of oscillating, as the trim sets it )
  params.res 0.098 f* -> params.res-k
  ( the resonance loop's coupling cap: 100k into 0.47 uF, 3.4 Hz )
  3.4 osr2 ota-hp-coef -> params.vcf-hpa
  params.slope 0.5 f>  1.0 0.0 select -> params.p2w
  ( ENV-1's polarity; the envelopes' rates )
  params.e1-pol 0.5 f>  -1.0 1.0 select -> params.e1s
  params.e1-a inv 1.791759469228055 env-rc-coef -> params.e1ca
  params.e1-d inv 4.605170185988091 env-rc-coef -> params.e1cd
  params.e1-s 0.1 f* -> params.e1sus
  params.e1-r inv 4.605170185988091 env-rc-coef -> params.e1cr
  params.e2-a inv 1.791759469228055 env-rc-coef -> params.e2ca
  params.e2-d inv 4.605170185988091 env-rc-coef -> params.e2cd
  params.e2-s 0.1 f* -> params.e2sus
  params.e2-r inv 4.605170185988091 env-rc-coef -> params.e2cr
  ( VCA: LFO MOD 0..3, our guess at the steps' depths )
  params.vca-lfo | vl |
  vl 0.5 f<  0.0  vl 1.5 f<  0.12  vl 2.5 f<  0.25 0.45  select  select  select -> params.trem
  params.level 0.1 f* -> params.lvl
  1.0  1.0  6.283185307179586 10.0 f* inv f*  f+  f/ -> params.dc-a
  ( AGE: Compu-tune keeps the VCOs close; drift up to ~2 cents, and the
    VCA balance trim's residual thump )
  0.25 inv drift-coef -> params.drift-c
  params.age 0.0012 f* -> params.drift-m
  params.age 0.004 f* -> params.bleed
  params.vol 0.6 f* -> params.gain
;

( --- note hooks ------------------------------------------------------------------ )

( ctx state params -- )
dsp: jp-note-on | ctx:Ctx state:JpState params:JpParams -- |
  ctx.hz 1.0 fmax log2 | o |
  o -> state.target-oct
  ( poly portamento: each voice glides from the note it last played )
  params.porta 0.5 f>  state.oct 1.0 f> and  state.oct o select -> state.oct
  ctx.clock -> state.t
  ( KEY FOLLOW: an octave up the keyboard runs the envelope ~1.4x faster,
    our guess )
  o JP-OCTC f- 0.5 f* exp2 -> state.ekf
  ctx.chan | v |
  state.dr1& v 1.0 f+ drift-seed-once
  state.dr2& v 11.0 f+ drift-seed-once
  state.noise-rng& v 37.0 f+ rand-seed-once
  ( unison: a fresh voice starts at the host's phase, not 0 )
  state.ph1 0.0 f=  ctx.phase  state.ph1  select -> state.ph1
  state.ph2 0.0 f=  ctx.phase 2.618 f* ffrac  state.ph2  select -> state.ph2
  ( AGE: this voice's parts, the same way every time )
  params.age | ag |
  v 1.0 spread 0.5 f* 0.5 f+  ag f* 0.2 f* -> state.curve1
  v 2.0 spread 0.5 f* 0.5 f+  ag f* 0.2 f* -> state.curve2
  v 4.0 spread ag f* 0.08 f* -> state.cut-sp
  ctx.legato 0.5 f< | fresh |
  state.e1& fresh jp-env-on
  state.e2& fresh jp-env-on
  ( the LFO's DELAY starts again only from the first key after all were up )
  0.0 0.0 16 [ | i s | i 1.0 f+  s params.gates& i f@i f+ ] times | ni s |
  s  params.gates& ctx.chan f@i  f- | others |
  others 0.5 f<  ctx.clock  params.lfo-trig  select -> params.lfo-trig
  1.0 params.gates& ctx.chan f!i
;

( ctx state params -- : note expression retunes the voice; a glide in
  flight keeps its offset. )
dsp: jp-note-expr | ctx:Ctx state:JpState params:JpParams -- |
  ctx.hz 1.0 fmax log2 | o |
  state.oct  o state.target-oct f-  f+ -> state.oct
  o -> state.target-oct
;

( ctx state params -- )
dsp: jp-note-off | ctx:Ctx state:JpState params:JpParams -- |
  0.0 params.gates& ctx.chan f!i
  state.e1& jp-env-off
  state.e2& jp-env-off
;

( --- the voice ---------------------------------------------------------------------- )

( io ctx state params -- : one output sample. )
dsp: k-jp-voice | io ctx state:JpState params:JpParams -- |
  state.t | t |
  t params.clk0 f- | k |
  t 1.0 f+ -> state.t
  ( the LFO: one for the layer.  RANDOM holds one value per cycle. )
  params.lfo-ph0  k params.lfo-inc f*  f+ | la |
  la ffrac | lp |
  params.lfo-wave | lw |
  lw 0.5 f<  lp sin2pi
    lw 1.5 f<  1.0 lp 2.0 f* f-
      lw 2.5 f<  lp 0.5 1.0 -1.0 fsel-lt
        params.lfo-n  la lp f-  f+  0.7071 clock-hash
      select
    select
  select  params.lfo-amp f* | lfo |
  ( envelopes; KEY FOLLOW per envelope )
  params.e1-kf 0.5 f>  state.ekf 1.0 select | m1 |
  params.e2-kf 0.5 f>  state.ekf 1.0 select | m2 |
  state.e1& params.e1ca params.e1cd params.e1sus params.e1cr m1 jp-env | e1u |
  state.e2& params.e2ca params.e2cd params.e2sus params.e2cr m2 jp-env | e2 |
  e1u params.e1s f* | e1 |
  ( portamento, in octaves )
  state.oct  state.target-oct state.oct f-  params.glide-c f*  f+ | oct |
  oct -> state.oct
  ( pitch: each VCO's octave, then a 4x increment )
  state.dr1& params.drift-c drift-step params.drift-m f* | d1 |
  state.dr2& params.drift-c drift-step params.drift-m f* | d2 |
  oct params.r1 f+  lfo params.vl1 f* f+  e1 params.ve1 f* f+  params.b1 f+  d1 f+
    exp2 params.inv-osr4 f* | dt1 |
  oct params.lowk f*  params.lowo f+  params.r2 f+  lfo params.vl2 f* f+  e1 params.ve2 f* f+  params.b2 f+  d2 f+
    exp2 params.inv-osr4 f* | dt2 |
  ( PWM: both VCOs' pulses, from the LFO, the slider or ENV-1 )
  0.5
    params.pw-man
    lfo 0.5 f* 0.5 f+ params.pw-lfo f*  f+
    e1u params.pw-env f*  f+
  f-  0.008 0.5 fclamp | pw |
  ( cutoff, in octaves: the slider, the key, the envelope, the LFO, the bender )
  params.env-src 0.5 f<  e1 e2 select | ef |
  params.cut0
    oct JP-OCTC f- params.kfo f*  f+
    ef params.envc f*  f+
    lfo params.lfoc f*  f+
    params.bvcf f+
    state.cut-sp f+
  exp2 | fc |
  fc params.osr2 params.res-k ota-coeffs | g kr |
  ( the resonance's passband loss, partly made up: our guess )
  1.0 kr 0.3 f* f+  JP-OUT f* | mk |
  state.h9&
    state.h4&
      state params dt1 dt2 pw jp-osc
      state params dt1 dt2 pw jp-osc
    hb4-dec | x0 |
    state params x0 g kr jp-filt
    state.h4&
      state params dt1 dt2 pw jp-osc
      state params dt1 dt2 pw jp-osc
    hb4-dec | x1 |
    state params x1 g kr jp-filt
  hb9-dec  mk f* | y |
  ( the VCA: ENV-2 x LEVEL, the LFO's tremolo; the balance trim's residue
    of ENV-2 leaks through, and the output cap takes out the DC )
  1.0 lfo params.trem f* f+ | am |
  y e2 f* params.lvl f* am f*  e2 params.bleed f*  f+ | x |
  x state.dc-x state.dc-y params.dc-a droop-hp | o |
  x -> state.dc-x
  o -> state.dc-y
  io f@64  o params.gain f*  f+  io f!64
;
