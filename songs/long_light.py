"""Long Light — a slow rock ballad with a lead guitar solo in the manner
of David Gilmour, written to show Fretwire's guitar and bass: strummed
chord shapes, bends held with finger vibrato, bend-and-release,
pre-bends, slides into notes, hammer-ons and pull-offs.

An original piece (E minor, Em C G D); the solo borrows his vocabulary,
not his notes: long bent notes and space, a vibrato that only pushes
the string sharp, phrases that answer each other, a climb in the second
chorus to bends at the top of the neck, and a delay that repeats them.

  part            played by                                   all factory
  lead guitar     Fretwire Guitar, bridge pickup, sustain     guitar
                  -> Ampstack BRIT -> delay -> hall
  rhythm guitar   Fretwire Guitar strums: clean in the verse,  guitar
                  crunch in the solos, fingerpicked intro
  bass            Fretwire, fingers, into Ampstack + DI        bass
  drums           VCSL studio kit                              sampler
  strings         VSCO cello and violin sections               sampler

    PYTHONPATH=tools python3 songs/long_light.py [--render [--stems]]
    zig-out/bin/slab demos/long_light.slab

A factory demo: this script writes demos/long_light.slab, which ships with
Slab and plays from its factory samples alone.
"""
import os
import sys

from slabkit import Song, fx
from slabkit.theory import Chord, guitar_voicing

song = Song("Long Light", bpm=66, key="E minor")
FORM = [("intro", 4), ("verse", 8), ("solo 1", 8), ("solo 2", 8), ("outro", 4)]
S = {name: song.section(name, bars) for name, bars in FORM}
PROG = "Em C G D"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── returns ─────────────────────────────────────────────────────────────
# The stadium is mostly here: a big dark hall for depth, a long tape echo
# that ducks under the lead and blooms in its gaps, and a short double
# either side, the ADT that spreads a mono solo across the speakers.
hall = song.bus("HALL", volume=0.85, fx=[
    fx("verb2", "big-hall", decay=3.6, predelay=0.06, lowcut=350, damp=5000, mix=1.0),
])
room = song.bus("ROOM", volume=0.6, fx=[
    fx("verb2", "small-room", decay=0.7, predelay=0.01, lowcut=250, damp=6000, mix=1.0),
])
echo = song.bus("ECHO", volume=0.8, fx=[
    # an Echorec-ish eighth (455 ms here), tape-dark, wobbling a little
    fx("delay2", sync="SYNC", div="1/8", mode="PING", fb=0.45, lowcut=450, damp=3200,
       char="TAPE", mod=0.25, rate=0.6, duck=0.55, mix=1.0),
])
echo.send(hall, -6)
adt_l = song.bus("ADT L", volume=0.75, pan=-0.85, fx=[
    fx("delay2", sync="FREE", time=0.021, fb=0.0, char="TAPE", mod=0.3, rate=0.9, mode="STEREO", mix=1.0),
])
adt_r = song.bus("ADT R", volume=0.75, pan=0.85, fx=[
    fx("delay2", sync="FREE", time=0.031, fb=0.0, char="TAPE", mod=0.3, rate=0.7, mode="STEREO", mix=1.0),
])
for b in (adt_l, adt_r):
    b.send(hall, -10)

# ── drums ───────────────────────────────────────────────────────────────
KIT = "vcsl/studio-kit"
drum_bus = song.bus("DRUMS", fx=[
    fx("bus2", "drum-bus", thresh=-16, makeup=1.5, color=0.15),
    fx("comp2", None, thresh=-30.0, ratio=1.5, atk=0.03, rel=0.2, makeup=11.0, mix=1.0),
    fx("eq2", None, hpf_on="ON", hpf_hz=40.0, ls_db=-4.0, ls_hz=90.0, p1_hz=400.0, p1_db=-2.0, p1_q=0.9,
       p2_hz=3500.0, p2_db=2.5, p2_q=0.8, hs_db=1.5, hs_hz=8000.0),
])
drum_bus.send(room, -10)
drum_bus.send(hall, -16)
drums = song.track("DRUMS", "sampler", KIT, volume=1.0, params=dict(level=1.0), output=drum_bus)
K, SN, CH, OH, CR, RD, T1, T2, T3 = 36, 38, 42, 46, 49, 51, 48, 45, 41
SOFT = {"x": 90, "o": 56, "X": 108}     # hats and cymbals sit back

