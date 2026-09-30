"""Chargement des series MM-Fit (montre gauche, 100 Hz -> 25 Hz, m/s2 -> milli-g)."""
import glob, os, csv, bisect
from eval_mmfit import load_npy

def load_sets(folder):
    sets = []
    for lab in sorted(glob.glob(os.path.join(folder, "w*_labels.csv"))):
        w = os.path.basename(lab)[:3]; p = os.path.join(folder, f"{w}_sw_l_acc.npy")
        if not os.path.exists(p): continue
        acc = load_npy(p); frames = [r[0] for r in acc]
        for row in csv.reader(open(lab)):
            f0, f1, reps, ex = int(row[0]), int(row[1]), int(row[2]), row[3]
            seg = acc[bisect.bisect_left(frames, f0):bisect.bisect_right(frames, f1)]
            if len(seg) < 100: continue
            xs, ys, zs = [], [], []
            for k in range(0, len(seg) - 3, 4):
                blk = seg[k:k + 4]
                xs.append(int(sum(r[2] for r in blk) / 4 * 1000 / 9.81)); ys.append(int(sum(r[3] for r in blk) / 4 * 1000 / 9.81)); zs.append(int(sum(r[4] for r in blk) / 4 * 1000 / 9.81))
            sets.append((w, ex, reps, xs, ys, zs))
    return sets

def score(subset, **kw):
    from repcounter2 import count2 as count
    ok = 0; err = 0
    for w, ex, reps, xs, ys, zs in subset:
        got = count(xs, ys, zs, **kw); ok += abs(got - reps) <= 1; err += abs(got - reps)
    return ok / len(subset), err / len(subset)
