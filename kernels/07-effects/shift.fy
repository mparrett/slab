( shift.fy - signed single-sideband frequency shifting and ring modulation.
  The quadrature pair is eight second-order allpasses, with one sample
  delay on the second path. Coefficients are the squared poles of Olli
  Niemitalo's published design: https://yehar.com/blog/?p=368 .
  This is a frequency shift in Hz, not a pitch transposition.
  State and oscillator phase persist across blocks; no audio allocation. )

include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"
include "../04-filters/tpt_svf.fy"

ustruct: ShAp f64 x1 f64 x2 f64 y1 f64 y2 ;
ustruct: ShChan
  ShAp a0 ShAp a1 ShAp a2 ShAp a3
  ShAp b0 ShAp b1 ShAp b2 ShAp b3
  f64 b-delay f64 osc-s f64 osc-c f64 wet
  f64 lp1 f64 lp2 f64 lp3 f64 lp4 f64 dc-x f64 dc-y
;
ustruct: ShiftState ShChan l ShChan r ;
ustruct: ShiftParams
  f64 hz f64 spread f64 mode f64 feedback f64 tone f64 mix f64 out
  f64 sl f64 cl f64 sr f64 cr f64 gl f64 gr f64 gain f64 dc
;

dsp: sh-ap | s:ShAp x a -- y |
  x s.y2 f+ a f* s.x2 f- | y |
  s.x1 -> s.x2  x -> s.x1
  s.y1 -> s.y2  y -> s.y1
  y
;

dsp: sh-quadrature | s:ShChan x -- re im |
  s.a0& x 0.161758498367701 sh-ap | a |
  s.a1& a 0.733028932341490 sh-ap | a |
  s.a2& a 0.945349700329113 sh-ap | a |
  s.a3& a 0.990599156684529 sh-ap | a |
  s.b0& x 0.479400865588840 sh-ap | b |
  s.b1& b 0.876218493539310 sh-ap | b |
  s.b2& b 0.976597589508199 sh-ap | b |
  s.b3& b 0.997499255935549 sh-ap | b |
  s.b-delay | bd |  b -> s.b-delay
  a bd
;

dsp: shift-block-prepare | ctx:Ctx state:ShiftState p:ShiftParams -- |
  state.l& | l:ShChan |  state.r& | r:ShChan |
  p.hz p.spread 0.5 f* f- | fl |
  p.hz p.spread 0.5 f* f+ | fr |
  fl 6.283185307179586 f* ctx.sr f/ | al |
  fr 6.283185307179586 f* ctx.sr f/ | ar |
  al sin -> p.sl  al cos -> p.cl
  ar sin -> p.sr  ar cos -> p.cr
  ( Leave a transition band before shifted audio reaches Nyquist. )
  p.tone ctx.sr 0.45 f* fl fabs f- fmin 20.0 fmax
    3.141592653589793 f* ctx.sr f/ tan-warp -> p.gl
  p.tone ctx.sr 0.45 f* fr fabs f- fmin 20.0 fmax
    3.141592653589793 f* ctx.sr f/ tan-warp -> p.gr
  p.out fabs 0.00001 f< 1.0 p.out db>lin select -> p.gain
  -125.66370614359172 ctx.sr f/ exp -> p.dc
  ( Seed once, and renormalize at block boundaries to prevent drift. )
  l.osc-c l.osc-c f* l.osc-s l.osc-s f* f+ | nl |
  nl 1.0e-12 f< 1.0 l.osc-c select nl 1.0e-12 f< 1.0 nl fsqrt select f/ -> l.osc-c
  l.osc-s nl 1.0e-12 fmax fsqrt f/ -> l.osc-s
  r.osc-c r.osc-c f* r.osc-s r.osc-s f* f+ | nr |
  nr 1.0e-12 f< 1.0 r.osc-c select nr 1.0e-12 f< 1.0 nr fsqrt select f/ -> r.osc-c
  r.osc-s nr 1.0e-12 fmax fsqrt f/ -> r.osc-s
;

dsp: sh-channel | s:ShChan p:ShiftParams x sn cs g -- y |
  x s.wet p.feedback f* f+ | input |
  input s.dc-x f- p.dc s.dc-y f* f+ | dc |
  input -> s.dc-x  dc -> s.dc-y
  s.lp1& s.lp2& dc g 0.923879532511287 tpt-svf-lp-step | a |
  s.lp3& s.lp4& a g 0.38268343236509 tpt-svf-lp-step | a |
  s a sh-quadrature | re im |
  p.mode 0.5 f<
    re s.osc-c f* im s.osc-s f* f-
    a s.osc-c f*
  select | wet |
  ( Bounded feedback path; the audible wet remains linear. )
  wet tanh-fast -> s.wet
  s.osc-s cs f* s.osc-c sn f* f+ | os |
  s.osc-c cs f* s.osc-s sn f* f- | oc |
  os -> s.osc-s  oc -> s.osc-c
  x 1.0 p.mix f- f* wet p.mix f* f+ p.gain f*
;

dsp: k-shift-tick | io:Io ctx s:ShiftState p:ShiftParams -- |
  s.l& p io.in-l p.sl p.cl p.gl sh-channel -> io.out-l
  s.r& p io.in-r p.sr p.cr p.gr sh-channel -> io.out-r
;