v = drums.clip(S["verse"])
# half time: kick on one and the and of three, snare on three, hats in eighths
v.drums({K: "x.......x...x...", SN: "........x......."}, step=0.25, bars=7)
v.drums({CH: "x.o.x.o.x.o.x.o."}, step=0.25, bars=7, vel=SOFT)
v.drums({K: "x.......x...x...", SN: "........x...x.x.", T1: "..............x."}, at=28, step=0.25, bars=1)
v.note(CR, 0, 1, 84)

for name in ("solo 1", "solo 2"):
    c = drums.clip(S[name])
    c.drums({K: "x.....x.x.......", SN: "....X.......X..."}, step=0.25, bars=7)
    # hats throughout; the second chorus opens the hat on the and of four
    hat = "x.o.x.o.x.o.x.o." if name == "solo 1" else "x.o.x.o.x.o.x.O."
    c.drums({CH: hat.replace("O", ".")}, step=0.25, bars=7, vel=SOFT)
    if name == "solo 2":
        c.drums({OH: "..............x."}, step=0.25, bars=7, vel=SOFT)
    # the fill into the next section: snare and toms down
    c.drums({K: "x.....x.........", SN: "....X...xoxx....", T1: "............xx..", T2: "..............x.",
             T3: "...............x"}, at=28, step=0.25, bars=1)
    c.note(CR, 0, 1, 100)
    c.note(CR, 16, 1, 84)
o = drums.clip(S["outro"])
o.note(K, 0, 1, 104)
o.note(CR, 0, 2, 104)
o.drums({K: "x.......x......."}, step=0.25, bars=2, at=4)
o.drums({RD: "x...x...x...x..."}, step=0.25, bars=2, at=4, vel={"x": 58})
for c in drums.clips:
    c.humanize(time=0.004, vel=4)

# ── bass: warm, behind the guitars, notes left to ring off ──────────────
bass = song.track("BASS", "bass", "flatwound", volume=0.57, params=dict(
    soft=3.0, tone=1600.0, release=0.45, thump=0.35, decay=8.0,
), fx=[
    fx("amp2", "bass-vintage-15", blend=0.45, level=-6.0),
    fx("comp2", "bass-leveler"),
])
bass.clip(S["verse"]).bass(PROG, "x.......x.......", octave=1, vel=84, gate=0.97)
for name in ("solo 1", "solo 2"):
    bass.clip(S[name]).bass(PROG, "x...x...x...x.5.", octave=1, vel=88, gate=0.95)
bo = bass.clip(S["outro"])
bo.note("E1", 0, 15.5, 90)

# ── rhythm guitar ───────────────────────────────────────────────────────
clean = song.track("CLEAN GTR", "guitar", "fingers", volume=0.9, pan=-0.4, fx=[
    fx("amp2", "guitar-clean", level=6.0),
    fx("chorus2", "juno-i", mix=0.35),
])
clean.send(hall, -8)
clean.send(echo, -16)

# intro: fingerpicked, the shapes' strings in eighths, each left ringing
intro = clean.clip(S["intro"])
for bar, sym in enumerate(PROG.split()):
    shape = guitar_voicing(sym)
    order = [0, 2, 3, 4, 3, 2, 1, 2]
    for k, idx in enumerate(order):
        p = shape[min(idx, len(shape) - 1)]
        intro.note(p, bar * 4 + k * 0.5, 4 - k * 0.5, 78 if k == 0 else 62 + 6 * (k % 2))
intro.humanize(time=0.006, vel=5)

# verse: a gentle strum, accents on the downbeats
clean.clip(S["verse"]).strums(PROG, "D..d..DU", step=0.5, vel=88, soft=0.65)

