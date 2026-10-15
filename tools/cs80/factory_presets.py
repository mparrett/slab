#!/usr/bin/env python3
"""Write C-Beam 80's presets (machines/cs80/presets/*.preset).

The channel settings are the Yamaha CS-80 Owner's Manual: all 22 factory
preset charts (pp. 28-30) and the programming examples of §III (pp. 24-27),
read off the slider drawings at 300 dpi against each row's ticks, bottom
tick 0 and top tick 10, to half a division (docs/38-cs80.md, "Panel and
presets"). The readings are charts.json beside this script.

The CS-80 calls a sound up as one Channel I preset plus one Channel II
preset; each factory file here is such a pairing. The manual's examples go
in presets/manual/. Times convert from slider positions with the IG00152's
law, one octave of time per volt: attack 1 ms x 2^s, decay and release
10 ms x 2^s. The speed sliders are exponential over their ranges: PWM and
ring 0.2 Hz x 1000^(s/10), the sub oscillator 0.7 Hz x 86^(s/10) [our
guess at the taper]. The charts show no FEET: 8' unless a note says so.

The last presets are ours, not Yamaha's: marked "(ours)" in the note.

    python3 tools/cs80/factory_presets.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "machines", "cs80", "presets")
CHARTS = os.path.join(HERE, "charts.json")

FEET = {16: 0, 8: 1, 5.33: 2, 4: 3, 2.67: 4, 2: 5}
SUB_FN = ["sine", "saw down", "saw up", "square", "noise"]


def atk(s):
    return round(0.001 * 2 ** s, 4)


def dec(s):
    return round(0.01 * 2 ** s, 4)


def speed(s):
    """A PWM or ring SPEED slider position -> Hz."""
    return round(0.2 * 1000 ** (s / 10), 3)


def sub_speed(s):
    return round(0.7 * (60 / 0.7) ** (s / 10), 3)


def key(name):
    return re.sub(r"[^a-z0-9]+", "", name.lower())


with open(CHARTS) as f:
    _charts = json.load(f)

# One channel at its panel defaults: nothing sounding but a plain saw.
BLANK = dict(feet=8, pwm_spd=6.0, pwm=0, pw=0, sqr=0, saw=1, noise=0,
             hpf=0, res_h=0, lpf=10, res_l=0, il=0, al=0, f_a=0, f_d=0, f_r=0,
             vcf_lvl=9, sine=0, a_a=0, a_d=10, a_s=10, a_r=1, level=9,
             i_bril=0, i_lvl=0, a_bril=0, a_lvl=0)


def panel(fields):
    """A chart's channel fields -> this script's channel dict."""
    c = dict(fields)
    c["pwm_spd"] = speed(c["pwm_spd"])
    c["feet"] = 8
    return c


# Channel presets from the charts, in slider positions 0..10, keyed
# string1, brass2, epiano, harpsichord1, funky3 ...
CH = {k: panel(v["fields"]) for k, v in _charts["presets"].items()}

GLOBAL = dict(sub_fn=0, sub_spd=5.5, sub_vco=0, sub_vcf=0, sub_vca=0,
              tr_pitch=0, tr_speed=0, tr_vco=0, tr_vcf=0,
              kb_bl=0, kb_bh=0, kb_ll=0, kb_lh=0,
              ring_spd=6.7, ring_mod=0, ring_depth=0, ring_a=0.03, ring_d=0.5,
              cho_mode=0, cho_spd=4, cho_depth=5,
              mix=5, bril=0, reso=0, vol=0.7, pitch=0, detune=0,
              porta=0, porta_t=0.01, sus_mode=0, sus_t=2.0, age=0.5)


# Each preset's note peak at VOLUME 0.7, measured on the bench; preset()
# trims VOLUME so a note peaks near -10 dBFS (VOLUME stays 0.2..1).
PEAK = {
    "bass": -10.0,
    "brass": -10.3,
    "brass-3": -9.9,
    "clavichord": -17.6,
    "e-piano": -14.0,
    "flute": -8.9,
    "funky": -12.1,
    "funky-2": -4.9,
    "guitar": -10.8,
    "harpsichord": -12.5,
    "manual/bells-gongs": -25.7,
    "manual/clarinet": -13.5,
    "manual/clavichord": -23.0,
    "manual/flute": -21.8,
    "manual/multiple-strings": -24.2,
    "manual/oboe": -19.9,
    "manual/pizzicato-legato": -14.8,
    "manual/solo-violin": -21.6,
    "manual/timpani": -15.8,
    "manual/trumpet": -13.9,
    "organ": -5.1,
    "rain-brass": -4.5,
    "ring-bells": -12.0,
    "solo-lead": -6.5,
    "strings": -8.2,
    "strings-2": -10.1,
    "tears-pad": -16.1,
}


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
    if name in PEAK:
        g["vol"] = round(max(0.2, min(1.0, 0.7 * 10 ** ((-10.0 - PEAK[name]) / 20))), 3)
    params = {}
    params.update(channel(1, ch1))
    params.update(channel(2, ch2))
    for k, v in g.items():
        params["cb-" + k.replace("_", "-")] = v
    doc = {"slab": "preset", "schema": 1, "machine": "cs80", "note": note, "params": params}
    path = os.path.join(OUT, name + ".preset")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(doc, f)
        f.write("\n")


def ch(name, **over):
    c = dict(CH[name])
    c.update(over)
    return c


def example_globals(g):
    """A §III diagram's levers -> C-Beam's global controls.  Centre-detent
    levers read 5 at the centre."""
    sub = g["sub_osc"]
    tr = g["touch_response"]
    ring = g["ring_mod"]
    cho = g.get("chorus_tremolo", "off")
    return dict(
        sub_fn=SUB_FN.index(sub["function"]), sub_spd=sub_speed(sub["speed"]),
        sub_vco=sub["vco"], sub_vcf=sub["vcf"], sub_vca=sub["vca"],
        tr_pitch=tr["initial_pitchbend"], tr_speed=tr["after_sub_osc_speed"],
        tr_vco=tr["after_sub_osc_vco"], tr_vcf=tr["after_sub_osc_vcf"],
        kb_bl=g["kbd_bril_low"] - 5, kb_bh=g["kbd_bril_high"] - 5,
        kb_ll=g["kbd_level_low"] - 5, kb_lh=g["kbd_level_high"] - 5,
        ring_spd=speed(ring["speed"]), ring_mod=ring["modulation"], ring_depth=ring["depth"],
        ring_a=atk(ring["attack"]), ring_d=dec(ring["decay"]),
        cho_mode=0 if cho == "off" else 1, cho_spd=3, cho_depth=4,
        mix=g["mix"], bril=g["brilliance"] - 5, reso=g["resonance"],
        detune=round((g["detune_ch2"] - 5) / 5, 2),
    )


def main():
    os.makedirs(OUT, exist_ok=True)
    # Yamaha's pairings: one Channel I and one Channel II preset.
    preset("brass", "BRASS 1 + BRASS 2: IL and AL both up, the swell from pressure",
           ch("brass1"), ch("brass2"))
    preset("brass-3", "BRASS 1 + BRASS 3: shorter, a resonant cornet edge",
           ch("brass1"), ch("brass3"))
    preset("strings", "STRING 1 + STRING 2: band-passed resonant saws, pressure swells",
           ch("string1"), ch("string2"))
    preset("strings-2", "STRING 3 + STRING 4: slow open saws, after touch brings the level",
           ch("string3"), ch("string4"))
    preset("flute", "FLUTE alone: a saw through a full-resonance LPF",
           ch("flute"), ch("flute"), mix=0)
    preset("e-piano", "E. PIANO alone: a square, IL and AL with no sustain on the filter",
           ch("epiano"), ch("epiano"), mix=0)
    preset("bass", "BASS alone: square and saw at 16', the resonant pluck, both filters ringing",
           ch("bass", feet=16), ch("bass", feet=16), mix=10)
    preset("clavichord", "CLAVICHORD 1 + CLAVICHORD 2: narrow pulses, a plucked band",
           ch("clavichord1"), ch("clavichord2"))
    preset("harpsichord", "HARPSICHORD 1 + HARPSICHORD 2: narrow pulses through a band",
           ch("harpsichord1"), ch("harpsichord2"))
    preset("organ", "ORGAN 1 + ORGAN 2: gated, unfiltered, the two channels' footages",
           ch("organ1"), ch("organ2"))
    preset("guitar", "GUITAR 1 + GUITAR 2: a plucked pulse and its resonant band",
           ch("guitar1"), ch("guitar2"))
    preset("funky", "FUNKY 1 + FUNKY 2: the CS-80's envelope-swept funk",
           ch("funky1"), ch("funky2"))
    preset("funky-2", "FUNKY 3 + FUNKY 4: the other funk pairing",
           ch("funky3"), ch("funky4"))
    # The Owner's Manual §III: Yamaha's own programming examples.
    for ex in _charts["examples"]:
        g = example_globals(ex["global"])
        # a one-channel example fills both panels; MIX picks the one heard
        c1 = panel(ex["ch1"] or ex["ch2"])
        c2 = panel(ex["ch2"] or ex["ch1"])
        c1["feet"] = float(ex["global"]["feet_I"]) if ex["global"]["feet_I"] != "8" else 8
        c2["feet"] = float(ex["global"]["feet_II"]) if ex["global"]["feet_II"] != "8" else 8
        c1["feet"] = int(c1["feet"]) if c1["feet"] in (16, 8, 4, 2) else c1["feet"]
        c2["feet"] = int(c2["feet"]) if c2["feet"] in (16, 8, 4, 2) else c2["feet"]
        name = "manual/" + re.sub(r"[^a-z0-9]+", "-", ex["name"].lower()).strip("-")
        where = {"I": "Channel I", "II": "Channel II", "both": "both channels"}[ex["channel"]]
        preset(name, f'Owner\'s Manual §III, {ex["name"].upper()}: {where}', c1, c2, **g)
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
