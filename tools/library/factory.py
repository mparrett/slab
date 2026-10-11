#!/usr/bin/env python3
"""factory.py - build the library instruments that ship with slab.

A few instruments from the CC0 library packs ship as factory samples, so
they play without the packs' gigabytes:

  vcsl       two pianos, the FM piano, a harpsichord, mallets, an ocarina
             and three drum kits (the rest of VCSL: packs/vcsl.pack.json)
  karoryfer  two fingered basses, the clean electric guitar, the alto sax
             (packs/karoryfer.pack.json)
  vsco       the string sections, solo contrabass pizzicato, trumpet and
             trombone (packs/vsco.pack.json)

This reads the SFZs the pack tools made in the library (run vcsl.py,
karoryfer.py and vsco.py first), converts every sample to 16-bit mono FLAC
at 44.1 kHz, whole, into machines/sampler/assets/<pack>/<name>/, writes
<name>.sfz beside them, and the pack's preset for it, pointed at the
factory copy, into machines/sampler/presets/<bank>/ under the same name
the pack uses - so songs that name a pack preset play without the pack.
Unfairlight's VCSL presets point at the same SFZs.  Needs sox.

  tools/library/factory.py                 every pack
  tools/library/factory.py --pack vsco     one pack
"""

import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vcsl  # noqa: E402

SLAB = vcsl.SLAB
SAMPLER = os.path.join(SLAB, "machines/sampler")

# pack: {library SFZ (under the pack): (preset path under the pack's
# presets/sampler/, factory bank, factory name)}
FACTORY = {
    "vcsl": {f"{src}": (src, "vcsl", name) for src, name in {
        "vcsl-keys/upright-piano-yamaha": "upright-piano",
        "vcsl-keys/grand-piano-kawai": "grand-piano",
        "vcsl-keys/fm-piano": "fm-piano",
        "vcsl-keys/harpsichord-french": "harpsichord",
        "vcsl-mallets/marimba": "marimba",
        "vcsl-mallets/kalimba-kenya": "kalimba",
        "vcsl-winds/ocarina-typical-sus": "ocarina",
        "vcsl-kits/acoustic-kit": "acoustic-kit",
        "vcsl-kits/studio-kit": "studio-kit",
        "vcsl-kits/latin-kit": "latin-kit",
    }.items()},
    "karoryfer": {f"slab/{n}": (f"karoryfer/{n}", "karoryfer", n)
                  for n in ("fashionbass", "growlybass", "emilyguitar", "weresax-alto")},
    "vsco": {f"{b}/{n}": (f"{b}/{n}", b, n) for b, n in (
        ("vsco-strings", "violin-section-susvib"), ("vsco-strings", "violin-section-spic"),
        ("vsco-strings", "viola-section-susvib"), ("vsco-strings", "cello-section-susvib"),
        ("vsco-strings", "solo-contrabass-pizz"),
        ("vsco-brass", "trumpet-sus"), ("vsco-brass", "trumpet-susvib"), ("vsco-brass", "trumpet-stac"),
        ("vsco-brass", "tenor-trombone-sus"), ("vsco-brass", "tenor-trombone-vib"),
        ("vsco-brass", "tenor-trombone-stac"))},
}


def convert(src, dst):
    subprocess.run(["sox", src, "-b", "16", "-c", "1", "-r", "44100", dst], check=True)


def build(pack, lib, src_name, preset_src, bank, name):
    sfz = os.path.join(lib, src_name + ".sfz")
    assets = os.path.join(SAMPLER, "assets", pack)
    out = os.path.join(assets, name)
    os.makedirs(out, exist_ok=True)
    lines, files = [], {}
    for line in open(sfz):
        line = line.rstrip("\n")
        m = re.search(r"sample=(.+)$", line)
        if not m:
            lines.append(line)
            continue
        src = os.path.normpath(os.path.join(os.path.dirname(sfz), m.group(1)))
        if src not in files:
            files[src] = f"{len(files) + 1:03d}-{os.path.basename(src)[:-4].replace(' ', '_')}.flac"
            dst = os.path.join(out, files[src])
            if not os.path.exists(dst):
                convert(src, dst)
        lines.append(line[: m.start()] + f"sample={name}/{files[src]}")
    lines.insert(2, "// shipped with slab as 16-bit mono FLAC at 44.1 kHz (tools/library/factory.py)")
    with open(os.path.join(assets, name + ".sfz"), "w") as f:
        f.write("\n".join(lines) + "\n")
    # the pack's preset for this SFZ, pointed at the factory copy
    pre = json.load(open(os.path.join(lib, "presets/sampler", preset_src + ".preset")))
    pre["assets"] = {"smp": f"factory:machines/sampler/assets/{pack}/{name}.sfz"}
    presets = os.path.join(SAMPLER, "presets", bank)
    os.makedirs(presets, exist_ok=True)
    with open(os.path.join(presets, name + ".preset"), "w") as f:
        json.dump(pre, f)
        f.write("\n")
    size = sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out))
    print(f"{name}: {len(files)} samples, {size / 1e6:.1f} MB", flush=True)
    return size


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", action="append", choices=sorted(FACTORY), help="only this pack (repeatable)")
    args = ap.parse_args()
    total = 0
    for pack in args.pack or sorted(FACTORY):
        lib = os.path.join(vcsl.library_root(), pack)
        size = sum(build(pack, lib, src, *dst) for src, dst in FACTORY[pack].items())
        print(f"{pack}: {size / 1e6:.1f} MB")
        total += size
    print(f"total {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