crunch = song.track("CRUNCH GTR", "guitar", "default", volume=0.55, pan=0.45, fx=[
    fx("amp2", "guitar-crunch"),
])
crunch.send(room, -12)
crunch.send(hall, -14)
for name in ("solo 1", "solo 2"):
    pat = "D..D.DUD" if name == "solo 1" else "D.DU.UDU"
    crunch.clip(S[name]).strums(PROG, pat, step=0.5, vel=100, position={"C": 3, "G": 3, "D": 5})
cr = crunch.clip(S["outro"])
cr.strum("Em", 0, 15.5, "down", vel=110)
# the rhythm guitar's amp gets hotter as the solo climbs, and backs off
# for the outro's last chord
crunch.automate("fx0:gain", (S["solo 1"].start, 0.3), (S["solo 2"].start, 0.42, "curve", -0.3),
                (S["solo 2"].start + 28, 0.62), (S["outro"].start, 0.5))

# ── keys: a Rhodes comping softly, a slow pad underneath ───────────────
keys = song.track("RHODES", "rhodes", "mellow", volume=0.85, pan=0.2, fx=[
    fx("chorus2", "juno-i", mix=0.5),
])
keys.send(hall, -8)
for name in ("verse", "solo 1", "solo 2"):
    keys.clip(S[name]).chords(PROG, "x.......x.......", near=62, voices=4, vel=64, gate=0.98)
keys.clip(S["outro"]).chords("Em", None, near=62, voices=4, vel=62)

pad = song.track("PAD", "juno2", "lush-pad", volume=0.6, fx=[
    fx("chorus2", "juno-ii", mix=0.6),
])
pad.send(hall, -4)
for name in ("intro", "solo 1", "solo 2", "outro"):
    pad.clip(S[name]).chords(PROG if name != "outro" else "Em", None, near=60, voices=4, spread=True, vel=70)
pad.ride({"intro": -4, "solo 1": -2, "solo 2": 0, "outro": (0, -8)})

# ── strings ─────────────────────────────────────────────────────────────
string_bus = song.bus("STRINGS", volume=0.9)
string_bus.send(hall, -4)
cello = song.track("CELLOS", "sampler", "vsco-strings/cello-section-susvib", volume=0.55, pan=-0.2,
                   output=string_bus)
violins = song.track("VIOLINS", "sampler", "vsco-strings/violin-section-susvib", volume=0.9, pan=0.25,
                     output=string_bus)
for name in ("solo 2", "outro"):
    lo = cello.clip(S[name])
    hi = violins.clip(S[name])
    bars = 8 if name == "solo 2" else 4
    for bar in range(bars):
        ch = Chord.parse(PROG.split()[bar % 4] if name == "solo 2" else "Em")
        lo.note(ch.root_pitch(2), bar * 4, 4, 70)
        lo.note(ch.root_pitch(2) + 7, bar * 4, 4, 62)
        for p in ch.pitches(4)[1:]:
            hi.note(p, bar * 4, 4, 58)

# ── the lead ────────────────────────────────────────────────────────────
# After the rig: a compressor up front for sustain, a fuzz at moderate
# gain, a clean amp with headroom into a 4x12, a touch of chorus; the
# stadium comes from the returns (echo, hall, ADT). The fuzz is ridden:
# restrained in the first chorus, pushed as the second one climbs.
lead = song.track("LEAD GTR", "guitar", "default", volume=0.8, pan=0.0, params=dict(
    decay=24.0, hfdec=1.6, pickup=0.1, thump=0.25, vibrate=4.8, vibdepth=0.9,
), fx=[
    fx("comp2", None, thresh=-28.0, ratio=4.0, atk=0.012, rel=0.25, makeup=6.0, mix=1.0),
    fx("sat2", "fuzz-wall", drive=20.0, tone=3200.0, sag=0.15),
    fx("amp2", None, voice="BASS", gain=0.3, bass=0.45, mid=0.6, treble=0.55, pres=0.35, master=0.35,
       cab="4x12", mic=0.25, level=-7.0),
    fx("chorus2", "juno-i", mix=0.15),
])
lead.send(echo, 0)
lead.send(hall, -6)
lead.send(adt_l, -5)
lead.send(adt_r, -5)
lead.automate("fx1:drive", (S["solo 1"].start, 18.0), (S["solo 2"].start, 22.0, "curve", -0.3),
              (S["solo 2"].start + 16, 28.0), (S["outro"].start, 26.0), (S["outro"].start + 15, 20.0))


