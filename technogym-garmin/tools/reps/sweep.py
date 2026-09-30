import sys, itertools, glob, os, csv, bisect
from eval_mmfit import load_npy
from repcounter2 import count2 as count
folder = sys.argv[1]
# precharge les series : (w, ex, reps, xs, ys, zs)
sets = []
for lab in sorted(glob.glob(os.path.join(folder, "w*_labels.csv"))):
    w = os.path.basename(lab)[:3]; acc = load_npy(os.path.join(folder, f"{w}_sw_l_acc.npy")); frames = [r[0] for r in acc]
    for row in csv.reader(open(lab)):
        f0, f1, reps, ex = int(row[0]), int(row[1]), int(row[2]), row[3]
        seg = acc[bisect.bisect_left(frames, f0):bisect.bisect_right(frames, f1)]
        if len(seg) < 100: continue
        xs, ys, zs = [], [], []
        for k in range(0, len(seg) - 3, 4):
            blk = seg[k:k + 4]
            xs.append(int(sum(r[2] for r in blk) / 4 * 1000 / 9.81)); ys.append(int(sum(r[3] for r in blk) / 4 * 1000 / 9.81)); zs.append(int(sum(r[4] for r in blk) / 4 * 1000 / 9.81))
        sets.append((w, ex, reps, xs, ys, zs))
train = [s for s in sets if s[0] in ("w00", "w01", "w02")]; test = [s for s in sets if s[0] not in ("w00", "w01", "w02")]
print("series train", len(train), "test", len(test))
def score(subset, **kw):
    ok = 0; err = 0
    for w, ex, reps, xs, ys, zs in subset:
        got = count(xs, ys, zs, **kw); ok += abs(got - reps) <= 1; err += abs(got - reps)
    return ok / len(subset), err / len(subset)
grid = dict(gravity_tau=[1.5, 3.0, 6.0, 12.0], smooth_tau=[0.2, 0.35, 0.5], hysteresis=[0.35, 0.5, 0.65], min_amplitude=[60, 120, 200], period_gate=[0.0, 0.5, 0.65], min_period=[0.8, 1.2])
keys = list(grid); best = []
for vals in itertools.product(*grid.values()):
    kw = dict(zip(keys, vals)); acc, err = score(train, **kw); best.append((acc, -err, kw))
best.sort(key=lambda t: (t[0], t[1]), reverse=True)
for acc, nerr, kw in best[:8]:
    tacc, terr = score(test, **kw)
    print(f"train {acc:.0%} err {-nerr:.2f} | test {tacc:.0%} err {terr:.2f} | {kw}")
