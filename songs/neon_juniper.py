"""Neon Juniper: a Juniper-8 demo after the Jupiter-8 synth-pop of the
early 80s. Original material.

118 BPM, E minor. Everything pitched is the Jupiter model on Roland's own
factory patches: the strings and brass that made the instrument's name, a
sync sweep in the intro, the clav arpeggiated as the JP-8's arpeggiator
would, the upright bass pumping eighths, and the sync lead in unison for
the hook. A gated snare and a plate stand in for the room these records
were cut in.

    PYTHONPATH=tools python3 songs/neon_juniper.py --render
    zig-out/bin/slab songs/neon_juniper.slab
"""
from slabkit import Song, fx

song = Song("Neon Juniper", bpm=118, key="E minor")

intro = song.section("intro", 4)
verse = song.section("verse", 8)
chorus = song.section("chorus", 8)
outro = song.section("outro", 4)

VERSE = "Em C G D"
CHORUS = "C D Bm Em"
ROOM = fx("verb2", "chamber", mix=0.18)
HALL = fx("verb2", "long-melancholy-verb", mix=0.22)
ECHO = fx("delay2", mix=0.18)

# ── sync sweep: the LFO drags VCO-2 under sync, in unison ───────────────
sweep = song.track("SWEEP", "jp8", "14-sync-sweep", volume=0.5, fx=[HALL], params={"jp-hpf": 3},
                   unison=dict(count=4, detune=14, spread=0.7))
sweep.clip(intro).note("E3", at=0, length=15.5, vel=100)

# ── strings: LO STRINGS under everything ────────────────────────────────
strings = song.track("STRINGS", "jp8", "31-lo-strings", volume=0.45, fx=[HALL],
                        params={"jp-hpf": 4.5})
for sec, prog in ((intro, VERSE), (verse, VERSE), (chorus, CHORUS), (outro, VERSE)):
    strings.clip(sec).chords(prog, near=55, voices=4, vel=80)

# ── clav through the arpeggiator: up, two octaves, sixteenths ──────────
clav = song.track("ARP", "jp8", "21-clav", volume=0.4, pan=0.3, fx=[ECHO, ROOM])
for sec, prog in ((verse, VERSE), (chorus, CHORUS)):
    clav.clip(sec).arp(prog, "up", rate=0.25, octave=4, octaves=2, vel=90)

# ── bass: UPRIGHT BASS pumping eighths ──────────────────────────────────
bass = song.track("BASS", "jp8", "87-upright-bass", volume=0.6, fx=[ROOM])
for sec, prog in ((verse, VERSE), (chorus, CHORUS)):
    bass.clip(sec).bass(prog, "x.x.o.x.x.x.o.x.", octave=2, vel=100)

# ── brass: LO BRASS stabs in the chorus ─────────────────────────────────
brass = song.track("BRASS", "jp8", "35-lo-brass", volume=0.5, pan=-0.2, fx=[ROOM],
                    params={"jp-hpf": 3})
brass.clip(chorus).chords(CHORUS, "x..x..x.........", near=60, voices=4, vel=96)

# ── the hook: SYNC LEAD in unison ───────────────────────────────────────
lead = song.track("LEAD", "jp8", "16-sync-lead", volume=0.45, fx=[ECHO, HALL],
                  unison=dict(count=3, detune=10, spread=0.5))
lead.clip(chorus).melody(
    "E5:1.5 D5:.5 E5:1 G5:1 | F#5:3 D5:1 | D5:1.5 B4:.5 D5:1 F#5:1 | E5:4 "
    "| E5:1.5 D5:.5 E5:1 G5:1 | A5:3 G5:1 | F#5:1.5 E5:.5 D5:1 F#5:1 | E5:4")

# ── bells: CROSS MOD, sparse ────────────────────────────────────────────
bells = song.track("BELLS", "jp8", "cross-bells", volume=0.3, pan=0.4, fx=[HALL])
bells.clip(intro).melody("r:2 B5:1 r:5 G5:1 r:3 F#5:1 r:3")
bells.clip(outro).melody("r:2 E6:1 r:5 B5:1 r:7")

# ── drums: a gated snare, as the decade wanted ─────────────────────────
drums = song.track("DRUMS", "drum2", "gated-snare-kit", volume=0.45)
for sec in (verse, chorus):
    drums.clip(sec).drums({"kick": "x.......x.x.....", "snare": "....x.......x...",
                           "hat": "x.x.x.x.x.x.x.x."}, bars=sec.bars)

song.master(fx=[fx("limiter2", gain=9, ceil=-1)])

song.save()

if __name__ == "__main__":
    import sys
    if "--render" in sys.argv:
        song.render()