def phrase(clip):
    """Notes with gestures, timed in beats from the clip's start.

    play(pitch, at, len, vel, bend=[(beat, semis)...], vib=(start, depth),
         legato=True: overlaps the previous note, a hammer-on or pull-off)"""
    state = {"prev": None}

    def play(pitch, at, ln, vel=96, bend=None, vib=None, legato=False):
        if legato and state["prev"] is not None:
            p_at, p_pitch, p_ln = state["prev"]
            # stretch the previous note into this one so they overlap
            for n in clip.notes:
                if n["start"] == p_at and n["pitch"] == p_pitch:
                    n["len"] = max(n["len"], at - p_at + 0.12)
        clip.note(pitch, at, ln, vel)
        pn = clip.notes[-1]["pitch"]
        pick = (lambda n, a=at, q=pn: n["start"] == a and n["pitch"] == q)
        if bend:
            clip.bend([(t, s, "curve", -0.4) if i else (t, s) for i, (t, s) in enumerate(bend)], notes=pick)
        if vib:
            start, depth = vib
            clip.bend([(0.0, 0.0), (start, 0.0), (start + 0.5, depth, "linear")], notes=pick, dim="slide")
        state["prev"] = (at, clip.notes[-1]["pitch"], ln)
    return play


def bend_hold(to=2, rise=0.35, hold=None):
    pts = [(0.0, 0), (rise, to)]
    if hold:
        pts.append((hold, to))
    return pts


def bend_release(to=2, rise=0.3, top=0.9, down=1.3):
    return [(0.0, 0), (rise, to), (top, to), (down, 0)]


def prebend(to=2, hold=0.4, down=0.9):
    return [(0.0, to), (hold, to), (down, 0)]


def slide_in(frm=-2, over=0.2):
    return [(0.0, frm), (over, 0)]


# solo 1: low and patient
s1 = lead.clip(S["solo 1"])
p = phrase(s1)
# Em: the opening cry, A bent to B and held
p("A4", 1.0, 2.75, 100, bend=bend_hold(2, 0.4, 2.75), vib=(0.9, 0.9))
# C: an answer climbing with hammer-ons, settling on D
p("G4", 4.5, 0.5, 90)
p("A4", 5.0, 0.5, 84, legato=True)
p("B4", 5.5, 1.0, 92, legato=True, bend=[(0.0, 0), (0.2, 0.4), (0.5, 0)])
p("D5", 6.5, 1.5, 96, vib=(0.4, 0.8))
# G: D bent up to E and let back down, falling through pull-offs to G
p("D5", 8.0, 1.6, 102, bend=bend_release(2, 0.3, 0.9, 1.4))
p("B4", 9.75, 0.5, 90)
p("A4", 10.25, 0.5, 84, legato=True)
p("G4", 10.75, 1.25, 88, legato=True, vib=(0.3, 0.8))
# D: slide into F# and hold it, then a pickup into the next bar
p("F#4", 12.0, 2.5, 96, bend=slide_in(-2, 0.25), vib=(0.8, 1.0))
p("A4", 14.75, 0.5, 86)
p("B4", 15.25, 0.75, 92, legato=True)
# Em: a pre-bend let down, then the high note bent slowly to its top
p("E5", 16.0, 1.0, 100, bend=prebend(2, 0.35, 0.8))
p("D5", 17.0, 0.5, 90)
p("E5", 17.5, 2.5, 104, bend=bend_hold(2, 0.6, 2.5), vib=(1.0, 1.0))
# C: a run of pull-offs, the breath of the solo
p("G5", 20.5, 0.33, 96)
p("E5", 20.83, 0.33, 86, legato=True)
p("D5", 21.16, 0.34, 86, legato=True)
p("E5", 21.5, 2.0, 98, vib=(0.5, 0.9))
# G: B bent a minor third to D, released, the curl of a blues phrase
p("B4", 24.0, 1.5, 100, bend=bend_release(3, 0.4, 1.0, 1.5))
p("A4", 25.75, 0.5, 88)
p("G4", 26.25, 1.75, 92, vib=(0.6, 0.9))
# D: a long A bent to B, its vibrato carrying over the turnaround
p("A4", 28.0, 3.75, 104, bend=bend_hold(2, 0.5, 3.75), vib=(1.0, 1.0))

