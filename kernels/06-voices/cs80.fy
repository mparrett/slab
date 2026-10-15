( cs80.fy - C-Beam 80: the Yamaha CS-80 [1977], one note as the original
  plays it.  docs/38-cs80.md is the circuit study this follows; the
  numbers below are Yamaha's [Owner's Manual, Adjustment Procedure, the
  CS-60 service manual's IC sheet] unless marked as our guess.

  A note sounds two complete voices, Channel I and Channel II, like the
  two M boards per key:

    IG00153 saw core --+-- saw ------.
      |  feet, PITCH,  +-- pulse ----+-- + channel noise -> coupling cap
      |  vibrato, IPB  |  [PW 50-90%,     -> IG00156 HPF [12 dB SVF, Q .5-5]
      |                |   PWM LFO]       -> IG00156 LPF [12 dB SVF, Q .5-5]
      |                '-- sine [shaped triangle, past both filters]
      v                                   -> VCF LEVEL + SINE -> IG00151 VCA
    Channel I x MIX + Channel II x MIX -> ring modulator -> chorus/tremolo

  What makes it a CS-80 and not a generic two-layer poly:
  - the VCO is linear in Hz [523.2 Hz/V]; feet are a multiplier, and the
    filters follow the KEY, not the feet [KV feeds the IG00156 directly];
  - the filters are a pair: HPF then LPF, each a resonant 2-pole SVF that
    does not self-oscillate [Q 0.5 at full damping, 5 at the top].  Their
    integrators are OTAs: a loud input runs them out of current and the Q
    falls instead of screaming;
  - the VCF envelope is IL -> AL -> 0 -> IL: it starts BOTH cutoffs below
    the sliders by IL, sweeps them above by AL, settles on the sliders [the
    sliders are the sustain] and releases back down to IL;
  - touch: initial touch is a decaying pulse, not a static velocity; after
    touch is per note.  Both move brilliance [both cutoffs] and level, and
    pressure brings in the sub oscillator's vibrato and wah on the pressed
    notes only;
  - the sub oscillator, the PWM LFOs, the noise and the ring modulator's
    carrier are single sources the whole instrument shares.  Every voice
    computes them from the host's sample clock [ctx.clock], so eight notes
    see one LFO in one phase and one noise, as on the original.

  Rates: the VCOs and filters run at 2x [hb9 down]; envelopes, touch and
  modulation once per sample; the shared modulators' phases in block-prepare.
  Guesses, all marked in docs/38: cutoff 0.85 octave per volt, the initial
  touch pulse's 0.25 s fall, the depth of each modulation route. )

include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"
include "../00-primitives/oversample.fy"
include "../01-oscillators/primitives/phase.fy"
include "../01-oscillators/primitives/blep.fy"
include "../01-oscillators/primitives/vco.fy"
include "../03-envelopes/primitives/env_rc.fy"
include "../08-analog/analog.fy"

:: CB-OPV 0.85 ;                    ( cutoff octaves per volt [guess] )
:: CB-KV0 7.03196347466 ;           ( log2 130.81 Hz: the key at KV 0.25 V, where 5 V puts fc at 1 kHz )
:: CB-SAT 0.35 ;                    ( the IG00156 OTAs' input range, signal units )
:: CB-ISAT 2.857142857142857 ;      ( 1 / CB-SAT )
:: CB-DEAD 0.02 ;                   ( the VCA EG rests 200 mV under the VCA's zero )

ustruct: CbSvf  f64 s1  f64 s2 ;

( One channel of one note: an M board. )
ustruct: CbChan
  f64 ph                             ( VCO phase )
  f64 fy  f64 fstage  f64 fstart  f64 fp  f64 fcr   ( VCF EG: volts, stage, attack start, progress, release coef )
  f64 ay  f64 astage  f64 acr        ( VCA EG )
  CbSvf hp
  CbSvf lp
  f64 lp1                            ( the LPF's gentle extra pole )
  f64 dro-x  f64 dro-y               ( the VCO output's coupling cap )
  f64 nlp                            ( the noise's low lump )
  f64 curve                          ( saw bow, from AGE )
  f64 pitch-sp  f64 hz-sp            ( tuning spread: a ratio and an offset in Hz )
  f64 cut-sp  f64 pw-sp              ( cutoff [volts] and pulse width spread )
  Drift dr
;

ustruct: CbState
  CbChan c1
  CbChan c2
  f64 t                              ( this voice's sample clock )
  f64 oct  f64 target-oct            ( key pitch, log2 Hz; glides )
  f64 gen                            ( the note group this note began, for SUSTAIN II )
  f64 vpe  f64 vp                    ( initial touch: the pulse, and its smoothed level )
  f64 press-t  f64 press             ( after touch 0..1: target and the pad's lag )
  f64 kb-v  f64 kb-g                 ( keyboard control: brilliance volts, level gain )
  f64 dc-x  f64 dc-y                 ( output coupling )
  f64 widx                           ( chorus BBD write head )
  f64 wl1  f64 wl2  f64 wr1  f64 wr2 ( the BBD's reconstruction filters )
  f64 buf  f64 buf-len               ( host buffer: the chorus delay line )
  Hb9 h9
;

( One channel's panel, then what block-prepare derives from it. )
ustruct: CbChanParams
  ( VCO )
  f64 feet                           ( frequency ratio to 8': .5 1 1.5 2 3 4 )
  f64 pwm-spd                        ( PWM LFO, Hz )
  f64 pwm  f64 pw                    ( 0..10 )
  f64 saw  f64 sqr                   ( switches 0/1 )
  f64 noise-l                        ( 0..10 )
  ( VCF )
  f64 hpf  f64 res-h  f64 lpf  f64 res-l   ( 0..10 )
  f64 il  f64 al                     ( 0..10 )
  f64 f-a  f64 f-d  f64 f-r          ( seconds )
  ( VCA )
  f64 vcf-lvl  f64 sine-l            ( 0..10 )
  f64 a-a  f64 a-d  f64 a-s  f64 a-r ( seconds, sustain 0..10 )
  f64 level                          ( 0..10 )
  ( touch )
  f64 i-bril  f64 i-lvl  f64 a-bril  f64 a-lvl   ( 0..10 )
  ( derived )
  f64 pwm-ph0  f64 pwm-inc
  f64 pw-c  f64 pwm-d
  f64 hp-mul  f64 lp-mul  f64 dh  f64 dl
  f64 il-v  f64 al-v
  f64 fca  f64 fcd  f64 fcr  f64 fcr-s
  f64 aca  f64 acd  f64 acr  f64 acr-s  f64 as-l
  f64 lvl  f64 ib  f64 ig  f64 ab  f64 ag
  f64 vlvl  f64 sine  f64 noise
  f64 det-r
;

ustruct: CbParams
  CbChanParams p1
  CbChanParams p2
  ( sub oscillator )
  f64 sub-fn  f64 sub-spd  f64 sub-vco-l  f64 sub-vcf-l  f64 sub-vca-l
  ( touch response )
  f64 tr-pitch  f64 tr-speed  f64 tr-vco  f64 tr-vcf
  ( keyboard control: -5..5 )
  f64 kb-bl  f64 kb-bh  f64 kb-ll  f64 kb-lh
  ( ring modulator )
  f64 ring-spd  f64 ring-mod  f64 ring-depth  f64 ring-a  f64 ring-d
  ( chorus / tremolo )
  f64 cho-mode  f64 cho-spd  f64 cho-depth
  ( master )
  f64 mix  f64 bril  f64 reso  f64 pitch  f64 detune
  f64 porta  f64 porta-t  f64 sus-mode  f64 sus-t
  f64 age  f64 vol
  ( shared state the note hooks keep: per-voice keys and pressures )
  f64 gates 16
  f64 prs 16
  f64 ring-trig
  f64 last-oct  f64 grp-clock  f64 grp-from  f64 gen
  ( derived by cb-block-prepare )
  f64 clk0
  f64 sub-ph0  f64 sub-inc
  f64 ring-ph0  f64 ring-inc  f64 ring-m  f64 ring-norm
  f64 cho-ph0  f64 cho-inc  f64 cho-d0  f64 cho-dm  f64 cho-am  f64 cho-dry  f64 cho-wet  f64 bbd-c
  f64 sub-vco  f64 sub-vcf  f64 sub-vca
  f64 a-vco  f64 a-vcf  f64 i-pitch
  f64 kv-off  f64 tune
  f64 g1  f64 g2
  f64 glide-step  f64 gliss
  f64 sus-cut  f64 any-noise
  f64 inv-osr  f64 pi-osr  f64 fc-lo  f64 fc-hi
  f64 dro-a  f64 nlp-c  f64 dc-a
  f64 drift-c  f64 drift-m  f64 drift-hz  f64 bleed
  f64 vp-dec  f64 vp-sm  f64 press-sm
;

( --- shared sources ------------------------------------------------------ )

( t salt -- n : white noise in -1..1 as a function of the sample clock.
  Every voice reading the same t and salt gets the same sample: the
  CS-80's noise is one zener per channel, shared by all eight voices.
  A Weyl step on t [split so the products stay exact] through two
  quadratic folds: flat to 0.1 dB, lag-1 correlation under 0.005. )
dsp: cb-hash | t salt -- n |
  t 0.000244140625 f* ffrac 4096.0 f* | lo |
  t lo f- 0.000244140625 f* | hi |
  lo 0.7548776662466927 f*  hi 0.5698402909980532 f* f+  salt f+ ffrac | w |
  w  w 179.37 f* 31.17 f+  f* ffrac | w |
  w  w 137.13 f* 41.97 f+  f* ffrac | w |
  w 2.0 f* 1.0 f-
;

( --- the IG00156 ---------------------------------------------------------- )

( f x g a h -- hp bp lp : one 2x step of an OTA state-variable filter.
  a = 2d + g, h = 1 / [1 + g a].  The linear zero-delay solve, then each
  integrator's OTA through its tanh: a loud signal runs them out of
  current and the Q falls.  The filter thickens; it never screams. )
dsp: cb-svf | f:CbSvf x g a h -- hp bp lp |
  f.s1 | s1 |
  f.s2 | s2 |
  x  a s1 f* f-  s2 f-  h f* | hp |
  hp CB-SAT f* tanh-fast CB-ISAT f* g f* | v1 |
  s1 v1 f+ | bp |
  bp CB-SAT f* tanh-fast CB-ISAT f* g f* | v2 |
  s2 v2 f+ | lp |
  bp v1 f+ -> f.s1
  lp v2 f+ -> f.s2
  hp bp lp
;

( --- one channel ---------------------------------------------------------- )

( one 2x substep: the core, the mixer, both filters, the sine, the VCA. )
dsp: cb-sub | c:CbChan cp:CbChanParams p:CbParams dt pw gh ah hh gl al hl gp g n -- y |
  c.ph dt f+ wrap01 | ph |
  ph -> c.ph
  ( the switches multiply: an ifte per switch per channel would
    outnumber the 32 bodies fy versions )
  ph dt c.curve vco-saw cp.saw f*  ph dt pw pulse-polyblep cp.sqr f*  f+ | m |
  ( the zener's noise, with its lump of low end )
  c.nlp  n c.nlp f- p.nlp-c f*  f+ | nl |
  nl -> c.nlp
  m  n nl 6.0 f* f+ cp.noise f*  f+ | x |
  x c.dro-x c.dro-y p.dro-a droop-hp | xd |
  x -> c.dro-x
  xd -> c.dro-y
  c.hp& xd gh ah hh cb-svf | h0 h1 h2 |
  c.lp& h0 gl al hl cb-svf | l0 l1 l2 |
  ( the gentle pole the IG00156's damping network adds above the LPF )
  l2 c.lp1 f- gp f* | u |
  c.lp1 u f+ | v |
  v u f+ -> c.lp1
  ( the sine: the WSC's triangle bent round, after both filters )
  1.0  ph 0.5 f- fabs 4.0 f*  f- | tr |
  tr  1.5  tr tr f* 0.5 f*  f-  f* | sn |
  v cp.vlvl f*  sn cp.sine f*  f+ | a |
  ( the IG00151 VCA, soft at the top )
  a 0.5 f* tanh-fast 2.0 f* g f*
;

( one channel for one sample: its envelopes, cutoffs and gain, then two
  substeps.  Returns both 2x samples and the VCA's gain [for the bleed]. )
dsp: cb-chan | c:CbChan cp:CbChanParams p:CbParams t k po vib ipb cvc gmul vp pr cut salt -- y0 y1 g |
  ( pitch: the key voltage through the feet, and AGE's drift and spread:
    a ratio, and an offset in Hz that the bass hears more of )
  c.dr& p.drift-c drift-step | dr |
  po exp2 p.tune f* cp.det-r f*  c.hz-sp f+  dr p.drift-hz f* f+
    cp.feet f*  c.pitch-sp f*  dr p.drift-m f* 1.0 f+ f*
    vib exp2 f*  ipb f*  p.inv-osr f*  0.0 0.45 fclamp | dt |
  ( PWM: this channel's LFO, one for all eight voices )
  cp.pwm-ph0 k cp.pwm-inc f* f+ sin2pi | pl |
  cp.pw-c  pl cp.pwm-d f*  f+  c.pw-sp f+  0.03 0.97 fclamp | pw |
  ( VCF EG: IL -> AL -> 0 [the sliders], release back to IL )
  c.fstage | fs |
  c.fp  1.2 c.fp f- cp.fca f*  f+ | fp1 |
  fs 0.5 f>  fs 1.5 f< and | fatk |
  fatk  fp1 1.0 f>= and | ftop |
  cut  cp.fcr  c.fcr  select | fcr |
  fs 0.5 f<
    c.fy  cp.il-v c.fy f- fcr f*  f+
    fs 1.5 f<
      c.fstart  cp.al-v c.fstart f-  fp1 1.0 fmin f*  f+
      c.fy  c.fy cp.fcd f*  f-
    select
  select | fy |
  fy -> c.fy
  fatk fp1 c.fp select -> c.fp
  ftop 2.0 fs select -> c.fstage
  ( VCA EG: ADSR; the attack aims past the top, an RC's knee )
  c.astage | ast |
  cut  cp.acr  c.acr  select | acr |
  ast 0.5 f<
    c.ay  c.ay acr f*  f-
    ast 1.5 f<
      c.ay  1.2 c.ay f- cp.aca f*  f+
      c.ay  cp.as-l c.ay f- cp.acd f*  f+
    select
  select | ay0 |
  ast 0.5 f>  ast 1.5 f< and  ay0 1.0 f>= and | atop |
  atop 1.0 ay0 select | ay |
  ay -> c.ay
  atop 2.0 ast select -> c.astage
  ( cutoffs: both filters move together, by the envelope, brilliance,
    keyboard control, touch and the sub oscillator, and follow the key )
  fy cvc f+  vp cp.ib f* f+  pr cp.ab f* f+  c.cut-sp f+  5.0 f-  CB-OPV f*
    po f+  p.kv-off f+  exp2 1000.0 f* | fb |
  fb cp.hp-mul f* p.fc-lo p.fc-hi fclamp | fh |
  fb cp.lp-mul f* p.fc-lo p.fc-hi fclamp | fl |
  fh p.pi-osr f* tan-warp | gh |
  fl p.pi-osr f* tan-warp | gl |
  ( the damping grows toward the top of the range: Q is frequency dependent )
  fh p.inv-osr f* 3.0 f* 1.0 f+ cp.dh f* 2.0 f*  gh f+ | ah |
  fl p.inv-osr f* 3.0 f* 1.0 f+ cp.dl f* 2.0 f*  gl f+ | al |
  1.0  1.0 gh ah f* f+  f/ | hh |
  1.0  1.0 gl al f* f+  f/ | hl |
  gl 5.0 f* 20.0 fmin | g5 |
  g5  1.0 g5 f+  f/ | gp |
  ( the VCA: envelope x [LEVEL + touch], under the dead zone nothing )
  ay  cp.lvl  vp cp.ig f* f+  pr cp.ag f* f+  f*  gmul f*  CB-DEAD f-  0.0 fmax  1.0204081632653061 f* | g |
  ( the channel's noise source, two 2x samples of it )
  p.any-noise 0.5 f<
    [ 0.0 0.0 ]
    [ t 2.0 f* salt cb-hash  t 2.0 f* 1.0 f+ salt cb-hash ]
  ifte | n0 n1 |
  c cp p dt pw gh ah hh gl al hl gp g n0 cb-sub
  c cp p dt pw gh ah hh gl al hl gp g n1 cb-sub
  g
;

( --- block rate ------------------------------------------------------------ )

( cp p dt inv osr det -- : one channel's derived fields. )
dsp: cb-chan-prep | cp:CbChanParams p:CbParams dt inv det -- |
  cp.pwm-ph0  dt cp.pwm-inc f*  f+ ffrac -> cp.pwm-ph0
  cp.pwm-spd inv f* -> cp.pwm-inc
  cp.pw 0.04 f* 0.5 f+ -> cp.pw-c
  cp.pwm 0.04 f* -> cp.pwm-d
  cp.hpf CB-OPV f* exp2 -> cp.hp-mul
  cp.lpf CB-OPV f* exp2 -> cp.lp-mul
  ( d = 1/2Q: 10 V of VQ gives Q 0.5, 0 V Q 5, on a log law )
  cp.res-h p.reso f+ 0.0 10.0 fclamp -0.33219280948873625 f* exp2 -> cp.dh
  cp.res-l p.reso f+ 0.0 10.0 fclamp -0.33219280948873625 f* exp2 -> cp.dl
  cp.il -0.5 f* -> cp.il-v
  cp.al 0.5 f* -> cp.al-v
  p.sus-mode 0.5 f>  p.sus-t 0.0 select | st |
  cp.f-a inv 1.791759469228055 env-rc-coef -> cp.fca
  cp.f-d inv 4.605170185988091 env-rc-coef -> cp.fcd
  cp.f-r inv 4.605170185988091 env-rc-coef -> cp.fcr
  cp.f-r st fmax inv 4.605170185988091 env-rc-coef -> cp.fcr-s
  cp.a-a inv 1.791759469228055 env-rc-coef -> cp.aca
  cp.a-d inv 4.605170185988091 env-rc-coef -> cp.acd
  cp.a-r inv 4.605170185988091 env-rc-coef -> cp.acr
  cp.a-r st fmax inv 4.605170185988091 env-rc-coef -> cp.acr-s
  cp.a-s 0.1 f* -> cp.as-l
  cp.level 0.1 f* -> cp.lvl
  ( touch: 6.4 V at 10 on each lever; level against LEVEL's 10 V )
  cp.i-bril 0.64 f* -> cp.ib
  cp.i-lvl 0.064 f* -> cp.ig
  cp.a-bril 0.64 f* -> cp.ab
  cp.a-lvl 0.064 f* -> cp.ag
  cp.vcf-lvl 0.1 f* -> cp.vlvl
  cp.sine-l 0.12 f* -> cp.sine
  cp.noise-l 0.1 f* -> cp.noise
  det -> cp.det-r
;

( ctx state params -- )
dsp: cb-block-prepare | ctx:Ctx state params:CbParams -- |
  ctx.sr | sr |
  ctx.inv-sr | inv |
  sr 2.0 f* | osr |
  ( the shared modulators run on the host clock: carry each phase over
    the samples since the last call, at the rate it had )
  ctx.clock params.clk0 f- 0.0 fmax | dt |
  params.sub-ph0  dt params.sub-inc f*  f+ ffrac -> params.sub-ph0
  params.ring-ph0  dt params.ring-inc f*  f+ ffrac -> params.ring-ph0
  params.cho-ph0  dt params.cho-inc f*  f+ ffrac -> params.cho-ph0
  ctx.clock -> params.clk0
  ( the hardest-pressed key, for AFTER SPEED )
  0.0 0.0 16 [ | i m | i 1.0 f+  m params.prs& i f@i fmax ] times | ni pmax |
  ( sub oscillator: 0.7..60 Hz, and pressure speeds it up to 3.6 octaves )
  params.tr-speed 0.36 f* pmax f* exp2 params.sub-spd f* inv f* -> params.sub-inc
  params.sub-vco-l 0.1 f* -> params.sub-vco
  params.sub-vcf-l 0.3 f* -> params.sub-vcf
  params.sub-vca-l 0.1 f* -> params.sub-vca
  params.tr-vco 0.0083333 f* -> params.a-vco
  params.tr-vcf 0.2 f* -> params.a-vcf
  params.tr-pitch 0.05 f* -> params.i-pitch
  ( ring modulator: the AD envelope raises the carrier by up to 4 octaves )
  ctx.clock params.ring-trig f- inv f* 0.0 fmax | rt |
  params.ring-a 0.0005 fmax | ra |
  params.ring-d 0.001 fmax | rd |
  rt ra f<
    1.0  rt ra f/ -3.0 f* exp  f-  1.0524033 f*
    rt ra f- rd f/ -4.605170185988091 f* -80.0 fmax exp
  select | re |
  params.ring-depth 0.4 f* re f* exp2 params.ring-spd f* inv f* -> params.ring-inc
  params.ring-mod 0.1 f* -> params.ring-m
  0.8044387 -> params.ring-norm            ( 1 / tanh 1.4 )
  ( chorus: 0.5..5 Hz, tremolo 5..20 Hz; the MN3001 sits near 2.5 ms )
  params.cho-mode | cm |
  params.cho-spd 0.1 f* | cs |
  params.cho-depth 0.1 f* | cd |
  cm 1.5 f<
    cs 3.321928094887362 f* exp2 0.5 f*
    cs 2.0 f* exp2 5.0 f*
  select inv f* -> params.cho-inc
  0.0025 sr f* -> params.cho-d0
  cm 1.5 f<  0.0008  0.00025  select cd f* sr f* -> params.cho-dm
  cm 1.5 f<  0.12  0.7  select cd f* -> params.cho-am
  cm 1.5 f<  0.66  0.9  select -> params.cho-dry
  cm 1.5 f<  0.66  0.35  select -> params.cho-wet
  1.0  -6.283185307179586 12000.0 f* inv f* exp  f- -> params.bbd-c
  ( pitch: PITCH -5..+7 semitones scales the key DAC's reference )
  params.pitch 0.08333333333333333 f* exp2 | tn |
  tn -> params.tune
  tn log2 CB-KV0 f- -> params.kv-off
  ( MIX: Channel I down to 0 at the bottom, II at the top, both at the middle )
  params.mix 0.1 f* | mx |
  1.0 mx f- 2.0 f* 1.0 fmin -> params.g1
  mx 2.0 f* 1.0 fmin -> params.g2
  ( portamento: a constant rate, the CS-80's semitone clock;
    glissando steps it )
  params.porta 0.5 f>
    0.08333333333333333  params.porta-t 0.00001 fmax sr f* f/
    100.0
  select -> params.glide-step
  params.porta 1.5 f> 1.0 0.0 select -> params.gliss
  params.sus-mode 1.5 f> 1.0 0.0 select -> params.sus-cut
  params.p1& CbChanParams.noise-l ptr+ f@64  params.p2& CbChanParams.noise-l ptr+ f@64  f+ 0.0 f> 1.0 0.0 select -> params.any-noise
  1.0 osr f/ -> params.inv-osr
  3.141592653589793 osr f/ -> params.pi-osr
  10.0 -> params.fc-lo
  osr 0.42 f* -> params.fc-hi
  1.0  1.0  6.283185307179586 5.0 f* osr f/  f+  f/ -> params.dro-a
  6.283185307179586 60.0 f* osr f/ -> params.nlp-c
  1.0  1.0  6.283185307179586 5.0 f* inv f*  f+  f/ -> params.dc-a
  ( AGE: drift up to ~4 cents and 0.12 Hz at 1; CV bleed into the audio )
  0.3 inv drift-coef -> params.drift-c
  params.age 0.0023 f* -> params.drift-m
  params.age 0.12 f* -> params.drift-hz
  params.age 0.03 f* -> params.bleed
  ( initial touch falls in ~0.25 s [guess]; after touch lags the pad ~20 ms )
  -4.0 inv f* exp -> params.vp-dec
  1.0  -333.0 inv f* exp  f- -> params.vp-sm
  1.0  -50.0 inv f* exp  f- -> params.press-sm
  params.p1& params dt inv 1.0 cb-chan-prep
  params.p2& params dt inv params.detune 0.08333333333333333 f* exp2 cb-chan-prep
;

( --- note hooks ------------------------------------------------------------- )

( c cp p ctx salt -- : a channel's key down. )
dsp: cb-chan-on | c:CbChan cp:CbChanParams p:CbParams ctx:Ctx salt -- |
  ctx.chan | v |
  c.dr& v 1.0 f+ salt 13.0 f* f+ drift-seed-once
  c.ph 0.0 f=  ctx.phase salt 0.381966 f* f+ ffrac  c.ph  select -> c.ph
  ( AGE: this board's parts, the same way every time )
  p.age | ag |
  v salt 1.0 f+ spread ag f* 0.05 f* 0.1 f+ -> c.curve
  v salt 2.0 f+ spread ag f* 0.0015 f* exp2 -> c.pitch-sp
  v salt 3.0 f+ spread ag f* 0.12 f* -> c.hz-sp
  v salt 4.0 f+ spread ag f* 0.3 f* -> c.cut-sp
  v salt 5.0 f+ spread ag f* 0.02 f* -> c.pw-sp
  ( a voice that has died away starts its filter envelope at IL )
  c.ay 0.0001 f<  cp.il-v  c.fy  select | fy |
  fy -> c.fy
  ctx.legato 0.5 f< | fresh |
  fresh fy c.fstart select -> c.fstart
  fresh 0.0 c.fp select -> c.fp
  fresh 1.0 c.fstage select -> c.fstage
  fresh 1.0 c.astage select -> c.astage
;

( ctx state params -- )
dsp: cb-note-on | ctx:Ctx state:CbState params:CbParams -- |
  ctx.hz 1.0 fmax log2 | o |
  ctx.clock -> state.t
  ( a chord is one group: its notes glide from one note, and a new group
    ends SUSTAIN II's die-away )
  ctx.clock params.grp-clock f= not | newg |
  newg params.last-oct params.grp-from select | from |
  from -> params.grp-from
  ctx.clock -> params.grp-clock
  newg params.gen 1.0 f+ params.gen select | gen |
  gen -> params.gen
  gen -> state.gen
  o -> params.last-oct
  o -> state.target-oct
  ctx.legato 0.5 f>
    state.oct
    params.porta 0.5 f>  from 1.0 f> and  from o select
  select -> state.oct
  ( keyboard control: smooth toward each end, nothing at the middle )
  66.0 ctx.pitch f- 0.03333333333333333 f* 0.0 1.0 fclamp | xl |
  xl xl f*  3.0 xl 2.0 f* f-  f* | cl |
  ctx.pitch 66.0 f- 0.03333333333333333 f* 0.0 1.0 fclamp | xh |
  xh xh f*  3.0 xh 2.0 f* f-  f* | ch |
  params.kb-bl cl f*  params.kb-bh ch f* f+  0.552 f* -> state.kb-v
  params.kb-ll cl f*  params.kb-lh ch f* f+  0.0552 f* 1.0 f+ 0.0 fmax -> state.kb-g
  ( touch: the stroke's pulse; the pad starts at rest )
  ctx.vel -> state.vpe
  0.0 -> state.press-t
  0.0 params.prs& ctx.chan f!i
  ( the ring modulator attacks again only once every key was up )
  0.0 0.0 16 [ | i s | i 1.0 f+  s params.gates& i f@i f+ ] times | ni s |
  s  params.gates& ctx.chan f@i  f- | others |
  others 0.5 f<  ctx.clock  params.ring-trig  select -> params.ring-trig
  1.0 params.gates& ctx.chan f!i
  state.c1& params.p1& params ctx 1.0 cb-chan-on
  state.c2& params.p2& params ctx 2.0 cb-chan-on
;

( ctx state params -- : expression bends the key [a glide in flight
  keeps its offset] and presses the pad: pressure rests at 0.5, the pad's
  threshold, and after touch is what lies above it. )
dsp: cb-note-expr | ctx:Ctx state:CbState params:CbParams -- |
  ctx.hz 1.0 fmax log2 | o |
  state.oct  o state.target-oct f-  f+ -> state.oct
  o -> state.target-oct
  ctx.pressure 0.5 f- 2.0 f* 0.0 1.0 fclamp | a |
  a -> state.press-t
  a params.prs& ctx.chan f!i
;

( c cp -- : key up; SUSTAIN stretches both releases. )
dsp: cb-chan-off | c:CbChan cp:CbChanParams -- |
  0.0 -> c.fstage
  0.0 -> c.astage
  cp.fcr-s -> c.fcr
  cp.acr-s -> c.acr
;

( ctx state params -- )
dsp: cb-note-off | ctx:Ctx state:CbState params:CbParams -- |
  0.0 params.gates& ctx.chan f!i
  0.0 params.prs& ctx.chan f!i
  0.0 -> state.press-t
  state.c1& params.p1& cb-chan-off
  state.c2& params.p2& cb-chan-off
;

( --- the voice ---------------------------------------------------------------- )

( buf len w d -- y : a BBD tap d samples behind the head, linear. )
dsp: cb-tap | buf len w d -- y |
  w d f- | p0 |
  p0 0.0  p0 len f+  p0  fsel-lt | p |
  p ffrac | fr |
  p 1.0 f+ | q0 |
  q0 len f>=  q0 len f-  q0  select | q |
  buf p f@i | x0 |
  buf q f@i | x1 |
  x0  x1 x0 f- fr f*  f+
;

( io ctx state params -- : one output sample, both sides. )
dsp: k-cb-voice | io:Io ctx state:CbState params:CbParams -- |
  state.t | t |
  t params.clk0 f- | k |
  t 1.0 f+ -> state.t
  ( the sub oscillator: one for the instrument )
  params.sub-ph0  k params.sub-inc f*  f+ ffrac | sp |
  params.sub-fn 0.5 f<
    [ sp sin2pi ]
    [ params.sub-fn | fn |
      fn 1.5 f<  1.0 sp 2.0 f* f-
        fn 2.5 f<  sp 2.0 f* 1.0 f-
          fn 3.5 f<  sp 0.5 1.0 -1.0 fsel-lt  t 0.123 cb-hash  select
        select
      select ]
  ifte | sub |
  ( touch: the stroke's pulse falls away; pressure follows the pad )
  state.vpe params.vp-dec f* | vpe |
  vpe -> state.vpe
  state.vp  vpe state.vp f- params.vp-sm f*  f+ | vp |
  vp -> state.vp
  state.press  state.press-t state.press f- params.press-sm f*  f+ | pr |
  pr -> state.press
  ( portamento at a constant rate; glissando lands on semitones )
  state.oct  state.target-oct state.oct f-  params.glide-step fneg params.glide-step fclamp  f+ | oct |
  oct -> state.oct
  oct state.target-oct f- 12.0 f* 0.5 f+ | q |
  params.gliss 0.5 f>
    q q ffrac f- 0.08333333333333333 f* state.target-oct f+
    oct
  select | po |
  ( the modulation every channel shares )
  sub  params.sub-vco pr params.a-vco f* f+  f* | vib |
  1.0  vp params.i-pitch f*  f-  0.0 fmax | ipb |
  params.bril  state.kb-v f+  sub  params.sub-vcf pr params.a-vcf f* f+  f*  f+ | cvc |
  state.kb-g  1.0  params.sub-vca 0.5 f*  1.0 sub f-  f*  f-  f* | gmul |
  params.sus-cut 0.5 f>  state.gen params.gen f= not  and | cut |
  state.c1& params.p1& params t k po vib ipb cvc gmul vp pr cut 0.31 cb-chan | a0 a1 ga |
  state.c2& params.p2& params t k po vib ipb cvc gmul vp pr cut 0.67 cb-chan | b0 b1 gb |
  state.h9&
    a0 params.g1 f*  b0 params.g2 f*  f+
    a1 params.g1 f*  b1 params.g2 f*  f+
  hb9-dec | y |
  ( the ring modulator: the mix times one shared sine, a little bent )
  params.ring-m 0.0 f=
    [ y ]
    [ params.ring-ph0  k params.ring-inc f*  f+ sin2pi 1.4 f* tanh-fast params.ring-norm f* | rc |
      y  1.0 params.ring-m f-  rc params.ring-m f*  f+  f* ]
  ifte | y |
  ( the VCAs' control voltage leaks through, and the output cap takes it out )
  y  ga gb f+ params.bleed f*  f+ | yb |
  yb state.dc-x state.dc-y params.dc-a droop-hp | o0 |
  yb -> state.dc-x
  o0 -> state.dc-y
  o0 params.vol f* 0.25 f* | o |
  params.cho-mode 0.5 f<
    [ io.out-l o f+ -> io.out-l
      io.out-r o f+ -> io.out-r ]
    [ ( the MN3001: two lines in antiphase, and the AM VCAs )
      state.buf& p@64 | buf |
      state.buf-len | len |
      state.widx | w |
      o buf w f!i
      w 1.0 f+ | w1 |
      w1 len f>=  0.0  w1  select -> state.widx
      params.cho-ph0  k params.cho-inc f*  f+ ffrac | cph |
      cph sin2pi | cl |
      cph 0.25 f+ sin2pi | cq |
      buf len w  params.cho-d0 cl params.cho-dm f* f+  cb-tap | wl |
      buf len w  params.cho-d0 cl params.cho-dm f* f-  cb-tap | wr |
      state.wl1  wl state.wl1 f- params.bbd-c f*  f+ | l1 |
      state.wl2  l1 state.wl2 f- params.bbd-c f*  f+ | l2 |
      state.wr1  wr state.wr1 f- params.bbd-c f*  f+ | r1 |
      state.wr2  r1 state.wr2 f- params.bbd-c f*  f+ | r2 |
      l1 -> state.wl1  l2 -> state.wl2  r1 -> state.wr1  r2 -> state.wr2
      o params.cho-dry f*  l2 params.cho-wet f*  f+  1.0 cq params.cho-am f* f+  f* | yl |
      o params.cho-dry f*  r2 params.cho-wet f*  f+  1.0 cq params.cho-am f* f-  f* | yr |
      io.out-l yl f+ -> io.out-l
      io.out-r yr f+ -> io.out-r ]
  ifte
;
