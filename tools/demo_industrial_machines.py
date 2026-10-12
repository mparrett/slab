"""Generate a five-part native effect audition in scratch/industrial-machines.

    PYTHONPATH=tools python3 tools/demo_industrial_machines.py --render

Writes only the demo package/export, never an existing song. Regeneration
owns that scratch package. Sources are Slab's synthetic CC0 factory foley.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from slabkit import Song, fx
from slabkit.machines import SLAB

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'scratch/industrial-machines'
PACKAGE = WORK / 'demo.slab'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    audio = PACKAGE / 'audio'
    audio.mkdir(parents=True, exist_ok=True)
    names = ['door-slam', 'anvil', 'glass-smash', 'metal-loop']
    for name in names:
        shutil.copy2(ROOT / f'machines/unfairlight/assets/{name}.wav', audio / f'{name}.wav')
    (audio / 'kit.sfz').write_text('\n'.join(
        f'<region> key={36+i} pitch_keycenter={36+i} loop_mode=one_shot sample={name}.wav'
        for i, name in enumerate(names)) + '\n')
    s = Song('Industrial Machines Audition', bpm=140)
    patches = [
        ('DRY FOLEY', []),
        ('BUFFER LOOM', [fx('buffer2', 'steel-scrambler', mix=.72, out=6)]),
        ('MODAL BANK', [fx('resonator2', 'steel-body', mix=1, out=24)]),
        ('SIDEBAND', [fx('shift2', 'warped-steel', mix=1, out=0)]),
        ('COMBINED', [fx('buffer2', 'reverse-grains', mix=.5),
                      fx('resonator2', 'pipe-chamber', mix=.45, out=9),
                      fx('shift2', 'slow-sidebands', mix=.55, out=3)])]
    for name, effects in patches:
        sec = s.section(name, 4)
        t = s.track(name, 'sampler', 'raw', samples=str(audio/'kit.sfz'),
                    volume=.48, params=dict(atk=.001, rel=.06, level=.8), fx=effects)
        c = t.clip(sec)
        for b in range(4):
            for at, key, vel, gate in [(0,36,112,.25),(.75,37,94,.18),
                                      (1.5,38,78,.16),(2.25,37,105,.22),
                                      (3,39,86,.32),(3.5,38,67,.1)]:
                c.note(key,b*4+at,gate,vel)
    s.master(subsonic=True, fx=[fx('limiter2', gain=7, ceil=-3.5)])
    s.save(PACKAGE)
    if args.render:
        with open(WORK/'render.log','w') as log:
            r = subprocess.run([SLAB,str(PACKAGE),'--render',str(WORK/'demo.wav'),
                                '--tail','8','--bits','24','--stems',str(WORK/'stems'),
                                '--stem-kind','all','--tap','fader'],cwd=ROOT,
                               stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        if r.returncode:
            raise RuntimeError((WORK/'render.log').read_text()[-4000:])
        from slabkit.analyze import analyze_wav, print_report
        report = analyze_wav(str(WORK/'demo.wav'),[(sec.name,s.seconds_at(sec.start),s.seconds_at(sec.end))
                                                  for sec in s.sections])
        print_report(str(WORK/'demo.wav'),report)
        (WORK/'analysis.json').write_text(json.dumps(report,indent=2,default=str)+'\n')


if __name__ == '__main__':
    main()