# solo 2: up the neck, more urgent
s2 = lead.clip(S["solo 2"])
p = phrase(s2)
p("B4", 0.0, 0.5, 96)
p("D5", 0.5, 0.5, 96)
p("E5", 1.0, 0.5, 100)
p("G5", 1.5, 2.5, 108, bend=bend_hold(2, 0.35, 2.5), vib=(0.8, 1.0))
p("A5", 4.0, 1.25, 106, bend=bend_release(2, 0.3, 0.8, 1.2))
p("G5", 5.5, 0.5, 96)
p("E5", 6.0, 2.0, 100, vib=(0.4, 0.9))
p("B5", 8.0, 2.0, 110, bend=bend_hold(1, 0.3, 2.0), vib=(0.7, 0.8))
p("A5", 10.0, 0.33, 98)
p("G5", 10.33, 0.33, 92, legato=True)
p("E5", 10.66, 0.34, 92, legato=True)
p("D5", 11.0, 1.0, 98, bend=[(0.0, 0), (0.25, 2), (0.6, 2), (0.9, 0)])
p("E5", 12.0, 0.5, 98, bend=slide_in(-2, 0.2))
p("G5", 12.5, 0.5, 100)
p("A5", 13.0, 3.0, 110, bend=bend_hold(2, 0.5, 3.0), vib=(1.0, 1.0))
# the peak: the top note bent and bent again
p("D6", 16.0, 1.5, 114, bend=bend_release(2, 0.3, 1.0, 1.4))
p("B5", 17.5, 0.5, 104)
p("D6", 18.0, 2.0, 116, bend=bend_hold(2, 0.5, 2.0), vib=(0.8, 1.0))
p("B5", 20.0, 0.25, 100)
p("A5", 20.25, 0.25, 96, legato=True)
p("G5", 20.5, 0.25, 96, legato=True)
p("E5", 20.75, 0.25, 96, legato=True)
p("G5", 21.0, 0.5, 100)
p("A5", 21.5, 2.5, 110, bend=bend_hold(2, 0.4, 2.5), vib=(0.6, 1.0))
p("E5", 24.0, 1.0, 102, bend=prebend(2, 0.4, 0.9))
p("D5", 25.0, 0.5, 96)
p("B4", 25.5, 2.5, 100, bend=bend_hold(2, 0.5, 2.5), vib=(0.9, 1.0))
p("A4", 28.0, 0.5, 96)
p("B4", 28.5, 0.5, 98, legato=True)
p("D5", 29.0, 3.0, 104, bend=bend_hold(2, 0.6, 3.0), vib=(1.0, 1.0))

# outro: the last note, bent and left to the echoes
oc = lead.clip(S["outro"])
p = phrase(oc)
p("B4", 0.0, 7.5, 108, bend=bend_hold(2, 0.8, 7.5), vib=(1.5, 1.0))
p("G4", 8.5, 0.5, 90)
p("E4", 9.0, 6.0, 96, bend=slide_in(-2, 0.3), vib=(1.5, 0.8))

# ── master: a gentle chain, then up to a streaming level ───────────────
song.master(fx=[
    fx("eq2", None, hpf_on="ON", hpf_hz=28.0, ls_db=0.5, ls_hz=90.0, p1_hz=300.0, p1_db=-1.0, p1_q=0.8,
       hs_db=3.0, hs_hz=9000.0),
    fx("multi2", "master-balance"),
    fx("comp2", "soft-master-glue"),
    fx("tape2", "chrome-glue", hiss=0.0, wow=0.05, flutter=0.05),
    fx("limiter2", gain=4.0, ceil=-1.8),
])

if __name__ == "__main__":
    # a factory demo: the generator owns demos/long_light.slab/project.json
    song.save(os.path.join(ROOT, "demos", "long_light.slab"))
    if "--render" in sys.argv:
        song.render(os.path.join(ROOT, "songs", "long_light.wav"), stems="--stems" in sys.argv)
