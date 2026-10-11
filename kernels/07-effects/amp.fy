( amp.fy - an instrument amplifier and its cabinet: preamp, tone stack,
  power amp, speaker, and a DI to blend back in.

    in -> TIGHT [input coupling HP] -> GAIN -> up4
       -> triode stages x VOICE [Miller LP, curve, coupling HP, invert]
       -> tone stack [BASS MID TREBLE, the passive network]
       -> power amp [MASTER drive, push-pull curve, SAG]
       -> dec4 -> PRESENCE [high shelf] -> cabinet [CAB, MIC] -> LEVEL
    in -> [aligned with the halfbands] -> BLEND with the amp

  The triode: a positive grid swing runs into grid current and clips
  hard, a negative one into cutoff, softer and later.  The curve is
  lopsided that way [even harmonics], and each stage inverts, so cascaded
  stages trade which side clips first, as real ones do.  The Miller
  capacitance rolls the highs off ahead of each grid; the coupling cap
  after each plate sets how much low end the next stage gets to clip.

  VOICE picks the stage count, their gains and filters, and the tone
  stack's parts:
    voice   stages  stack parts [C1 C2 C3, R1 R2 R3 R4]   after
    BASS    1       250p 20n 20n, 250k 1M 25k 56k         Bassman '59
    CLEAN   1       250p 100n 47n, 250k 250k 10k 100k     blackface
    BRIT    2       470p 22n 22n, 220k 1M 22k 33k         JCM800
    HIGAIN  3       470p 22n 22n, 220k 1M 22k 33k         a hot-rodded JCM

  The tone stack is the passive three-knob network, from its analog
  transfer function [Yeh and Smith, "Discretization of the '59 Fender
  Bassman Tone Stack", DAFx 2006] by the bilinear transform at the 4x
  rate.  The controls interact the way the circuit's do: the mid knob
  fills the scoop, the treble knob moves the mids.  BASS is a log-taper
  pot, as in the amps.

  The cabinet is parametric: the speaker's low resonance as a resonant
  high-pass, three bells for the box and cone, and a 4th-order roll-off.
  MIC slides from the cone's center toward its edge: darker, less bite.
    cab    resonance    bells                          roll-off
    1x12   80 Hz soft   +2 @ 120, -3 @ 500, +5 @ 2.5k  5.5 kHz  open back
    4x12   95 Hz peak   +2 @ 120, -3 @ 700, +6 @ 2.8k  5 kHz    closed
    1x15   45 Hz        +3 @ 90, +2 @ 500, -3 @ 1.5k   2.5 kHz  bass
    8x10   55 Hz peak   +3 @ 100, -2 @ 400, +4 @ 1.8k  4 kHz    bass, growl
    4x10   50 Hz        +2 @ 110, +1 @ 800, +3 @ 3.5k  9 kHz    with a horn

  BLEND mixes the clean input back in, delayed by the oversampler's
  latency so the two line up [a bass player's DI + amp].  Dual mono. )

include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"
include "../00-primitives/oversample.fy"
include "../04-filters/tone.fy"
include "../04-filters/coeffs.fy"   ( svf-dc-coeff )

:: AMP-FLUSH 1.0e-18 ;

ustruct: Svf  f64 s1  f64 s2 ;
ustruct: SvfK  f64 g  f64 d  f64 h ;   ( h = 1 / [1 + 2dg + g^2] )

ustruct: AmpState
  Pole tight
  Up4 up
  Dec4 dec
  Pole m1  Pole c1     ( stage 1: Miller LP, coupling HP )
  Pole m2  Pole c2
  Pole m3  Pole c3
  f64 z1  f64 z2  f64 z3   ( tone stack, transposed direct form II )
  f64 env                  ( SAG follower )
  Pole pres
  Svf hp  Svf lp1  Svf lp2
  BellSt b1  BellSt b2  BellSt b3
  f64 d1  f64 d2  f64 d3  f64 d4  f64 d5   ( the DI, waiting for the halfbands )
;

ustruct: AmpParams
  ( user-facing )
  f64 voice      ( 0 BASS, 1 CLEAN, 2 BRIT, 3 HIGAIN )
  f64 gain       ( 0..1 preamp gain )
  f64 tight      ( Hz: input coupling high-pass )
  f64 bass       ( 0..1 )
  f64 mid        ( 0..1 )
  f64 treble     ( 0..1 )
  f64 presence   ( 0..1 )
  f64 master     ( 0..1 power amp drive )
  f64 sag        ( 0..1 )
  f64 cab        ( 0 off, 1 1x12, 2 4x12, 3 1x15, 4 8x10, 5 4x10 )
  f64 mic        ( 0 center .. 1 edge )
  f64 blend      ( 0 amp .. 1 DI )
  f64 level-db
  ( derived - amp-block-prepare )
  f64 lat
  f64 tight-G
  f64 g1  f64 g2  f64 g3     ( stage gains )
  f64 miller-G  f64 cpl-G
  f64 sb0 f64 sb1 f64 sb2 f64 sb3  f64 sa1 f64 sa2 f64 sa3
  f64 pw-g  f64 pw-mk  f64 sag-k  f64 env-a
  Shelf pres-sh
  SvfK hpk  SvfK lpk  SvfK lp2k
  Bell cb1  Bell cb2  Bell cb3
  f64 wet  f64 dry
;

( v k0 k1 k2 k3 -- k : the entry for VOICE v. )
dsp: amp-by-voice | v k0 k1 k2 k3 -- k |
  v 2.5 f< v 1.5 f< v 0.5 f< k0 k1 select k2 select k3 select
;

( c k1 k2 k3 k4 k5 -- k : the entry for CAB c [1..5]. )
dsp: amp-by-cab | c k1 k2 k3 k4 k5 -- k |
  c 4.5 f< c 3.5 f< c 2.5 f< c 1.5 f< k1 k2 select k3 select k4 select k5 select
;

( p f d sr -- : TPT SVF coefficients. )
dsp: svf-k-set | p:SvfK f d sr -- |
  f 3.141592653589793 f* sr f/ tan | g |
  g -> p.g  d -> p.d
  1.0  1.0 2.0 d f* g f* f+ g g f* f+  f/ -> p.h
;

( st k x -- lp hp )
dsp: svf-lphp | st:Svf k:SvfK x -- lp hp |
  x  2.0 k.d f* k.g f+ st.s1 f* f-  st.s2 f-  k.h f* | hp |
  k.g hp f* st.s1 f+ | bp |
  k.g bp f* st.s2 f+ | lp |
  k.g hp f* bp f+ -> st.s1
  k.g bp f* lp f+ -> st.s2
  lp hp
;

( The tone stack's analog coefficients [Yeh and Smith 2006], t m l the
  treble, mid and bass pot positions, then the bilinear transform at fs. )
dsp: amp-stack-set | params:AmpParams t m l fs -- |
  params.voice 0.00000000025 0.00000000025 0.00000000047 0.00000000047 amp-by-voice | C1 |
  params.voice 0.00000002 0.0000001 0.000000022 0.000000022 amp-by-voice | C2 |
  params.voice 0.00000002 0.000000047 0.000000022 0.000000022 amp-by-voice | C3 |
  params.voice 250000.0 250000.0 220000.0 220000.0 amp-by-voice | R1 |
  params.voice 1000000.0 250000.0 1000000.0 1000000.0 amp-by-voice | R2 |
  params.voice 25000.0 10000.0 22000.0 22000.0 amp-by-voice | R3 |
  params.voice 56000.0 100000.0 33000.0 33000.0 amp-by-voice | R4 |
  C1 C2 f* C3 f* | c123 |
  t C1 f* R1 f*  m C3 f* R3 f* f+  l C1 R2 f* C2 R2 f* f+ f* f+  C1 R3 f* C2 R3 f* f+ f+ | b1 |
  t  C1 C2 f* R1 f* R4 f*  C1 C3 f* R1 f* R4 f* f+  f*
  m m f*  C1 C3 f* R3 f* R3 f*  C2 C3 f* R3 f* R3 f* f+  f* f-
  m  C1 C3 f* R1 f* R3 f*  C1 C3 f* R3 f* R3 f* f+  C2 C3 f* R3 f* R3 f* f+  f* f+
  l  C1 C2 f* R1 f* R2 f*  C1 C2 f* R2 f* R4 f* f+  C1 C3 f* R2 f* R4 f* f+  f* f+
  l m f*  C1 C3 f* R2 f* R3 f*  C2 C3 f* R2 f* R3 f* f+  f* f+
  C1 C2 f* R1 f* R3 f*  C1 C2 f* R3 f* R4 f* f+  C1 C3 f* R3 f* R4 f* f+  f+ | b2 |
  l m f*  c123 R1 f* R2 f* R3 f*  c123 R2 f* R3 f* R4 f* f+  f*
  m m f*  c123 R1 f* R3 f* R3 f*  c123 R3 f* R3 f* R4 f* f+  f* f-
  m  c123 R1 f* R3 f* R3 f*  c123 R3 f* R3 f* R4 f* f+  f* f+
  t c123 f* R1 f* R3 f* R4 f* f+
  t m f* c123 f* R1 f* R3 f* R4 f* f-
  t l f* c123 f* R1 f* R2 f* R4 f* f+ | b3 |
  C1 R1 f* C1 R3 f* f+ C2 R3 f* f+ C2 R4 f* f+ C3 R4 f* f+
  m C3 f* R3 f* f+  l C1 R2 f* C2 R2 f* f+ f* f+ | a1 |
  m  C1 C3 f* R1 f* R3 f*  C2 C3 f* R3 f* R4 f* f-  C1 C3 f* R3 f* R3 f* f+  C2 C3 f* R3 f* R3 f* f+  f*
  l m f*  C1 C3 f* R2 f* R3 f*  C2 C3 f* R2 f* R3 f* f+  f* f+
  m m f*  C1 C3 f* R3 f* R3 f*  C2 C3 f* R3 f* R3 f* f+  f* f-
  l  C1 C2 f* R2 f* R4 f*  C1 C2 f* R1 f* R2 f* f+  C1 C3 f* R2 f* R4 f* f+  C2 C3 f* R2 f* R4 f* f+  f* f+
  C1 C2 f* R1 f* R4 f*  C1 C3 f* R1 f* R4 f* f+  C1 C2 f* R3 f* R4 f* f+
    C1 C2 f* R1 f* R3 f* f+  C1 C3 f* R3 f* R4 f* f+  C2 C3 f* R3 f* R4 f* f+  f+ | a2 |
  l m f*  c123 R1 f* R2 f* R3 f*  c123 R2 f* R3 f* R4 f* f+  f*
  m m f*  c123 R1 f* R3 f* R3 f*  c123 R3 f* R3 f* R4 f* f+  f* f-
  m  c123 R3 f* R3 f* R4 f*  c123 R1 f* R3 f* R3 f* f+  c123 R1 f* R3 f* R4 f* f-  f* f+
  l c123 f* R1 f* R2 f* R4 f* f+
  c123 R1 f* R3 f* R4 f* f+ | a3 |
  ( bilinear, c = 2 fs; b0 = 0 )
  2.0 fs f* | c |  c c f* | c2 |  c2 c f* | c3 |
  b1 c f* | x1 |  b2 c2 f* | x2 |  b3 c3 f* | x3 |
  a1 c f* | y1 |  a2 c2 f* | y2 |  a3 c3 f* | y3 |
  -1.0 y1 f- y2 f- y3 f- | A0 |
  -3.0 y1 f- y2 f+ 3.0 y3 f* f+ | A1 |
  -3.0 y1 f+ y2 f+ 3.0 y3 f* f- | A2 |
  -1.0 y1 f+ y2 f- y3 f+ | A3 |
  1.0 A0 f/ | ia |
  x1 fneg x2 f- x3 f- ia f* -> params.sb0
  x1 fneg x2 f+ 3.0 x3 f* f+ ia f* -> params.sb1
  x1 x2 f+ 3.0 x3 f* f- ia f* -> params.sb2
  x1 x2 f- x3 f+ ia f* -> params.sb3
  A1 ia f* -> params.sa1
  A2 ia f* -> params.sa2
  A3 ia f* -> params.sa3
;

dsp: amp-cab-set | params:AmpParams sr -- |
  params.cab | c |
  params.mic | mic |
  params.hpk&  c 80.0 95.0 45.0 55.0 50.0 amp-by-cab
    c 0.7 0.35 0.5 0.38 0.45 amp-by-cab  sr svf-k-set
  c 5500.0 5000.0 2500.0 4000.0 9000.0 amp-by-cab  1.0 mic 0.45 f* f-  f* | lpf |
  ( 4th-order Butterworth: two sections at Q 0.54 and 1.31 )
  params.lpk&  lpf 0.924 sr svf-k-set
  params.lp2k& lpf 0.383 sr svf-k-set
  params.cb1&  c 120.0 120.0 90.0 100.0 110.0 amp-by-cab
    c 2.0 2.0 3.0 3.0 2.0 amp-by-cab  1.0 sr bell-set
  params.cb2&  c 500.0 700.0 500.0 400.0 800.0 amp-by-cab
    c -3.0 -3.0 2.0 -2.0 1.0 amp-by-cab  0.8 sr bell-set
  ( the cone's bite falls off toward its edge )
  params.cb3&  c 2500.0 2800.0 1500.0 1800.0 3500.0 amp-by-cab
    c 5.0 6.0 -3.0 4.0 3.0 amp-by-cab  1.0 mic f- f*  mic 3.0 f* f-  1.2 sr bell-set
;

dsp: amp-block-prepare | ctx:Ctx state params:AmpParams |
  ctx.sr | sr |  sr 4.0 f* | fs4 |
  OS4-LATENCY -> params.lat
  params.tight sr pole-G -> params.tight-G
  params.voice | v |
  params.gain | k |
  ( stage gains: the first takes GAIN, the later ones are fixed )
  v  1.0 k 14.0 f* f+  0.6 k 5.0 f* f+  1.0 k 24.0 f* f+  2.0 k 60.0 f* f+  amp-by-voice -> params.g1
  v  1.0 1.0 4.0 6.0 amp-by-voice -> params.g2
  v  1.0 1.0 1.0 4.0 amp-by-voice -> params.g3
  v  11000.0 12000.0 7500.0 6500.0 amp-by-voice  fs4 pole-G -> params.miller-G
  v  25.0 50.0 110.0 160.0 amp-by-voice  fs4 pole-G -> params.cpl-G
  ( tone stack: BASS is a log pot )
  params params.treble params.mid  params.bass 1.0 f- 4.905 f* exp2  fs4 amp-stack-set
  ( power amp: MASTER drives it; makeup keeps the level near the input's )
  0.4 params.master 5.0 f* f+ | pg |
  pg -> params.pw-g
  ( makeup: an instrument peaking near 0.1 comes out near 0.25, clean
    or saturated - the power curve tops out at 1, so a hot chain needs
    no more taming than a clean one needs lifting.  The stack's ~10 dB
    loss is the 0.3.  Each stage inverts: an odd count is turned back
    over, so BLEND adds the DI in phase instead of cancelling the lows. )
  params.g1 params.g2 f* params.g3 f* pg f* | gt |
  v  -0.25 -0.25 0.25 -0.25 amp-by-voice  gt 0.03 f* tanh  f/ -> params.pw-mk
  params.sag 2.0 f* -> params.sag-k
  sr 6.0 svf-dc-coeff -> params.env-a
  params.pres-sh&  3000.0  params.presence 12.0 f* 3.0 f-  1.0 sr shelf-set
  params sr amp-cab-set
  params.level-db db>lin | out |
  1.0 params.blend f- out f* -> params.wet
  params.blend out f* -> params.dry
;

( x -- y : a triode's grid-to-plate curve, inverted: grid current clips
  a positive swing hard, cutoff a negative one softly and later. )
dsp: amp-tube | x -- y |
  x tanh-fast | p |
  x 0.55 f* tanh-fast 1.8181818181818181 f* | n |
  x 0.0 f< n p select fneg
;

( m c params x g -- y : one stage at 4x. )
dsp: amp-stage | m:Pole c:Pole params:AmpParams x g -- y |
  m params.miller-G  x g f*  pole-lp  amp-tube | t |
  t  c params.cpl-G t pole-lp  f-
;

( params state x -- y : the preamp stages VOICE asks for, then the stack
  and the power amp, at 4x. )
dsp: amp-core | state:AmpState params:AmpParams x -- y |
  state.m1& state.c1& params x params.g1 amp-stage | y |
  params.voice 1.5 f>
    [ state.m2& state.c2& params y params.g2 amp-stage ]
    [ y ]
  ifte | y |
  params.voice 2.5 f>
    [ state.m3& state.c3& params y params.g3 amp-stage ]
    [ y ]
  ifte | y |
  ( tone stack, TDF-II; the stack's loss is made up after it )
  params.sb0 y f* state.z1 f+ | s |
  params.sb1 y f* state.z2 f+ params.sa1 s f* f- -> state.z1
  params.sb2 y f* state.z3 f+ params.sa2 s f* f- -> state.z2
  params.sb3 y f* params.sa3 s f* f- -> state.z3
  ( power amp: sag pulls the drive down as the supply droops )
  s params.pw-g f*  1.0 params.sag-k state.env f* f+ f/ tanh-fast
;

dsp: k-amp-tick | io:Io ctx state:AmpState params:AmpParams -- |
  io.in-l | dry |
  dry  state.tight& params.tight-G dry pole-lp  f- | x |
  state.up& x up4 | a b c d |
  state.dec&
    state params a amp-core  state params b amp-core
    state params c amp-core  state params d amp-core
  dec4 params.pw-mk f* | y |
  state.env  y fabs state.env f-  params.env-a f*  f+ -> state.env
  params.pres-sh& y state.pres& shelf-hi | y |
  params.cab 0.5 f>
    [ state.hp& params.hpk& y svf-lphp nip | y |
      state.b1& params.cb1& y bell-tick | y |
      state.b2& params.cb2& y bell-tick | y |
      state.b3& params.cb3& y bell-tick | y |
      state.lp1& params.lpk& y svf-lphp drop | y |
      state.lp2& params.lp2k& y svf-lphp drop ]
    [ y ]
  ifte | y |
  state.d4 -> state.d5  state.d3 -> state.d4  state.d2 -> state.d3
  state.d1 -> state.d2  dry -> state.d1
  ( flushed below ~1e-34, so a decaying tail ends at 0, not denormals )
  y params.wet f*  state.d5 params.dry f*  f+  AMP-FLUSH f+ AMP-FLUSH f- -> io.out-l
;
