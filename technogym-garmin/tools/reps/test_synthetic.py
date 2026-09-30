"""Validation du compteur sur des signaux de synthese : repetitions sinusoidales bruitees, orientation
quelconque de la montre, pauses, tremblements. Chaque cas donne le nombre attendu et le nombre compte."""
import math, random
from repcounter2 import count2 as count

random.seed(7)
RATE = 25

def synth(n_reps, period, amp=400, noise=40, axis=(0.2, 0.9, 0.4), gravity=(300, -900, 200), pause_before=3.0, pause_after=3.0, tremor=0.0):
    xs, ys, zs = [], [], []
    norm = math.sqrt(sum(a * a for a in axis)); axis = [a / norm for a in axis]
    total = pause_before + n_reps * period + pause_after
    for i in range(int(total * RATE)):
        t = i / RATE
        s = 0.0
        if pause_before <= t < pause_before + n_reps * period:
            s = amp * math.sin(2 * math.pi * (t - pause_before) / period)
            s += tremor * math.sin(2 * math.pi * 7.0 * t)  # tremblement 7 Hz
        for arr, g, a in zip((xs, ys, zs), gravity, axis):
            arr.append(int(g + a * s + random.gauss(0, noise)))
    return xs, ys, zs

cases = [
    ("10 reps lentes (3 s)", synth(10, 3.0), 10),
    ("10 reps rapides (1.2 s)", synth(10, 1.2), 10),
    ("8 reps, montre tournee", synth(8, 2.0, axis=(0.9, 0.1, -0.3), gravity=(-950, 100, 250)), 8),
    ("12 reps, bruit fort", synth(12, 2.0, noise=120), 12),
    ("6 reps avec tremblement", synth(6, 2.5, tremor=150), 6),
    ("0 rep, repos bruite", synth(0, 2.0, pause_before=15, noise=80), 0),
    ("5 reps petite amplitude (200 mg)", synth(5, 2.0, amp=200), 5),
]
ok = 0
for name, (xs, ys, zs), expected in cases:
    got = count(xs, ys, zs)
    good = abs(got - expected) <= 1
    ok += good
    print(f"{'OK ' if good else 'KO '} {name:36} attendu={expected:3} compte={got:3}")
print(f"{ok}/{len(cases)} cas a +/-1 rep")
