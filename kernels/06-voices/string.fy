( string.fy — plucked-string voice: a digital waveguide [Karplus-Strong as
  Jaffe and Smith extended it], tuned for electric bass.

  One delay loop per voice holds the traveling velocity wave.  Each sample:

    ring read at w - D [Lagrange, 4 taps]
      -> loss shelf [decay per partial]
      -> 16 dispersion allpasses [stiffness: upper partials run sharp]
      -> optional fret-buzz soft limit
      -> + excitation  -> ring write at w

    loop signal - itself pickup-pos periods ago [pickup comb]
      -> pickup resonance [2-pole LP] -> out

  What makes it sound like a string rather than a pluck-and-fade toy.
  Each was fitted against a sampled roundwound bass [Karoryfer
  fashionbass, neck pickup, DI] with tools/fit/string_fit.py:

    * DECAY sets the T60 of the low partials, HF DEC the T60 of those
      above KNEE [a harmonic number].  See string-tune.
    * STIFF is the inharmonicity B at D1 [x 1e-4], key-tracked as
      1/sqrt f; the measured bass is about 3.6 at D1 and 2.2 at D3.  The
      tuning subtracts the loss shelf's and the allpasses' phase delay at
      f0, so notes measure within a few cents.
    * HAND picks the string a note is played on [st-fret], which moves the
      pluck and pickup points along the vibrating length.
    * The excitation is a smooth velocity pulse, the finger's push and
      release, minus itself one pluck delay later.  Measured finger plucks
      [neck pickup, DI] look like this: a smooth bump a few ms wide, and an
      attack spectrum near flat to the 12th harmonic with notches at
      multiples of 1/POS.  SOFT is the pulse width.  SHAPE crossfades to a
      smoothed velocity STEP instead [a rectangle as long as the pluck
      point's share of the period, the ideal plucked string, 1/n]: a
      pick's or a pop's harder, rounder push.
    * The pickup sees the wave at its own point: a second comb [PICKUP
      POS], which also removes the loop's DC.
    * THUMP: tension modulation.  The loop shortens with displacement
      squared [the velocity follower over f], so a hard pluck starts sharp
      and settles as it decays.  At 0.5 it matches the measured bass: a
      hard low D starts ~50 cents sharp, a D3 ~7.
    * BUZZ: the loop runs through a soft limit, the string rattling on the
      frets when it swings wide; it bites only on loud notes.

  A note-on mutes the old note's content: for one loop length the
  feedback is masked, so the ring refills with the new excitation, while
  the old read fades out on the output over 64 samples.

  Polyphony: the ring is a host buffer per voice [manifest `buffer`], so
  every voice owns its own string.  Voices ACCUMULATE into io.out-l. )

include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"
include "../00-primitives/rand.fy"
include "../04-filters/coeffs.fy"
include "../04-filters/tpt_svf.fy"

ustruct: StringState
  f64 buf       ( host ring base pointer )
  f64 buf-len   ( host ring cells )
  f64 w         ( write index )
  f64 dl        ( loop delay in samples, gliding to dl-tgt )
  f64 dl-tgt
  f64 hz
  f64 vel
  f64 age       ( samples since note-on )
  f64 gate      ( 1 held, 0 released )
  f64 clear-n   ( feedback masked while age < clear-n )
  f64 g-hi      ( loss shelf: per-period gain above the knee )
  f64 g-dif     ( gain below the knee minus g-hi )
  f64 g-rel     ( flat per-period gain once released )
  f64 la        ( loss shelf one-pole coefficient )
  f64 lp1
  f64 apc       ( dispersion allpass coefficient )
  f64 apx 16    ( dispersion allpass states )
  f64 apy 16
  f64 amp       ( excitation level from velocity )
  f64 inv-w     ( 1 / excitation width in samples )
  f64 pu-g      ( pulse level: narrow pulses carry less energy )
  f64 pd        ( pluck comb delay, samples )
  f64 pk        ( pickup comb delay, samples )
  f64 nz-env
  f64 nz-k
  f64 rng
  f64 tens      ( amplitude follower for THUMP )
  f64 th-k      ( THUMP: delay shortening per tens^2, this note )
  f64 s1  f64 s2  ( pickup resonance )
;

ustruct: StringParams
  ( user-facing )
  f64 decay      ( s: T60 of the low partials at E1, key-tracked )
  f64 hf-decay   ( s: T60 of the partials above the knee at E1 )
  f64 knee       ( harmonic where the decay turns from DECAY to HF DEC )
  f64 stiff      ( inharmonicity B at D1, x 1e-4 )
  f64 release    ( s: T60 once the note is released [finger mute] )
  f64 pos        ( pluck point, fraction of the open string from the bridge )
  f64 soft       ( ms: excitation rise time at mid velocity )
  f64 shape      ( 0 pulse [finger] .. 1 step [pick, pop] )
  f64 noise      ( finger noise into the string )
  f64 pickup     ( pickup point, fraction of the open string from the bridge )
  f64 hand       ( fretting-hand position, fret 0..12: picks the string )
  f64 tone       ( Hz: pickup resonance )
  f64 res        ( pickup resonance peak 0..1 )
  f64 thump      ( tension modulation 0..1 )
  f64 buzz       ( fret buzz 0..1 )
  f64 level
  ( derived — string-block-prepare )
  f64 sr
  f64 inv-sr
  f64 pk-g
  f64 pk-d
  f64 tens-a
;

( |x| <= 1: atan to ~1e-5 rad, enough for phase-delay tuning. )
dsp: st-atan-small | x -- y |
  x x f* | z |
  z -0.0117212 f* 0.05265332 f+ z f* -0.11643287 f+ z f* 0.19354346 f+
    z f* -0.33262347 f+ z f* 0.99997726 f+ x f*
;

dsp: st-atan | x -- y |
  x fabs 1.0 f> | big |
  big  1.0 x f/  x  select  st-atan-small | r |
  big
    x 0.0 f< -1.5707963267948966 1.5707963267948966 select r f-
    r
  select
;

dsp: string-block-prepare | ctx:Ctx state params:StringParams |
  ctx.sr | sr |
  sr -> params.sr
  1.0 sr f/ -> params.inv-sr
  params.tone sr svf-g -> params.pk-g
  ( d 0.7 [flat] down to 0.12 [Q ~4] )
  0.7 params.res 0.64 f* f- -> params.pk-d
  ( THUMP follower: ~8 ms )
  sr 20.0 svf-dc-coeff -> params.tens-a
;

( hz hand -- ratio : how much shorter than open the vibrating string is.
  The note goes on the highest string [E1 A1 D2 G2] where it sits at or
  above the hand's fret; below that, the E string.  Pickup and pluck sit
  at fixed distances from the bridge, so their share of the vibrating
  length grows by this ratio up the neck: the 12th fret puts the neck
  pickup a third of the way along, and the tone changes string to string
  the way it does on a bass. )
dsp: st-fret | hz hand -- ratio |
  hand 0.08333333333333333 f* exp2 | h |
  hz 41.2 f/
  hz 55.0 h f* f>=  hz 55.0 f/  rot select
  hz 73.42 h f* f>=  hz 73.42 f/  rot select
  hz 98.0 h f* f>=  hz 98.0 f/  rot select
  1.0 fmax
;

( Per-note loop coefficients from hz and the knobs.  Runs at note-on, on
  note-expr, and every 64 samples [control!] so the knobs act live.

  Loss is a first-order shelf, y = g-hi x + g-dif LP[x], LP a one-pole at
  KNEE x f0: partials below it lose DECAY's share per period, partials
  above HF DEC's.  Measured basses [tools/fit/string_fit.py] turn from
  slow to fast decay around the 5th-8th harmonic at any pitch, which a
  plain one-pole in the loop [loss rising as f^2] can't follow.  The
  shelf is normalized so the fundamental's per-period gain is exact.

  Dispersion: AP-N first-order allpasses, all at c = -r.  At low w each
  section's phase delay falls as g0 r w^2 / [3 [1-r]^2], and a stiff
  string needs N B n^2 / 2 less delay at its n-th partial; both go as
  w^2, so r solves r[1+r] / [1-r]^3 = 3 B N^3 / [8 pi^2 AP-N], exact in
  the low partials and saturating above w ~ [1-r] / sqrt r. )
:: THUMP-K 10.0 ;
:: AP-N 16 ;
:: AP-NF 16.0 ;
dsp: string-tune | state:StringState params:StringParams -- |
  params.sr | sr |
  state.hz 20.0 4000.0 fclamp | hz |
  sr hz f/ | n |
  6.283185307179586 hz f* sr f/ | w0 |
  w0 cos | cw |  w0 sin | sw |
  ( per-period gains: low partials, upper partials, released )
  params.decay | t0 |
  -6.907755278982137 t0 hz f* f/ exp | glo |
  params.hf-decay  41.2 hz f/ log2 0.75 f* exp2  f*  t0 fmin | t1 |
  -6.907755278982137 t1 hz f* f/ exp | ghi |
  -6.907755278982137 params.release hz f* f/ exp | grel |
  -6.283185307179586 params.knee f* hz f* sr f/ exp 0.0 0.9999 fclamp | a |
  ( the shelf at w0: H = ghi + [glo - ghi] [1-a] / [1 - a e^-jw] )
  1.0 a cw f* f- | dr |  a sw f* | di |
  dr dr f* di di f* f+ | den |
  glo ghi f- 1.0 a f- f* den f/ | k |
  ghi k dr f* f+ | re |
  k di f* | im |
  glo  re re f* im im f* f+ fsqrt  f/ | norm |
  ghi norm f* 0.99999 fmin -> state.g-hi
  glo ghi f- norm f* -> state.g-dif
  grel -> state.g-rel
  a -> state.la
  im re f/ st-atan w0 f/ | pdl |
  ( dispersion coefficient from B, key-tracked like a real set of strings )
  params.stiff 0.0001 f*  36.71 hz f/ fsqrt  f* | b |
  3.0 b f* n f* n f* n f*  78.95683520871486 AP-NF f* f/ 0.000000001 fmax | kk |
  2.0 kk f/ log2 0.3333333333333333 f* exp2 0.001 1.0 fclamp
  8 [ | u |  1.0 u f- 2.0 u f- f* kk f/ log2 0.3333333333333333 f* exp2 0.001 1.0 fclamp ] times
  | u |
  ( keep the chain's delay under 60% of the period so the line stays long )
  0.6 n f* AP-NF f/ 1.0 fmax | q |
  1.0 u f-  0.0  q 1.0 f- q 1.0 f+ f/ 0.97 fmin  fclamp fneg | ac |
  ac -> state.apc
  1.0  ac sw f*  1.0 ac cw f* f+  f/ st-atan 2.0 f* w0 f/  f- | pda |
  n pdl f- pda AP-NF f* f-  4.0  state.buf-len 16.0 f-  fclamp -> state.dl-tgt
  params.pickup hz params.hand st-fret f* 0.5 fmin n f* 1.0 fmax -> state.pk
  ( THUMP: pitch rises with displacement squared, velocity / f )
  41.2 hz f/ dup f*  params.thump f* THUMP-K f* -> state.th-k
;

dsp: string-note-on | ctx:Ctx state:StringState params:StringParams -- |
  ctx.hz -> state.hz
  ctx.vel -> state.vel
  0.0 -> state.age
  1.0 -> state.gate
  state params string-tune
  state.dl-tgt -> state.dl
  state.dl-tgt 2.0 f+ -> state.clear-n
  0.0 -> state.lp1
  state.apx& | xs |  state.apy& | ys |
  0.0 AP-N [ | i |  0.0 xs i f!i  0.0 ys i f!i  i 1.0 f+ ] times drop
  0.0 -> state.tens
  ctx.vel 0.0001 1.0 fclamp log2 1.3 f* exp2 -> state.amp
  ( width: soft at low velocity, sharp at high )
  params.soft 0.001 f* params.sr f*  41.2 ctx.hz 20.0 4000.0 fclamp f/ fsqrt f*
    1.4 ctx.vel 0.8 f* f-  f*  1.0 fmax | wid |
  1.0 wid f/ -> state.inv-w
  2.0 params.soft f/ fsqrt 0.5 4.0 fclamp -> state.pu-g
  ctx.hz 20.0 4000.0 fclamp | hz |
  params.pos hz params.hand st-fret f* 0.5 fmin  params.sr hz f/ f* -> state.pd
  1.0 -> state.nz-env
  -1.0  0.002 wid params.inv-sr f* f+  params.sr f*  f/ exp -> state.nz-k
  state.rng& ctx.chan 3.0 f+ rand-seed-once
;

dsp: string-note-off | ctx state:StringState params -- |
  0.0 -> state.gate
;

dsp: string-note-expr | ctx:Ctx state:StringState params:StringParams -- |
  ctx.hz -> state.hz
  state params string-tune
;

dsp: string-control | ctx state:StringState params:StringParams -- |
  state params string-tune
;

( buf len pos -- y : 4-tap Lagrange read at fractional ring index pos. )
dsp: st-read | buf len pos -- y |
  pos floor | i |  pos i f- | d |
  1.0 len f/ | il |
  buf  i 1.0 f- dup il f* floor len f* f-  f@i | xm |
  buf  i dup il f* floor len f* f-  f@i | x0 |
  buf  i 1.0 f+ dup il f* floor len f* f-  f@i | x1 |
  buf  i 2.0 f+ dup il f* floor len f* f-  f@i | x2 |
  d 1.0 f- | dm1 |  d 2.0 f- | dm2 |  d 1.0 f+ | dp1 |
  d dm1 f* dm2 f* -0.16666666666666666 f* xm f*
  dp1 dm1 f* dm2 f* 0.5 f* x0 f*  f+
  dp1 d f* dm2 f* -0.5 f* x1 f*  f+
  dp1 d f* dm1 f* 0.16666666666666666 f* x2 f*  f+
;

( Smoothed step 0 -> 1 over the width, and a raised-cosine pulse, at
  sample x of the excitation [x < 0: not started]. )
dsp: st-step | x iw -- s |  x iw f* 0.0 1.0 fclamp cospi -0.5 f* 0.5 f+ ;
dsp: st-pulse | x iw -- s |  x iw f* 0.0 1.0 fclamp 2.0 f* cospi -0.5 f* 0.5 f+ ;

dsp: string-excite | state:StringState params:StringParams -- e |
  state.age | t |  t state.pd f- | td |  state.inv-w | iw |
  t iw st-step  td iw st-step f- | pl |
  t iw st-pulse td iw st-pulse f- state.pu-g f* | pu |
  pl pu f- params.shape f* pu f+  state.amp f*
  state.rng& rand-b state.nz-env f* params.noise f* state.amp f*  f+
  state.nz-env state.nz-k f* -> state.nz-env
;

dsp: k-string-voice | io:Io ctx state:StringState params:StringParams -- |
  state.buf& p@64 | buf |  state.buf-len 4.0 f- | len |
  state.age | t |
  t state.clear-n f>= | live |
  ( loop delay: glide toward the target, shortened by tension )
  state.dl  state.dl-tgt state.dl f- 0.002 f* f+ | dl |
  dl -> state.dl
  dl  1.0 state.tens state.tens f* state.th-k f* 0.1 fmin f-  f* | d |
  state.w | w |
  buf len  w d f- len f+  st-read | r |
  live r 0.0 select | rr |
  ( loss )
  state.la | a |
  state.gate 0.5 f> | held |
  held state.g-hi state.g-rel select | gh |
  held state.g-dif 0.0 select | gd |
  1.0 a f- rr f*  a state.lp1 f* f+ | s |
  s -> state.lp1
  rr gh f*  s gd f* f+ | lp |
  ( dispersion )
  state.apc | c |  state.apx& | xs |  state.apy& | ys |
  lp 0.0 AP-N [ | x i |
    xs i f@i | x1 |  ys i f@i | y1 |
    c x f* x1 f+ c y1 f* f- | y |
    x xs i f!i  y ys i f!i
    y i 1.0 f+
  ] times drop | y |
  params.buzz 0.0 f>
    [ y 3.0 f* tanh-fast 0.3333333333333333 f* y f- params.buzz f* y f+ ]
    [ y ]
  ifte | y |
  state params string-excite | e |
  y e f+ | nw |
  nw buf w f!i
  w 1.0 f+ dup len f>= 0.0 rot select -> state.w
  state.tens  nw fabs state.tens f- params.tens-a f* f+ -> state.tens
  ( pickup comb, linear tap )
  w state.pk f- len f+ | pp |
  pp floor | pi |  pp pi f- | pf |
  buf  pi dup len f>= len 0.0 select f-  f@i | p0 |
  buf  pi 1.0 f+ dup len f>= len 0.0 select f-  f@i | p1 |
  nw  p1 p0 f- pf f* p0 f+  f-
  ( old note fading out while the ring refills )
  r  1.0 t 0.015625 f* f- 0.0 fmax f*  live 0.0 rot select  f+ | o |
  state.s1& state.s2& o params.pk-g params.pk-d tpt-svf-lp-step | out |
  io.out-l  out params.level f* 2.25 f* f+ -> io.out-l
  t 1.0 f+ -> state.age
;
