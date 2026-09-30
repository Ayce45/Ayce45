"""Evaluation du compteur sur MM-Fit (Strömbäck et al. 2020) : montre gauche, accelerometre 100 Hz
reechantillonne a 25 Hz et converti en milli-g, une serie annotee = (frame debut, frame fin, reps, exercice).
Usage : python eval_mmfit.py <dossier avec wXX_sw_l_acc.npy et wXX_labels.csv>"""
import sys, glob, os, struct, ast, csv
from collections import defaultdict
from repcounter2 import count2 as count

def load_npy(path):
    """Lecture .npy sans numpy (version 1.0 / 2.0, tableau float64 ou float32 C-contigu)."""
    with open(path, "rb") as f:
        magic = f.read(6); assert magic == b"\x93NUMPY"
        major, minor = f.read(1)[0], f.read(1)[0]
        hlen = struct.unpack("<H", f.read(2))[0] if major == 1 else struct.unpack("<I", f.read(4))[0]
        header = ast.literal_eval(f.read(hlen).decode("latin1"))
        shape = header["shape"]; descr = header["descr"]
        fmt = {"<f8": "d", "<f4": "f", "<i8": "q", "<i4": "i"}[descr]
        n = 1
        for s in shape: n *= s
        data = struct.unpack("<" + fmt * n, f.read(n * struct.calcsize(fmt)))
    rows = shape[0]; cols = shape[1] if len(shape) > 1 else 1
    return [data[i * cols:(i + 1) * cols] for i in range(rows)]

def evaluate(folder, verbose=True):
    results = []
    for lab in sorted(glob.glob(os.path.join(folder, "w*_labels.csv"))):
        w = os.path.basename(lab)[:3]
        acc_path = os.path.join(folder, f"{w}_sw_l_acc.npy")
        if not os.path.exists(acc_path): continue
        acc = load_npy(acc_path)          # colonnes : frame, timestamp, x, y, z (m/s2)
        frames = [r[0] for r in acc]
        # index rapide frame -> premiere ligne
        import bisect
        for row in csv.reader(open(lab)):
            f0, f1, reps, ex = int(row[0]), int(row[1]), int(row[2]), row[3]
            i0 = bisect.bisect_left(frames, f0); i1 = bisect.bisect_right(frames, f1)
            seg = acc[i0:i1]
            if len(seg) < 100: continue
            # 100 Hz -> 25 Hz (moyenne de 4), m/s2 -> milli-g
            xs, ys, zs = [], [], []
            for k in range(0, len(seg) - 3, 4):
                blk = seg[k:k + 4]
                xs.append(int(sum(r[2] for r in blk) / 4 * 1000 / 9.81))
                ys.append(int(sum(r[3] for r in blk) / 4 * 1000 / 9.81))
                zs.append(int(sum(r[4] for r in blk) / 4 * 1000 / 9.81))
            got = count(xs, ys, zs)
            results.append((w, ex, reps, got, len(xs) / 25))
    by_ex = defaultdict(list)
    for w, ex, reps, got, dur in results:
        by_ex[ex].append((reps, got))
        if verbose: print(f"{w} {ex:22} attendu={reps:3} compte={got:3} ({dur:5.1f} s) {'OK' if abs(reps-got)<=1 else 'KO'}")
    tot = len(results); ok1 = sum(1 for r in results if abs(r[2]-r[3]) <= 1); exact = sum(1 for r in results if r[2] == r[3])
    print(f"\n{tot} series : exact {exact/tot:.0%}, a +/-1 rep {ok1/tot:.0%}, erreur absolue moyenne {sum(abs(r[2]-r[3]) for r in results)/tot:.2f}")
    for ex, v in sorted(by_ex.items()):
        ok = sum(1 for a, b in v if abs(a-b) <= 1)
        print(f"  {ex:22} {ok}/{len(v)} a +/-1  (moy attendu {sum(a for a,_ in v)/len(v):.1f}, compte {sum(b for _,b in v)/len(v):.1f})")
    return results

if __name__ == "__main__":
    evaluate(sys.argv[1] if len(sys.argv) > 1 else ".")
