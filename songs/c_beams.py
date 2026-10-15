"""C-Beams: a C-Beam 80 demo after the CS-80 film scores of the early 80s.
Original material.

72 BPM, D minor. Everything is the CS-80 model played the way the
instrument wants: per-note pressure swells each brass note after its
attack, brings vibrato in on the held notes only, and the phrase ends
fall away as the ribbon would take them. A long hall stands in for the
Lexicon 224 these records went through.

    PYTHONPATH=tools python3 songs/c_beams.py
    zig-out/bin/slab songs/c_beams.slab
"""
from slabkit import Song, fx

song = Song("C-Beams", bpm=72, key="D minor")

intro = song.section("intro", 4)
theme = song.section("theme", 8)
swell = song.section("swell", 4)
coda = song.section("coda", 4)

PROG = "Dm9 Bbmaj7 Gm9 A7sus4"
HALL = fx("verb2", "long-melancholy-verb", mix=0.26)

# ── pad: STRING 2 over slow PWM, chorus on, breathing with pressure ─────
pad = song.track("PAD", "cs80", "tears-pad", volume=0.55, fx=[HALL])
for sec in (intro, theme, swell, coda):
    c = pad.clip(sec).chords(PROG, near=57, voices=4, vel=70)
    c.bend([(0, 0.5), (1.5, 0.75), (3.5, 0.55)], dim="pressure")

# ── bells: the ring modulator's swept carrier, sparse ───────────────────
bells = song.track("BELLS", "cs80", "ring-bells", volume=0.35, pan=0.3, fx=[HALL])
b = bells.clip(intro)
b.melody("r:2 A5:1 r:5 F5:1 r:3 E5:1 r:3")
bells.clip(coda).melody("r:2 D6:1 r:5 A5:1 r:7")

# ── the brass theme: each note swells with pressure, vibrato on the long
#    ones, and the last note of each phrase falls ─────────────────────────
brass = song.track("BRASS", "cs80", "rain-brass", volume=0.6, fx=[HALL])
t = brass.clip(theme)
t.melody("A4:3 G4:.5 F4:.5 | E4:2 F4:1 G4:1 | D4:6 r:2 "
         "| A4:3 Bb4:.5 C5:.5 | D5:2 C5:1 E4:1 | D4:6 r:2")
t.bend([(0, 0.5), (0.4, 0.55), (1.6, 0.9), (4, 0.8)], dim="pressure")
for n in t.notes:
    if n["len"] >= 6:
        # the ribbon's fall at the end of a phrase
        t.bend([(0, 0), (4.5, 0), (6, -5, "curve", -0.6)],
               notes=lambda m, s=n["start"]: m["start"] == s)

# ── swell: the brass chords Yamaha's method is known for ────────────────
ch = song.track("CHORDS", "cs80", "brass", volume=0.42, fx=[HALL])
s = ch.clip(swell).chords(PROG, near=60, voices=4, vel=92)
s.bend([(0, 0.5), (0.6, 0.5), (2.6, 1.0), (4, 0.7)], dim="pressure")

# ── bass: the resonant pluck under the theme ────────────────────────────
bass = song.track("BASS", "cs80", "bass", volume=0.8, fx=[fx("verb2", "chamber", mix=0.12)])
for sec in (theme, swell):
    bass.clip(sec).bass(PROG, "x.......x...x...", octave=2, vel=96)

song.master(fx=[fx("limiter2", gain=6, ceil=-1)])

song.save()

if __name__ == "__main__":
    import sys
    if "--render" in sys.argv:
        song.render()
