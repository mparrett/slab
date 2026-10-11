#!/usr/bin/env python3
"""Measure a plucked-string note: what the waveguide voice is fitted to.

For one WAV holding one note it reports
  * f0 and the inharmonicity B [f_n = n f0 sqrt(1 + B n^2)], fitted to the
    partial peaks of the first second,
  * each harmonic's T60, from a line fitted to its dB envelope after the
    attack, down to 40 dB below its start or the noise floor,
  * the attack spectrum: each harmonic's level 20-80 ms in, relative to
    the strongest.

    python3 tools/fit/string_fit.py note.wav --hz 73.42 [--start 0.0] [--n 24]
    python3 tools/fit/string_fit.py a.wav b.wav --hz 73.42   # side by side
    python3 tools/fit/string_fit.py song.wav --hz 36.71 --start 8 --dur 7

numpy only.  Reads 16/24/32-bit PCM and 32-bit float WAV.
"""
import argparse
import struct

import numpy as np


def read_wav(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"RIFF":
        raise SystemExit(f"{path}: not RIFF")
    pos, fmt, raw = 12, None, None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
        elif cid == b"data":
            raw = body
        pos += 8 + size + (size & 1)
    tag, ch, sr, _, _, bits = fmt
    if tag == 3 or (tag == 0xFFFE and bits == 32 and False):
        x = np.frombuffer(raw, "<f4").astype(np.float64)
    elif bits == 16:
        x = np.frombuffer(raw, "<i2") / 32768.0
    elif bits == 24:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3)
        v = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        v = np.where(v >= 1 << 23, v - (1 << 24), v)
        x = v / float(1 << 23)
    elif bits == 32 and tag in (3, 0xFFFE):
        x = np.frombuffer(raw, "<f4").astype(np.float64)
    elif bits == 32:
        x = np.frombuffer(raw, "<i4") / float(1 << 31)
    else:
        raise SystemExit(f"{path}: {bits}-bit format {tag}")
    return x.reshape(-1, ch).mean(axis=1), sr


def peak_near(spec, freqs, f, width):
    lo, hi = np.searchsorted(freqs, [f - width, f + width])
    if hi <= lo:
        return f, -200.0
    k = lo + int(np.argmax(spec[lo:hi]))
    if 0 < k < len(spec) - 1:  # parabolic interpolation in dB
        a, b, c = spec[k - 1], spec[k], spec[k + 1]
        d = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) != 0 else 0.0
        return freqs[k] + d * (freqs[1] - freqs[0]), b - 0.25 * (a - c) * d
    return freqs[k], spec[k]


def analyse(path, hz, start, nh, dur=None):
    x, sr = read_wav(path)
    x = x[int(start * sr):]
    if dur:
        x = x[:int(dur * sr)]
    onset = int(np.argmax(np.abs(x) > 0.05 * np.max(np.abs(x))))
    x = x[onset:]
    # partials over the first second, a long window for resolution
    seg = x[int(0.05 * sr):int(1.05 * sr)]
    win = np.hanning(len(seg))
    nfft = 1 << 20
    spec = 20 * np.log10(np.abs(np.fft.rfft(seg * win, nfft)) + 1e-12)
    freqs = np.fft.rfftfreq(nfft, 1 / sr)
    f1, _ = peak_near(spec, freqs, hz, hz * 0.06)
    peaks = []
    guess_b = 0.0
    for n in range(1, nh + 1):
        f = n * f1 * np.sqrt(1 + guess_b * n * n)
        fn, lv = peak_near(spec, freqs, f, f1 * 0.25)
        peaks.append((n, fn, lv))
        # refit B as we climb so the search window follows the stretch
        good = [(m, g) for m, g, l in peaks if l > spec.max() - 70]
        if len(good) >= 4:
            ms = np.array([m for m, _ in good], float)
            r = (np.array([g for _, g in good]) / (ms * f1)) ** 2 - 1
            guess_b = max(0.0, float(np.sum(r * ms * ms) / np.sum(ms ** 4)))
    good = [(m, g) for m, g, l in peaks if l > spec.max() - 60]
    ms = np.array([m for m, _ in good], float)
    r = (np.array([g for _, g in good]) / (ms * f1)) ** 2 - 1
    B = max(0.0, float(np.sum(r * ms * ms) / np.sum(ms ** 4))) if len(good) >= 4 else 0.0

    # per-harmonic envelopes from an STFT
    n_win = 1 << int(np.ceil(np.log2(4 * sr / f1)))
    hop = 256
    w = np.hanning(n_win)
    frames = range(0, max(1, len(x) - n_win), hop)
    fr = np.fft.rfftfreq(n_win, 1 / sr)
    env = np.zeros((nh, len(frames)))
    for j, i in enumerate(frames):
        s = np.abs(np.fft.rfft(x[i:i + n_win] * w))
        for n, fn, _ in peaks:
            k = int(round(fn / (fr[1] - fr[0])))
            env[n - 1, j] = 20 * np.log10(np.max(s[max(0, k - 2):k + 3]) + 1e-12)
    t = (np.arange(len(frames)) * hop + n_win / 2) / sr
    floor = np.percentile(env[:, -max(1, len(frames) // 10):], 50)
    rows = []
    top = env[:, (t > 0.02) & (t < 0.08)].max(axis=1) if np.any((t > 0.02) & (t < 0.08)) else env[:, 0]
    for n, fn, _ in peaks:
        e = env[n - 1]
        k0 = int(np.argmax(e[: max(1, np.searchsorted(t, 0.3))]))
        sel = (np.arange(len(e)) >= k0) & (e > e[k0] - 40) & (e > floor + 10)
        # stop at the first frame that leaves the band
        idx = np.nonzero(sel)[0]
        if len(idx) < 4:
            rows.append((n, fn, np.nan, top[n - 1]))
            continue
        run = idx[: np.argmax(np.diff(np.append(idx, idx[-1] + 2)) > 1) + 1]
        if len(run) < 4:
            rows.append((n, fn, np.nan, top[n - 1]))
            continue
        slope = np.polyfit(t[run], e[run], 1)[0]
        t60 = -60.0 / slope if slope < 0 else np.inf
        rows.append((n, fn, t60, top[n - 1]))
    return dict(path=path, sr=sr, f1=f1, B=B, rows=rows, peak=max(top))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("wav", nargs="+")
    ap.add_argument("--hz", type=float, required=True)
    ap.add_argument("--start", type=float, default=0.0, help="seconds to skip before looking for the onset")
    ap.add_argument("--dur", type=float, default=None, help="seconds to read after --start")
    ap.add_argument("--n", type=int, default=20, help="harmonics")
    a = ap.parse_args()
    res = [analyse(p, a.hz, a.start, a.n, a.dur) for p in a.wav]
    for r in res:
        print(f"{r['path']}: f0 {r['f1']:.2f} Hz  B {r['B']:.2e}")
    head = "  n " + "".join(f"| {'Hz':>7} {'T60 s':>6} {'att dB':>6} " for _ in res)
    print(head)
    for i in range(a.n):
        line = f"{i + 1:3d} "
        for r in res:
            n, fn, t60, lv = r["rows"][i]
            line += f"| {fn:7.1f} {t60:6.2f} {lv - r['peak']:6.1f} "
        print(line)


if __name__ == "__main__":
    main()
