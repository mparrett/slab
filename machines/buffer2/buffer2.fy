( buffer2.fy - live capture, granular scatter and repeat/stutter. )
include "../../kernels/07-effects/buffer.fy"
include "../lib/manifest.fy"
: manifest
  "Buffer Loom" effect-block machine*
  "k-buffer-tick" render! "buffer-block-prepare" block-prepare!
  BufferState.size state-size! BufferParams.size params-size!
  600.0 panel-w! stereo
  ( A frozen capture must survive arbitrarily long gaps in input. )
  -1.0 tail!
  "capture-l" BufferState.bl BufferState.len 4.1 buffer
  "capture-r" BufferState.br BufferState.len-r 4.1 buffer
  "CAPTURE" "MODE" "buf-mode" BufferParams.mode 0.0 switch
    "GRAINS" 0.0 opt "REPEAT" 1.0 opt as-radio
  "CAPTURE" "FREEZE" "buf-freeze" BufferParams.freeze 0.0 switch
    "OFF" 0.0 opt "ON" 1.0 opt as-button
  "CAPTURE" "SPAN" "buf-span" BufferParams.span 0.05 4.0 0.5 curve-exp knob
  "CAPTURE" "POS" "buf-position" BufferParams.position 0.0 1.0 0.5 curve-lin knob
  "CAPTURE" 4 strip
  "GRAINS" "SIZE MS" "buf-grain" BufferParams.grain-ms 10.0 250.0 90.0 curve-exp knob
  "GRAINS" "DENSITY" "buf-density" BufferParams.density 1.0 32.0 12.0 curve-exp knob
  "GRAINS" "SPRAY" "buf-spray" BufferParams.spray 0.0 1.0 0.15 curve-lin knob
  "GRAINS" "JITTER" "buf-jitter" BufferParams.jitter 0.0 12.0 0.0 curve-lin knob
  "GRAINS" 4 strip
  "CLOCK" "SYNC" "buf-sync" BufferParams.sync 0.0 switch
    "FREE" 0.0 opt "SYNC" 1.0 opt
  "CLOCK" "DIV" "buf-div" BufferParams.div 1.0 switch
    "1/32" 0.125 opt "1/16" 0.25 opt "1/8" 0.5 opt "1/4" 1.0 opt
    "1/2" 2.0 opt "1 BAR" 4.0 opt as-display
  "CLOCK" "PITCH" "buf-pitch" BufferParams.pitch -24.0 24.0 0.0 curve-lin knob
  "CLOCK" "REVERSE" "buf-reverse" BufferParams.reverse 0.0 switch
    "OFF" 0.0 opt "ON" 1.0 opt as-button
  "CLOCK" 4 strip
  "OUT" "WIDTH" "buf-width" BufferParams.width 0.0 1.0 0.3 curve-lin knob
  "OUT" "FB" "buf-fb" BufferParams.feedback 0.0 0.85 0.0 curve-pow knob
  "OUT" "TONE" "buf-tone" BufferParams.tone 1000.0 20000.0 14000.0 curve-exp knob
  "OUT" "MIX" "buf-mix" BufferParams.mix 0.0 1.0 0.5 curve-lin knob
  "OUT" "LEVEL" "buf-out" BufferParams.out -24.0 12.0 0.0 curve-lin knob
  "OUT" 5 strip
  1.0 row
    1.0 cell "CAPTURE" 1.0 item
    1.0 cell "GRAINS" 1.0 item
  1.0 row
    1.0 cell "CLOCK" 1.0 item
    1.5 cell "OUT" 1.0 item
  machine-desc
;
