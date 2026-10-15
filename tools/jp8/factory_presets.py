#!/usr/bin/env python3
"""Write Juniper-8's presets (machines/jp8/presets/*.preset).

The patches are Roland's Jupiter-8 factory patch sheets, read off the
slider drawings to about half a division (docs/39-jp8.md, "Panel and
presets"). Sliders are 0..10 as on the panel; the envelope and LFO
sliders convert to seconds and hertz with an exponential pot law over the
calibrated ranges [our guess at the taper]:

    attack          1.5 ms x 4000^(s/10)    (1.5 ms .. 6 s)
    decay, release  1.5 ms x 8000^(s/10)    (1.5 ms .. 12 s)
    LFO rate        0.05 Hz x 800^(s/10)    (0.05 .. 40 Hz)
    LFO delay       0.4 s x s               (0 .. 4 s)

The last presets are ours, not Roland's: marked "(ours)" in the note.

    python3 tools/jp8/factory_presets.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "machines", "jp8", "presets")

# switch options, in panel order: a preset stores the option's index
LFO_WAVE = ["sine", "saw", "square", "random"]
VMOD_DST = ["vco1", "both", "vco2"]
RANGE1 = [16, 8, 4, 2]
WAVE1 = ["tri", "saw", "pulse", "square"]
WAVE2 = ["sine", "saw", "pulse", "noise"]
PWM_SRC = ["lfo", "man", "env1"]
ENV_SRC = ["env1", "env2"]


def atk(s):
    return round(0.0015 * 4000 ** (s / 10), 4)


def dec(s):
    return round(0.0015 * 8000 ** (s / 10), 4)


def rate(s):
    return round(0.05 * 800 ** (s / 10), 3)


# The panel at rest: VCO-1 saw at 8', the VCF open a little, organ gates.
BLANK = dict(
    lfo_rate=5, lfo_delay=0, lfo_wave="sine",
    lfo_vco=0, env_vco=0, vmod_dst="both",
    cross=0, range1=8, wave1="saw",
    range2=0, fine2=0, wave2="saw", sync=0, low2=0,
    pwm=0, pwm_src="man", mix=0, hpf=0,
    slope=24, cutoff=5, res=0, env_src="env1", env_mod=0, lfo_vcf=0, kf=5,
    vca_lfo=0, level=8,
    e1=(0, 5, 5, 3), e1_kf=0, e1_pol=0,
    e2=(0, 5, 10, 3), e2_kf=0,
    bend_vco=2, bend_vcf=0, bend_v1=1, bend_v2=1,
    porta=0, porta_t=0.15, age=0.3, vol=0.7,
)


def params(p):
    a1, d1, s1, r1 = p["e1"]
    a2, d2, s2, r2 = p["e2"]
    return {
        "jp-lfo-rate": rate(p["lfo_rate"]),
        "jp-lfo-delay": round(0.4 * p["lfo_delay"], 3),
        "jp-lfo-wave": LFO_WAVE.index(p["lfo_wave"]),
        "jp-lfo-vco": p["lfo_vco"],
        "jp-env-vco": p["env_vco"],
        "jp-vmod-dst": VMOD_DST.index(p["vmod_dst"]),
        "jp-cross": p["cross"],
        "jp-range1": RANGE1.index(p["range1"]),
        "jp-wave1": WAVE1.index(p["wave1"]),
        "jp-range2": p["range2"],
        "jp-fine2": p["fine2"],
        "jp-wave2": WAVE2.index(p["wave2"]),
        "jp-sync": p["sync"],
        "jp-low2": p["low2"],
        "jp-pwm": p["pwm"],
        "jp-pwm-src": PWM_SRC.index(p["pwm_src"]),
        "jp-mix": p["mix"],
        "jp-hpf": p["hpf"],
        "jp-slope": 0 if p["slope"] == 24 else 1,
        "jp-cutoff": p["cutoff"],
        "jp-res": p["res"],
        "jp-env-src": ENV_SRC.index(p["env_src"]),
        "jp-env-mod": p["env_mod"],
        "jp-lfo-vcf": p["lfo_vcf"],
        "jp-kf": p["kf"],
        "jp-vca-lfo": p["vca_lfo"],
        "jp-level": p["level"],
        "jp-e1-a": atk(a1), "jp-e1-d": dec(d1), "jp-e1-s": s1, "jp-e1-r": dec(r1),
        "jp-e1-kf": p["e1_kf"], "jp-e1-pol": p["e1_pol"],
        "jp-e2-a": atk(a2), "jp-e2-d": dec(d2), "jp-e2-s": s2, "jp-e2-r": dec(r2),
        "jp-e2-kf": p["e2_kf"],
        "jp-bend": 0.0,
        "jp-bend-vco": p["bend_vco"], "jp-bend-vcf": p["bend_vcf"],
        "jp-bend-v1": p["bend_v1"], "jp-bend-v2": p["bend_v2"],
        "jp-porta": p["porta"], "jp-porta-t": p["porta_t"],
        "jp-tune": 0.0, "jp-age": p["age"], "jp-vol": p["vol"],
    }


PRESETS = []


def preset(name, note, **over):
    p = dict(BLANK)
    p.update(over)
    PRESETS.append((name, note, p))


def fine(deg):
    """FINE TUNE's pointer angle from 12 o'clock -> cents, +-50 over +-135 deg."""
    return round(max(-50.0, min(50.0, deg * 50 / 135)), 1)


# Roland's sheets.  VCO-2 RANGE is a continuous knob, about 7.5 deg a
# semitone: 16' = -12, 8' = 0, 4' = +12 against VCO-1 at 8'.
preset("13-juicy-funk", "13 JUICY FUNK: inverted ENV-1 snaps the resonant 24 dB filter shut",
       lfo_rate=0, range1=16, wave1="saw", range2=0, fine2=fine(-6), wave2="saw",
       cutoff=8, res=10, env_mod=6, lfo_vcf=3, kf=8, level=5,
       e1=(3, 3, 0, 0), e1_pol=1, e2=(0, 10, 10, 0))
preset("14-sync-sweep", "14 SYNC SWEEP: the slow LFO sweeps VCO-2 under sync after a delay. Roland plays it in UNISON: turn UNI on",
       lfo_rate=3, lfo_delay=5, lfo_vco=9.5, env_vco=4, vmod_dst="vco2",
       pwm=7.5, pwm_src="lfo", range1=16, wave1="saw",
       sync=1, range2=5, wave2="pulse",
       cutoff=6, res=6.5, env_mod=5, lfo_vcf=3.5, kf=7.5, level=5,
       e1=(0, 10, 10, 0), e2=(0, 10, 10, 0), bend_vco=10, bend_v1=0)
preset("16-sync-lead", "16 SYNC LEAD: ENV-1 drops VCO-2 down the sync harmonics, 12 dB on ENV-2. Roland plays it in UNISON: turn UNI on",
       lfo_rate=6.5, env_vco=9, vmod_dst="vco2", range1=16, wave1="saw",
       sync=1, range2=-12, wave2="saw",
       slope=12, cutoff=8, res=3, env_src="env2", env_mod=3, kf=10, level=4,
       e1=(0, 5, 2.5, 0), e2=(0, 10, 10, 0), bend_vco=10, bend_v1=0)
preset("21-clav", "21 CLAV: two narrow pulses at 16', inverted ENV-1 on the filter",
       lfo_rate=7, pwm=7, range1=16, wave1="pulse", range2=-12, fine2=fine(-7), wave2="pulse",
       cutoff=8.5, env_mod=5, kf=10, level=6,
       e1=(6.5, 4.5, 8, 0), e1_pol=1, e2=(0, 5, 0, 3))
preset("31-lo-strings", "31 LO STRINGS: saw and an LFO-swept pulse at 16', 12 dB, vibrato on VCO-1",
       lfo_rate=7, lfo_vco=2, vmod_dst="vco1", pwm=7, pwm_src="lfo",
       range1=16, wave1="saw", range2=-12, fine2=fine(7), wave2="pulse",
       slope=12, cutoff=7, env_mod=3, kf=0, level=4.5,
       e1=(5.5, 7, 7, 5), e1_kf=1, e2=(5.5, 6, 6, 5.5), e2_kf=1)
preset("32-mid-strings", "32 MID STRINGS: the same an octave up, brighter",
       lfo_rate=7.5, lfo_vco=2.5, vmod_dst="vco1", pwm=4, pwm_src="lfo",
       range1=8, wave1="saw", range2=0, fine2=fine(13), wave2="pulse",
       slope=12, cutoff=8.5, env_mod=2.5, kf=0, level=3,
       e1=(5, 7.5, 5.5, 3.5), e1_kf=1, e2=(5, 6, 5, 5), e2_kf=1)
preset("35-lo-brass", "35 LO BRASS: two saws at 16', the 24 dB filter opened by ENV-1 at full",
       lfo_rate=7, range1=16, wave1="saw", range2=-12, fine2=fine(14), wave2="saw",
       cutoff=4, env_mod=10, kf=0, level=5,
       e1=(3, 5, 3, 2), e2=(0, 0, 6, 3.5))
preset("36-hi-brass", "36 HI BRASS: the brass at 8', slower filter",
       lfo_rate=7, range1=8, wave1="saw", range2=0, fine2=fine(9), wave2="saw",
       cutoff=4.5, env_mod=10, kf=0, level=5,
       e1=(5, 6, 4.5, 6.5), e2=(0, 5, 8, 5))
preset("38-synth-brass", "38 SYNTH BRASS: 12 dB with some resonance, a fast swell",
       lfo_rate=7.5, range1=16, wave1="saw", range2=-12, fine2=fine(16), wave2="saw",
       slope=12, cutoff=2.5, res=3.5, env_mod=10, kf=5, level=7,
       e1=(2.5, 5, 2.5, 0.5), e2=(0, 2.5, 5.5, 0.5))
preset("57-tomita-chime", "57 TOMITA CHIME: triangle and sine at 4', inverted ENV-1 bends VCO-2",
       lfo_rate=7, env_vco=10, vmod_dst="vco2", range1=4, wave1="tri", range2=12, wave2="sine",
       cutoff=0, env_src="env2", env_mod=10, kf=10, level=5,
       e1=(0, 0, 5, 5), e1_pol=1, e2=(0, 5, 10, 7.5))
preset("71-fat-fifths", "71 FAT FIFTHS: two LFO-swept pulses a fifth apart, resonant 12 dB",
       lfo_rate=5, pwm=8, pwm_src="lfo", range1=16, wave1="pulse",
       range2=-5, fine2=fine(12), wave2="pulse",
       slope=12, cutoff=3.75, res=7, env_mod=10, kf=10, level=5,
       e1=(0.25, 3.5, 4.5, 0), e2=(0, 5, 6.5, 0))
preset("82-flute", "82 FLUTE: triangle at 4' with a breath of VCO-2's noise, delayed LFO on the filter",
       lfo_rate=6.5, lfo_delay=5, range1=4, wave1="tri", range2=-12, wave2="noise", mix=1.75,
       slope=12, cutoff=2, env_mod=8.5, lfo_vcf=3.5, kf=0, level=6.5,
       e1=(4, 6, 5.5, 3.5), e2=(0, 0, 10, 3))
preset("84-cello", "84 CELLO: saw and pulse at 16', delayed vibrato on VCO-2",
       lfo_rate=6, lfo_delay=3.5, lfo_vco=2, vmod_dst="vco2", pwm=3, pwm_src="lfo",
       range1=16, wave1="saw", range2=-12, fine2=fine(23), wave2="pulse",
       slope=12, cutoff=6.5, env_mod=3, lfo_vcf=2, kf=3.5, level=5,
       e1=(6.5, 4.5, 6.5, 4), e1_kf=1, e2=(5, 4.5, 6, 3), e2_kf=1)
preset("87-upright-bass", "87 UPRIGHT BASS: triangle under a synced pulse, ENV-1 on VCO-2 for the pluck",
       lfo_rate=5.5, env_vco=3.5, vmod_dst="vco2", pwm=8, range1=16, wave1="tri",
       sync=1, range2=0, fine2=fine(-8), wave2="pulse",
       cutoff=4, env_src="env2", env_mod=3, kf=3.5, level=10,
       e1=(0, 3.5, 3.5, 0), e1_kf=1, e2=(0, 4.75, 2.5, 2.5), e2_kf=1)

# The rest of the 64, transcribed the same way into sheets.json: slider
# positions as on the sheet, VCO-2 RANGE in semitones from 8', FINE as the
# pointer's angle.  The bender box's VCF switch sets a third of BEND VCF.
SHEETS = os.path.join(HERE, "sheets.json")


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def load_sheets():
    if not os.path.exists(SHEETS):
        return
    with open(SHEETS) as f:
        sheets = json.load(f)
    for s in sorted(sheets, key=lambda s: s["num"]):
        p = dict(s["params"])
        p["fine2"] = fine(p.pop("fine_deg"))
        p["e1"] = tuple(p["e1"])
        p["e2"] = tuple(p["e2"])
        p["bend_vcf"] = 3 if p.get("bend_vcf") else 0
        note = f'{s["num"]} {s["name"]}: {s["note"]}'
        if s.get("assign", "").lower().startswith("unison"):
            note += ". Roland plays it in UNISON: turn UNI on"
        preset(f'{s["num"]}-{slug(s["name"])}', note, **p)


load_sheets()

# Ours: what the sheets above leave out.
preset("cross-bells", "(ours) CROSS MOD: VCO-2's sine a fifth up drives VCO-1's pitch, clangorous bells",
       range1=8, wave1="tri", cross=4, range2=19, wave2="sine", mix=0,
       cutoff=6, env_mod=4, kf=10, level=7,
       e1=(0, 6, 0, 6), e2=(0, 7.5, 0, 7))

def main():
    os.makedirs(OUT, exist_ok=True)
    for name, note, p in PRESETS:
        doc = {"slab": "preset", "schema": 1, "machine": "jp8", "note": note,
               "params": params(p)}
        with open(os.path.join(OUT, name + ".preset"), "w") as f:
            json.dump(doc, f)
            f.write("\n")
    print(f"wrote {len(PRESETS)} presets to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
