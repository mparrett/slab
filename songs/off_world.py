"""Off-World: a film-noir end-titles theme for the C-Beam 80. Original
material in the manner of early-80s CS-80 scores: no melody borrowed.

88 BPM, F minor. Rain first: CS-80 noise through both filters and the
ring-modulated bells. Then the pulse, a resonant CS-80 bass in eighths
under a huge distant snare. Then the brass: each note swells under
pressure after its attack, vibrato comes in only on the held notes, and
the long notes fall away at the end as a ribbon would take them. The
climax doubles the theme with Yamaha's BRASS pairing in chords. One long
hall over everything, the way these records went through a Lexicon.

    PYTHONPATH=tools python3 songs/off_world.py --render
    zig-out/bin/slab songs/off_world.slab
"""
from slabkit import Song, fx

song = Song("Off-World", bpm=88, key="F minor")

rain = song.section("rain", 4)
pulse = song.section("pulse", 4)
theme = song.section("theme", 12)
climax = song.section("climax", 8)
coda = song.section("coda", 4)

PROG = "Fm Db Bbm C"
HALL = fx("verb2", "long-melancholy-verb", mix=0.3)
CATHEDRAL = fx("verb2", "cathedral", mix=0.45)


def swell(clip, rise=1.6, peak=0.9, settle=0.8):
    """Pressure after the attack: the CS-80 brass player's lean."""
    clip.bend([(0, 0.5), (0.4, 0.55), (rise, peak), (4, settle)], dim="pressure")


def falls(clip, min_len=6, drop=-7):
    """The ribbon taking each phrase's long last note down."""
    for n in clip.notes:
        if n["len"] >= min_len:
            ln = n["len"]
            clip.bend([(0, 0), (ln - 1.8, 0), (ln, drop, "curve", -0.7)],
                      notes=lambda m, s=n["start"]: m["start"] == s)


# ── rain: CS-80 noise through the HPF/LPF window, slowly breathing ───────
weather = song.track("RAIN", "cs80", "tears-pad", volume=0.9, pan=-0.1, fx=[HALL], params={
    "cb1-saw": 0, "cb1-noise": 9, "cb1-hpf": 5.5, "cb1-res-h": 3, "cb1-lpf": 7.5, "cb1-res-l": 4,
    "cb1-a-a": 0.9, "cb1-a-r": 6.0, "cb-mix": 0, "cb-sub-vcf": 3, "cb-sub-spd": 0.7,
})
for sec in (rain, pulse, theme, climax, coda):
    weather.clip(sec).note("F4", at=0, length=sec.bars * 4 - 0.25, vel=60)

bells = song.track("BELLS", "cs80", "ring-bells", volume=0.75, pan=0.35, fx=[HALL])
bells.clip(rain).melody("r:1 C6:1 r:3 Ab5:1 r:2 F6:1 r:5 Eb6:1 r:1")
bells.clip(coda).melody("r:2 C6:1 r:3 F5:1 r:5 Ab5:1 r:3")

# ── pad: STRING 2 over slow PWM, chorus on ───────────────────────────────
pad = song.track("PAD", "cs80", "tears-pad", volume=0.45, fx=[HALL])
for sec in (rain, pulse, theme, climax, coda):
    c = pad.clip(sec).chords(PROG, near=56, voices=4, vel=66)
    c.bend([(0, 0.5), (2, 0.72), (4, 0.55)], dim="pressure")

# ── pulse: the resonant CS-80 bass in eighths ────────────────────────────
bass = song.track("PULSE", "cs80", "bass", volume=1.0, params={"cb-vol": 1.0}, fx=[fx("verb2", "chamber", mix=0.1)])
for sec in (pulse, theme, climax):
    bass.clip(sec).bass(PROG, "x.x.o.x.x.x.o.x.", octave=2, vel=100)

drums = song.track("DRUMS", "drum2", "synthetic-tom-kit", volume=0.32, fx=[CATHEDRAL])
for sec in (pulse, theme):
    drums.clip(sec).drums({"kick": "x...............", "snare": "........x......."}, bars=sec.bars)
d = drums.clip(climax)
d.drums({"kick": "x.......x.......", "snare": "........x......."}, bars=7)
d.drums({"tom": "x.x.x.xxx.x.xxxx", "snare": "............x.xX"}, at=28, bars=1)

# ── the brass theme ─────────────────────────────────────────────────────
lead = song.track("BRASS", "cs80", "rain-brass", volume=0.8, fx=[HALL])
t = lead.clip(theme)
t.melody("C5:3 Ab4:1 | F4:2 Eb4:1 F4:1 | Db5:3 C5:.5 Bb4:.5 | C5:6 r:2 "
         "| Ab4:3 Bb4:.5 C5:.5 | Db5:2 Eb5:1 Db5:1 | C5:4 Bb4:2 G4:2 | F4:7 r:5")
swell(t)
falls(t)

h = lead.clip(climax)
h.melody("F5:3 Eb5:.5 Db5:.5 | C5:4 | Db5:2 Eb5:2 | F5:4 "
         "| Ab5:3 G5:.5 F5:.5 | E5:4 | F5:7.5")
swell(h, rise=1.2, peak=1.0)
falls(h, min_len=7, drop=-12)

horns = song.track("HORNS", "cs80", "brass", volume=0.4, pan=-0.15, fx=[HALL])
hc = horns.clip(climax).chords(PROG, near=60, voices=4, vel=96)
hc.bend([(0, 0.5), (0.5, 0.5), (2.6, 1.0), (4, 0.7)], dim="pressure")

# ── coda: one last brass note, falling into the rain ────────────────────
last = lead.clip(coda)
last.note("F4", at=0, length=12, vel=80)
swell(last, rise=3, peak=0.85, settle=0.7)
falls(last, min_len=12, drop=-12)

song.master(fx=[fx("limiter2", gain=6, ceil=-1)])

song.save()

if __name__ == "__main__":
    import sys
    if "--render" in sys.argv:
        song.render()
