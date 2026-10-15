#!/usr/bin/env python3
"""Write C-Beam 80's presets (machines/cs80/presets/*.preset).

The channel settings are the Yamaha CS-80 Owner's Manual preset charts
(pp. 28-29), read off the slider drawings to about half a division
(docs/38-cs80.md, "Factory presets"). The CS-80 calls a sound up as one
Channel I preset plus one Channel II preset; each file here is such a
pairing. Times convert from slider positions with the IG00152's law, one
octave of time per volt: attack 1 ms x 2^s, decay and release 10 ms x 2^s.

The last presets are ours, not Yamaha's: marked "(ours)" in the note.

    python3 tools/cs80/factory_presets.py
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "machines", "cs80", "presets")

FEET = {16: 0, 8: 1, 5.33: 2, 4: 3, 2.67: 4, 2: 5}


def atk(s):
    return round(0.001 * 2 ** s, 4)


def dec(s):
    return round(0.01 * 2 ** s, 4)


# One channel at its panel defaults: nothing sounding but a plain saw.
BLANK = dict(feet=8, pwm_spd=6.0, pwm=0, pw=0, sqr=0, saw=1, noise=0,
             hpf=0, res_h=0, lpf=10, res_l=0, il=0, al=0, f_a=0, f_d=0, f_r=0,
             vcf_lvl=9, sine=0, a_a=0, a_d=10, a_s=10, a_r=1, level=9,
             i_bril=0, i_lvl=0, a_bril=0, a_lvl=0)

# Channel presets from the charts, in slider positions 0..10.
CH = {
    "brass1": dict(lpf=5.5, res_l=5.5, il=7, al=7, f_a=7.5, f_d=7, f_r=2,
                   vcf_lvl=9, a_a=5, a_d=10, a_s=9.5, a_r=2, level=10,
                   i_bril=2, i_lvl=9.5, a_bril=5, a_lvl=6.5),
    "brass2": dict(lpf=5.5, res_l=2, il=7.5, al=5, f_a=7.5, f_d=5.5, f_r=3,
                   vcf_lvl=9, a_a=6, a_d=5.5, a_s=7.5, a_r=1, level=9.5,
                   i_bril=3, i_lvl=0, a_bril=5.5, a_lvl=8),
    "brass3": dict(lpf=4, res_l=6.5, il=5.5, al=6.5, f_a=3.5, f_d=3.5, f_r=2,
                   vcf_lvl=9, a_a=4, a_d=5.5, a_s=5, a_r=2, level=9,
                   i_bril=2.5, i_lvl=5, a_bril=4, a_lvl=9),
    "string1": dict(hpf=3, res_h=7, lpf=5, res_l=7, il=6.5, al=5, f_a=5, f_d=3.5,
                    f_r=1.5, vcf_lvl=9.5, a_a=5, a_d=10, a_s=5, a_r=2, level=9.5,
                    i_bril=4, i_lvl=9.5),
    "string2": dict(hpf=3, lpf=9, a_a=0, a_d=10, a_s=9.5, a_r=1.5, level=9,
                    a_lvl=9.5),
    "flute": dict(lpf=4, res_l=10, a_a=6, a_d=10, a_s=10, a_r=2.5, level=9,
                  i_bril=2, i_lvl=7.5, a_bril=2, a_lvl=10),
    "epiano": dict(saw=0, sqr=1, pw=6, lpf=4, res_l=2, il=7, al=7, f_a=0, f_d=7,
                   f_r=2, a_a=0, a_d=5, a_s=5, a_r=5, level=9, i_bril=3, i_lvl=9),
    "bass": dict(feet=16, saw=0, sqr=1, pw=7.5, res_h=9, lpf=2, res_l=9, il=3,
                 al=7.5, f_a=0, f_d=4, f_r=1.5, a_a=1, a_d=7, a_s=0, a_r=1.5,
                 level=9, i_bril=7, i_lvl=3),
    "harpsi1": dict(saw=0, sqr=1, pw=6.5, hpf=4.5, res_h=2, lpf=6.5, res_l=2,
                    a_a=0, a_d=5.5, a_s=2, a_r=2, level=9),
    "harpsi2": dict(saw=0, sqr=1, pw=6, hpf=5, lpf=6, a_a=0, a_d=5.5, a_s=0,
                    a_r=2, level=9),
}

GLOBAL = dict(sub_fn=0, sub_spd=5.5, sub_vco=0, sub_vcf=0, sub_vca=0,
              tr_pitch=0, tr_speed=0, tr_vco=0, tr_vcf=0,
              kb_bl=0, kb_bh=0, kb_ll=0, kb_lh=0,
              ring_spd=6.7, ring_mod=0, ring_depth=0, ring_a=0.03, ring_d=0.5,
              cho_mode=0, cho_spd=4, cho_depth=5,
              mix=5, bril=0, reso=0, vol=0.7, pitch=0, detune=0,
              porta=0, porta_t=0.01, sus_mode=0, sus_t=2.0, age=0.5)


def channel(n, ch):
    c = dict(BLANK)
    c.update(ch)
    out = {}
    for k, v in c.items():
        if k == "feet":
            v = FEET[v]
        elif k in ("f_a", "a_a"):
            v = atk(v)
        elif k in ("f_d", "f_r", "a_d", "a_r"):
            v = dec(v)
        out[f"cb{n}-{k.replace('_', '-')}"] = v
    return out


def preset(name, note, ch1, ch2, **glob):
    g = dict(GLOBAL)
    g.update(glob)
    params = {}
    params.update(channel(1, ch1))
    params.update(channel(2, ch2))
    for k, v in g.items():
        params["cb-" + k.replace("_", "-")] = v
    doc = {"slab": "preset", "schema": 1, "machine": "cs80", "note": note, "params": params}
    with open(os.path.join(OUT, name + ".preset"), "w") as f:
        json.dump(doc, f)
        f.write("\n")


def ch(name, **over):
    c = dict(CH[name])
    c.update(over)
    return c


def main():
    os.makedirs(OUT, exist_ok=True)
    # Yamaha's pairings: one Channel I and one Channel II preset.
    preset("brass", "BRASS 1 + BRASS 2: IL and AL both up, the swell from pressure",
           ch("brass1"), ch("brass2"))
    preset("brass-3", "BRASS 1 + BRASS 3: shorter, a resonant cornet edge",
           ch("brass1"), ch("brass3"))
    preset("strings", "STRING 1 + STRING 2: band-passed resonant saws, pressure swells",
           ch("string1"), ch("string2"))
    preset("flute", "FLUTE alone: a saw through a full-resonance LPF",
           ch("flute"), ch("flute"), mix=0)
    preset("e-piano", "E. PIANO alone: a 75% pulse, IL and AL with no sustain on the filter",
           ch("epiano"), ch("epiano"), mix=0)
    preset("bass", "BASS alone: the resonant pluck, both filters ringing",
           ch("bass"), ch("bass"), mix=10)
    preset("harpsichord", "HARPSICHORD 1 + HARPSICHORD 2: narrow pulses through a band",
           ch("harpsi1"), ch("harpsi2"))
    # Ours, built from Yamaha's brass method [manual §III] and the sounds
    # it is famous for.
    preset("rain-brass", "(ours) brass after the Blade Runner end titles: two detuned "
           "BRASS 1s, pressure brings brilliance, level and vibrato. Add a long hall",
           ch("brass1", a_bril=4.5, a_lvl=8), ch("brass1", a_bril=4.5, a_lvl=8, i_lvl=6),
           detune=0.12, bril=-0.5, sub_spd=5.5, tr_vco=4)
    preset("tears-pad", "(ours) STRING 2 over a slow PWM layer, chorus on: a pad that "
           "breathes with pressure",
           ch("string2", lpf=6.5, res_l=3, a_a=7.5, a_r=7.5, a_bril=4),
           ch("string2", feet=4, lpf=5, saw=0, sqr=1, pw=3, pwm=4, pwm_spd=0.6,
              a_a=8, a_r=8, a_bril=3),
           mix=4.5, cho_mode=1, cho_spd=3, cho_depth=6, sub_vcf=1.5, sub_spd=0.9)
    preset("ring-bells", "(ours) the manual's bells: sine and saw, the ring modulator's "
           "envelope sweeping its carrier",
           ch("string2", lpf=7, sine=6, a_a=0, a_d=8, a_s=0, a_r=8, a_lvl=0),
           ch("string2", feet=2, saw=0, sqr=0, sine=8, a_a=0, a_d=7, a_s=0, a_r=7, a_lvl=0),
           ring_mod=7, ring_spd=90, ring_depth=4, ring_a=0.004, ring_d=1.2)
    preset("solo-lead", "(ours) a solo voice: portamento at the CS-80's constant rate, "
           "after touch opens the filter and adds vibrato",
           ch("brass3", res_l=7, a_bril=8, a_lvl=4), ch("brass3", feet=4, level=5, a_bril=8),
           mix=3, porta=1, porta_t=0.012, tr_vco=5, sub_spd=6.0)


if __name__ == "__main__":
    main()
