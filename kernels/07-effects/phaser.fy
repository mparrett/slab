( phaser.fy - stereo 4/6/12-stage swept allpass phaser.
  Moog MF-103/S and MXR Phase 90/95 are control/topology references,
  not circuit models. All DSP here is original fy.
  Normalized lattice sections conserve energy even as coefficients move.
  Feedback is solved algebraically at each sample, with no extra delay.
  All twelve sections stay warm; stage selection crossfades their taps. )
include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"

ustruct: PhChan f64 z 12 ;
ustruct: PhaserState
  PhChan l PhChan r
  f64 ready f64 phase f64 beat
  f64 center f64 depth f64 spread f64 feedback f64 mix f64 gain
  f64 drive f64 rate f64 w4 f64 w6 f64 polarity
;
ustruct: PhaserParams
  f64 stages f64 hz f64 depth f64 feedback f64 rate f64 sync f64 div
  f64 shape f64 spread f64 drive f64 mode f64 mix f64 out
  f64 center f64 gain f64 excite f64 alpha f64 beat-inc
  f64 w4 f64 w6 f64 polarity f64 max-log
;

dsp: ph-approach | v target alpha -- y |
  target v f- | d |
  d fabs 1.0e-10 f< target v d alpha f* f+ select
;

dsp: phaser-block-prepare | ctx:Ctx s:PhaserState p:PhaserParams -- |
  p.hz log2 -> p.center
  p.out fabs 0.00001 f< 1.0 p.out db>lin select -> p.gain
  p.drive db>lin -> p.excite
  1.0 -100.0 ctx.sr f/ exp f- -> p.alpha
  ctx.tempo 20.0 999.0 fclamp 60.0 f/ ctx.sr f/ -> p.beat-inc
  ctx.beat -> s.beat
  p.stages 0.5 f< mask>f -> p.w4
  p.stages 0.5 f> p.stages 1.5 f< and mask>f -> p.w6
  p.mode 0.5 f< 1.0 -1.0 select -> p.polarity
  ctx.sr 0.45 f* log2 -> p.max-log
;

dsp: ph-controls | s:PhaserState p:PhaserParams -- |
  ( The host also prepares during reset, before pending control snapshots
    land. Seed at the first audio sample, after those snapshots arrive. )
  s.ready 0.5 f< | init |
  init p.center s.center select -> s.center
  init p.depth s.depth select -> s.depth
  init p.spread s.spread select -> s.spread
  init p.feedback s.feedback select -> s.feedback
  init p.mix s.mix select -> s.mix
  init p.gain s.gain select -> s.gain
  init p.excite s.drive select -> s.drive
  init p.rate s.rate select -> s.rate
  init p.w4 s.w4 select -> s.w4
  init p.w6 s.w6 select -> s.w6
  init p.polarity s.polarity select -> s.polarity
  1.0 -> s.ready
  s.center p.center p.alpha ph-approach -> s.center
  s.depth p.depth p.alpha ph-approach -> s.depth
  s.spread p.spread p.alpha ph-approach -> s.spread
  s.feedback p.feedback p.alpha ph-approach -> s.feedback
  s.mix p.mix p.alpha ph-approach -> s.mix
  s.gain p.gain p.alpha ph-approach -> s.gain
  s.drive p.excite p.alpha ph-approach -> s.drive
  s.rate p.rate p.alpha ph-approach -> s.rate
  s.w4 p.w4 p.alpha ph-approach -> s.w4
  s.w6 p.w6 p.alpha ph-approach -> s.w6
  s.polarity p.polarity p.alpha ph-approach -> s.polarity
;

( Output of each tap for zero current input, with the old lattice state. )
dsp: ph-affine | s:PhChan a b -- b4 b6 b12 |
  s.z& | z |
  0.0 0.0 4 [ | i y | i 1.0 f+ y a f* z i f@i b f* f+ ] times | i y4 |
  i y4 2 [ | i y | i 1.0 f+ y a f* z i f@i b f* f+ ] times | i y6 |
  i y6 6 [ | i y | i 1.0 f+ y a f* z i f@i b f* f+ ] times | i y12 |
  y4 y6 y12
;

dsp: ph-step | z i x a b -- y |
  z i f@i | old |
  x a f* old b f* f+ | y |
  x b f* old a f* f- | next |
  ( Flush inaudible tails long before they become denormals. )
  next fabs 1.0e-24 f< 0.0 next select z i f!i
  y
;

dsp: ph-cascade | s:PhChan a b x -- y4 y6 y12 |
  s.z& | z |
  0.0 x 4 [ | i y | i 1.0 f+ z i y a b ph-step ] times | i y4 |
  i y4 2 [ | i y | i 1.0 f+ z i y a b ph-step ] times | i y6 |
  i y6 6 [ | i y | i 1.0 f+ z i y a b ph-step ] times | i y12 |
  y4 y6 y12
;

dsp: ph-wave | phase shape -- wave |
  phase ffrac | ph |
  shape 0.5 f< ph sin2pi ph 0.5 f- fabs 4.0 f* 1.0 f- select
;

dsp: ph-channel | c:PhChan s:PhaserState p:PhaserParams x phase sr -- y |
  phase p.shape ph-wave s.depth f* s.center f+
    4.321928094887363 p.max-log fclamp exp2 | hz |
  hz 3.141592653589793 f* sr f/ tan-warp | g |
  1.0 g f+ | den |
  g 1.0 f- den f/ | a |
  2.0 g fsqrt f* den f/ | b |
  a a f* | a2 | a2 a2 f* | a4 | a4 a2 f* | a6 | a6 a6 f* | a12 |
  1.0 s.w4 f- s.w6 f- | w12 |
  a4 s.w4 f* a6 s.w6 f* f+ a12 w12 f* f+ | aa |
  c a b ph-affine | b4 b6 b12 |
  b4 s.w4 f* b6 s.w6 f* f+ b12 w12 f* f+ | bb |
  ( DRIVE has unity small-signal gain; 0 dB is exactly linear. )
  s.drive 1.00001 f< x x s.drive f* tanh-fast s.drive f/ select | driven |
  driven s.feedback bb f* f+ 1.0 s.feedback aa f* f- f/ | u |
  c a b u ph-cascade | y4 y6 y12 |
  y4 s.w4 f* y6 s.w6 f* f+ y12 w12 f* f+ | wet |
  ( Dry and allpass cancel to form notches. Resonance compensation holds
    the maximum static linear gain at unity instead of boosting peaks. )
  u wet s.polarity f* f+ 0.5 f* 1.0 s.feedback fabs f- f* | phased |
  x 1.0 s.mix f- f* phased s.mix f* f+ s.gain f*
;

dsp: k-phaser-tick | io:Io ctx:Ctx s:PhaserState p:PhaserParams -- |
  s p ph-controls
  p.sync 0.5 f< s.phase s.beat p.div f/ select | phase |
  s.l& s p io.in-l phase ctx.sr ph-channel -> io.out-l
  s.r& s p io.in-r phase s.spread 360.0 f/ f+ ctx.sr ph-channel -> io.out-r
  s.phase s.rate ctx.sr f/ f+ ffrac -> s.phase
  s.beat p.beat-inc f+ -> s.beat
;
