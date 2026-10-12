"""Generate a native phaser preset comparison in scratch/phaser-audition.

    PYTHONPATH=tools python3 tools/demo_phaser.py --render

Only owns its scratch projects. Prints one Rhodes/synth/foley phrase,
then reuses that exact audio for dry and nine preset sections. Optional
audition compensation lives on track faders; presets are unchanged.
"""
import argparse
import json
from pathlib import Path
import subprocess

from slabkit import Song, fx
from slabkit.machines import SLAB

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'scratch/phaser-audition'
PACKAGE = WORK / 'demo.slab'
PATCHES = ['four-stage-silk', 'four-stage-bite', 'six-stage-keys',
           'twelve-stage-orbit', 'clockwork-funk', 'dub-undertow',
           'steel-vortex', 'audio-rate-metal', 'auxiliary-haze']


def bounce(project, wav, tail=3, stems=None):
    command = [SLAB, str(project), '--render', str(wav), '--tail', str(tail), '--bits', '24']
    if stems:
        command += ['--stems', str(stems), '--stem-kind', 'all', '--tap', 'fader']
    with open(wav.with_suffix('.log'), 'w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=True)
    if result.returncode:
        raise RuntimeError(wav.with_suffix('.log').read_text()[-4000:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    audio = PACKAGE / 'audio'
    audio.mkdir(parents=True, exist_ok=True)
    source = audio / 'phrase.wav'
    raw = Song('Phaser Source Phrase', bpm=120, key='D minor')
    phrase = raw.section('SOURCE', 4)
    keys = raw.track('RHODES', 'rhodes', 'bright', volume=.42)
    synth = raw.track('SYNTH', 'concoction', volume=.2, params={
        'a_pos': .6666667, 'f_cut': 9000, 'e1_a': .01, 'e1_r': .18,
        'e1_s': .75, 'level': .5})
    chords = [[62, 65, 69, 72], [58, 62, 65, 69], [60, 64, 67, 70], [57, 60, 64, 67]]
    kc, sc = keys.clip(phrase), synth.clip(phrase)
    for bar, chord in enumerate(chords):
        kc.chord(chord, bar*4, 2.9, 95)
        kc.chord(chord, bar*4+3.25, .45, 72)
        sc.chord(chord, bar*4+.5, 2.8, 78)
    foley = raw.track('METAL', 'unfairlight', 'anvil', volume=.07).clip(phrase)
    for at in [1.75, 3.5, 5.75, 7.5, 9.75, 11.5, 13.75, 15]:
        foley.note(60, at, .12, 68)
    raw.master(subsonic=True, fx=[fx('limiter2', gain=8, ceil=-6)])
    raw.save(WORK / 'source.slab')
    bounce(WORK / 'source.slab', source, tail=0)

    song = Song('Phaser Preset Audition', bpm=120)
    for name in ['DRY'] + PATCHES:
        sec = song.section(name.upper(), 4)
        # Leave fader headroom for compensation (host maximum is 1.25).
        track = song.track(name, 'sampler', 'raw', volume=.125,
                           fx=[] if name == 'DRY' else [fx('phaser2', name)])
        track.audio(str(source), sec, dur_sec=8, fade_in=.004, fade_out=.025)
    song.master(subsonic=True, fx=[fx('limiter2', gain=17, ceil=-3.5)])
    song.save(PACKAGE)
    if args.render:
        from slabkit.analyze import analyze_wav, print_report
        sections = [(sec.name, song.seconds_at(sec.start), song.seconds_at(sec.end))
                    for sec in song.sections]
        bounce(PACKAGE, WORK / 'demo.wav', stems=WORK / 'stems')
        report = analyze_wav(str(WORK / 'demo.wav'), sections)
        # Compare timbre without letting dry win just by being louder.
        levels = report['sections']
        reference = levels[0]['lufs']
        trims = {}
        for track, level in zip(song.tracks, levels):
            db = max(-18, min(18, reference - level['lufs']))
            track.volume *= 10**(db/20)
            trims[track.name] = round(db, 2)
        song.save(PACKAGE)
        bounce(PACKAGE, WORK / 'demo.wav', stems=WORK / 'stems')
        report = analyze_wav(str(WORK / 'demo.wav'), sections)
        print_report(str(WORK / 'demo.wav'), report)
        (WORK / 'analysis.json').write_text(json.dumps(report, indent=2, default=str)+'\n')
        (WORK / 'audition-trims.json').write_text(json.dumps(trims, indent=2)+'\n')


if __name__ == '__main__':
    main()
