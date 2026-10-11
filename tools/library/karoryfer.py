#!/usr/bin/env python3
"""karoryfer.py - fetch CC0 Karoryfer instruments and make them playable.

Karoryfer Samples publishes several CC0 multisampled instruments as SFZ
on github.com/sfzinstruments. Their SFZ use opcodes Slab's sampler
doesn't read (lorand/hirand round robins, backslash paths, CC layers),
so this script flattens each chosen program into the subset Slab does
(src/keymap.zig parseSfz):

  - <global>/<master>/<group>/<region> inheritance is resolved;
  - random round robins become seq_length/seq_position;
  - sample paths use forward slashes, relative to the new file;
  - keys outside `keys` (noise keys, scrapes) are dropped, and round
    robins or velocity layers are thinned until the program fits the
    sampler's 256 zones.

Output: lib:karoryfer/slab/<name>.sfz and a sampler preset in the pack,
karoryfer/presets/sampler/karoryfer/<name>.preset.

Usage:
  tools/library/karoryfer.py              fetch [pinned archives] and convert everything below
  tools/library/karoryfer.py --no-fetch   convert what's on disk
"""
import argparse
import json
import os
import re
import shutil
import sys
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcsl import library_root, write_preset  # noqa: E402

MAX_ZONES = 256  # src/keymap.zig MAX_ZONES

# Each repository pinned to the commit the SFZ flattening was checked on.
COMMITS = {
    "karoryfer.weresax": "a4d756b21d2a573aca0d840cce7e71ba5effd4c6",
    "karoryfer.fashionbass": "0703973b300a6bacb837602be9b588ab64732a72",
    "karoryfer.growlybass": "4f483268fc66b5a6d5781d421c0d11b8d08d3fc6",
    "karoryfer.emilyguitar": "b4920dc662fd9cad6dcaccdeecffdd91c8725d8c",
}

# name: (repo, [programs], keys (lo, hi), note, sampler params)
PROGRAMS = {
    "weresax-alto": ("karoryfer.weresax", ["Programs/alto_map_piano_condenser.sfz",
                                           "Programs/alto_map_forte_condenser.sfz"], (40, 100),
                     "Weresax alto saxophone, condenser mic, piano and forte layers",
                     {"smp-atk": 0.008, "smp-rel": 0.12, "smp-vel": 0.5}),
    "fashionbass": ("karoryfer.fashionbass", ["fashionbass_clean.sfz"], (12, 72),
                    "Fashionbass, fingered electric bass direct, five velocity layers",
                    {"smp-atk": 0.002, "smp-rel": 0.08, "smp-vel": 0.45}),
    "growlybass": ("karoryfer.growlybass", ["growlybass_clean.sfz"], (12, 72),
                   "Growlybass, Squier Jazz Bass fingered, clean",
                   {"smp-atk": 0.002, "smp-rel": 0.08, "smp-vel": 0.45}),
    "emilyguitar": ("karoryfer.emilyguitar", ["emily_clean.sfz"], (36, 89),
                    "Emily, Epiphone electric with flatwounds, direct, clean",
                    {"smp-atk": 0.001, "smp-rel": 0.1, "smp-vel": 0.5}),
}

KEEP = {"sample", "key", "lokey", "hikey", "pitch_keycenter", "lovel", "hivel", "tune", "transpose",
        "volume", "pan", "loop_mode", "loop_start", "loop_end", "trigger", "rt_decay"}
NAMES = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def keynum(v):
    """An SFZ key: a number or a name like c#4 / eb2 (c4 = 60)."""
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    m = re.fullmatch(r"([a-gA-G])([#b]?)(-?\d+)", v)
    if not m:
        return None
    acc = {"#": 1, "b": -1}.get(m.group(2), 0)
    return (int(m.group(3)) + 1) * 12 + NAMES[m.group(1).lower()] + acc


def parse(path):
    """Fully resolved regions of an SFZ file (with #include and #define)."""
    defines = {}

    def text_of(p):
        out = []
        for line in open(p, encoding="utf-8", errors="replace"):
            line = line.split("//")[0]
            m = re.match(r'\s*#include\s+"([^"]+)"', line)
            if m:
                out.append(text_of(os.path.join(os.path.dirname(p), m.group(1).replace("\\", "/"))))
                continue
            m = re.match(r"\s*#define\s+(\$\w+)\s+(\S+)", line)
            if m:
                defines[m.group(1)] = m.group(2)
                continue
            out.append(line)
        return "\n".join(out)

    text = text_of(path)
    for k, v in defines.items():
        text = text.replace(k, v)
    levels = {"control": {}, "global": {}, "master": {}, "group": {}}
    order = ["global", "master", "group"]
    regions, cur, region = [], None, None

    def flush():
        if region is not None:
            r = {}
            for lv in order:
                r.update(levels[lv])
            r.update(region)
            regions.append(r)

    # opcode values may hold spaces only for sample=, which runs to the next opcode
    for tok in re.finditer(r"<(\w+)>|(\w+)=((?:(?!\s+\w+=|\s*<).)*)", text, re.S):
        if tok.group(1):
            flush()
            region = None
            cur = tok.group(1)
            if cur == "region":
                region = {}
            elif cur in levels:
                levels[cur] = {}
                for lv in order[order.index(cur) + 1:] if cur in order else []:
                    levels[lv] = {}
            continue
        k, v = tok.group(2), tok.group(3).strip()
        if cur == "region":
            region[k] = v
        elif cur in levels:
            levels[cur][k] = v
    flush()
    dp = levels["control"].get("default_path", "").replace("\\", "/")
    for r in regions:
        r["sample"] = dp + r.get("sample", "").replace("\\", "/")
    return regions


