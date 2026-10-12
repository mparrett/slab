( resonator.fy - eight parallel damped complex modes per channel.
  A mode's pole radius is exp[-ln[1000]/[sr*T60]]. Rotation gives
  pitch independently of damping; higher modes decay faster with DAMP.
  Mode weights and resonant peak gains are normalized before summation.
  All state is fixed-size; modes above 0.45 sr are omitted, not folded. )
include "../00-primitives/ctx.fy"
include "../00-primitives/math.fy"

ustruct: RsMode f64 re f64 im ;
ustruct: RsCoef f64 c f64 s f64 inject f64 weight ;
ustruct: RsChan
  RsMode m0 RsMode m1 RsMode m2 RsMode m3
  RsMode m4 RsMode m5 RsMode m6 RsMode m7
;
ustruct: ResonatorState RsChan l RsChan r ;
ustruct: ResonatorParams
  f64 hz f64 material f64 decay f64 damp f64 inharm f64 spread
  f64 drive f64 mix f64 out
  RsCoef c0 RsCoef c1 RsCoef c2 RsCoef c3
  RsCoef c4 RsCoef c5 RsCoef c6 RsCoef c7
  f64 excite f64 gain f64 norm
;

dsp: rs-coef | c:RsCoef p:ResonatorParams sr i ratio -- |
  p.hz ratio f* 1.0 p.inharm i i f* f* 0.015 f* f+ f* | f |
  p.decay 1.0 p.damp i f* 0.7 f* f+ f/ | t60 |
  -6.907755278982137 sr t60 f* f/ exp | r |
  f sr 0.45 f* f< mask>f | on |
  f sr 0.45 f* fmin 6.283185307179586 f* sr f/ | a |
  a cos r f* -> c.c  a sin r f* -> c.s
  1.0 r f- 2.0 f* on f* -> c.inject
  1.0 ratio fsqrt f/ on f* 0.25 f* -> c.weight
;

dsp: rs-weight | c:RsCoef -- w | c.weight ;

dsp: resonator-block-prepare | ctx:Ctx state p:ResonatorParams -- |
  p.material 0.5 f< | harmonic |
  p.material 1.5 f> | pipe |
  ( Plate ratios follow an inharmonic series; PIPE uses odd harmonics. )
  p.c0& p ctx.sr 0.0 1.0 rs-coef
  p.c1& p ctx.sr 1.0 harmonic 2.0 pipe 3.0 1.593 select select rs-coef
  p.c2& p ctx.sr 2.0 harmonic 3.0 pipe 5.0 2.136 select select rs-coef
  p.c3& p ctx.sr 3.0 harmonic 4.0 pipe 7.0 2.296 select select rs-coef
  p.c4& p ctx.sr 4.0 harmonic 5.0 pipe 9.0 2.653 select select rs-coef
  p.c5& p ctx.sr 5.0 harmonic 6.0 pipe 11.0 2.918 select select rs-coef
  p.c6& p ctx.sr 6.0 harmonic 7.0 pipe 13.0 3.598 select select rs-coef
  p.c7& p ctx.sr 7.0 harmonic 8.0 pipe 15.0 4.101 select select rs-coef
  1.0 p.c0& rs-weight p.c1& rs-weight f+ p.c2& rs-weight f+
    p.c3& rs-weight f+ p.c4& rs-weight f+ p.c5& rs-weight f+
    p.c6& rs-weight f+ p.c7& rs-weight f+ 0.000001 fmax f/ -> p.norm
  p.drive db>lin -> p.excite  p.out db>lin -> p.gain
;

dsp: rs-mode | s:RsMode c:RsCoef x sign spread -- y |
  ( Stereo detune as a small extra rotation of the pole, in radians. )
  c.c sign spread f* c.s f* f- | rc |
  c.s sign spread f* c.c f* f+ | rs |
  ( Normalize this first-order rotation so detuning cannot increase radius. )
  1.0 spread spread f* f+ fsqrt | norm |
  rc norm f/ | rc |  rs norm f/ | rs |
  s.re rc f* s.im rs f* f- x c.inject f* f+ | re |
  s.im rc f* s.re rs f* f+ | im |
  re -> s.re  im -> s.im
  re c.weight f*
;

dsp: rs-channel | s:RsChan p:ResonatorParams x sign spread -- y |
  x p.excite f* tanh-fast | excite |
  s.m0& p.c0& excite sign spread rs-mode
  s.m1& p.c1& excite sign spread rs-mode f+
  s.m2& p.c2& excite sign spread rs-mode f+
  s.m3& p.c3& excite sign spread rs-mode f+
  s.m4& p.c4& excite sign spread rs-mode f+
  s.m5& p.c5& excite sign spread rs-mode f+
  s.m6& p.c6& excite sign spread rs-mode f+
  s.m7& p.c7& excite sign spread rs-mode f+ | wet |
  x 1.0 p.mix f- f* wet p.norm f* p.mix f* f+ p.gain f*
;

dsp: k-resonator-tick | io:Io ctx:Ctx s:ResonatorState p:ResonatorParams -- |
  p.spread 6.283185307179586 f* ctx.sr f/ | spread |
  s.l& p io.in-l -1.0 spread rs-channel -> io.out-l
  s.r& p io.in-r 1.0 spread rs-channel -> io.out-r
;