def convert(name, root, programs, keys):
    regions = []
    for p in programs:
        src = os.path.join(root, p)
        for r in parse(src):
            if r.get("trigger", "attack") not in ("attack", "release"):
                continue
            if any(k.startswith(("locc", "hicc", "on_locc", "on_hicc", "sw_")) for k in r):
                continue    # keyswitched or CC-gated variants
            lo = keynum(r.get("lokey", r.get("key", "0")))
            hi = keynum(r.get("hikey", r.get("key", "127")))
            if lo is None or hi is None or hi < keys[0] or lo > keys[1]:
                continue
            r["lokey"], r["hikey"] = str(max(lo, keys[0])), str(min(hi, keys[1]))
            r.pop("key", None)
            if "pitch_keycenter" not in r:
                r["pitch_keycenter"] = str(lo)
            r["_src"] = os.path.dirname(src)
            regions.append(r)

    # random round robins → sequence positions within each key/velocity cell
    def cell(r):
        return (r["lokey"], r["hikey"], r.get("lovel", "0"), r.get("hivel", "127"), r.get("trigger", "attack"))

    cells = {}
    for r in regions:
        cells.setdefault(cell(r), []).append(r)
    rr_cap = max(len(v) for v in cells.values())
    while sum(min(len(v), rr_cap) for v in cells.values()) > MAX_ZONES and rr_cap > 1:
        rr_cap -= 1
    drop_release = sum(min(len(v), rr_cap) for v in cells.values()) > MAX_ZONES
    out = []
    for c, rs in cells.items():
        if drop_release and c[4] == "release":
            continue
        rs = sorted(rs, key=lambda r: float(r.get("lorand", 0)))[:rr_cap]
        for i, r in enumerate(rs):
            if len(rs) > 1:
                r["seq_length"], r["seq_position"] = str(len(rs)), str(i + 1)
            out.append(r)
    return out[:MAX_ZONES]


def write(path, title, regions):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [f"// {title}", "// Karoryfer Samples (CC0) - flattened for Slab by tools/library/karoryfer.py", ""]
    for r in regions:
        rel = os.path.relpath(os.path.join(r["_src"], r["sample"]), os.path.dirname(path))
        ops = [f"{k}={v}" for k, v in r.items() if k in KEEP - {"sample"} or k in ("seq_length", "seq_position")]
        lines.append("<region> " + " ".join(ops) + f" sample={rel}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def fetch(repo, root):
    """The repository's archive at its pinned commit, unpacked into root.
    A finished zip is kept until it unpacks, so a rerun picks up there."""
    url = f"https://github.com/sfzinstruments/{repo}/archive/{COMMITS[repo]}.zip"
    zpath = root + ".zip"
    if not os.path.exists(zpath):
        print(f"  {repo}: downloading", flush=True)
        with urllib.request.urlopen(url) as r, open(zpath + ".part", "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
        os.replace(zpath + ".part", zpath)
    tmp = root + ".unpack"
    shutil.rmtree(tmp, ignore_errors=True)
    with zipfile.ZipFile(zpath) as z:
        z.extractall(tmp)
    (top,) = os.listdir(tmp)
    os.replace(os.path.join(tmp, top), root)
    shutil.rmtree(tmp)
    os.remove(zpath)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-fetch", action="store_true", help="use what's on disk")
    args = ap.parse_args()
    base = os.path.join(library_root(), "karoryfer")
    os.makedirs(base, exist_ok=True)
    for name, (repo, programs, keys, note, params) in PROGRAMS.items():
        root = os.path.join(base, repo)
        if not os.path.isdir(root):
            if args.no_fetch:
                print(f"  {name}: {repo} not on disk")
                continue
            fetch(repo, root)
        regions = convert(name, root, programs, keys)
        missing = [r for r in regions if not os.path.exists(os.path.join(r["_src"], r["sample"]))]
        if missing:
            print(f"  {name}: {len(missing)} samples missing, e.g. {missing[0]['sample']}")
        sfz = os.path.join(base, "slab", name + ".sfz")
        write(sfz, note, regions)
        p = {"smp-model": 0, "smp-engine": 0, "smp-loop": 1, "smp-sus": 1.0, "smp-level": 0.7}
        p.update(params)
        write_preset("karoryfer", name, note + " (Karoryfer, CC0)", f"lib:karoryfer/slab/{name}.sfz", p,
                     pack="karoryfer")
        print(f"  {name}: {len(regions)} zones")
    with open(os.path.join(base, "README.txt"), "w") as fh:
        fh.write("Karoryfer Samples instruments, CC0 1.0 / public domain, from github.com/sfzinstruments.\n"
                 "Each karoryfer.* folder is the published repository; slab/ holds SFZ flattened for\n"
                 "Slab's sampler by tools/library/karoryfer.py.\n")
    json.dumps({})


if __name__ == "__main__":
    main()
