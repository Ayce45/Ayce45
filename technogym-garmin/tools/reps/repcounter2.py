"""Compteur de repetitions v2 : un detecteur de cycles par axe, et l'axe retenu est celui dont les cycles sont
les plus reguliers (pas le plus energique : sur les curls, l'axe le plus energique est une derive lente de
rotation du poignet, alors que l'axe utile bat proprement a chaque repetition).

Par axe : retrait de la gravite (passe-haut), lissage (passe-bas), cycles pic / creux avec hysteresis
adaptative, periode minimale, filtrage des demi-cycles (un cycle plus court que PERIOD_GATE x periode
apprise est ignore, ce qui supprime le double pic des fentes ou des pompes).
Score de regularite d'un axe : nombre de cycles recents dont la duree est a +/-35 % de la duree mediane.
Le nombre de repetitions affiche est celui de l'axe au meilleur score (a egalite, le plus ample).
Meme code que watch/source/RepCounter.mc."""

from __future__ import annotations

RATE = 25


class AxisCounter:
    def __init__(self, min_period=0.8, max_period=8.0, smooth_tau=0.4, min_amplitude=80.0, hysteresis=0.5, period_gate=0.5, warmup=2):
        self.min_period = min_period; self.max_period = max_period
        self.al = 1.0 / (1.0 + smooth_tau * RATE)
        self.min_amplitude = min_amplitude; self.hysteresis = hysteresis; self.period_gate = period_gate
        self.reps = 0; self.lp = 0.0; self.state = 0; self.peak = 0.0; self.valley = 0.0
        self.amp = 0.0; self.period = 0.0; self.last_t = -1e9; self.dts: list[float] = []
        self.warmup = warmup            # nb de cycles reguliers consecutifs requis avant de compter (anti faux departs)
        self.candidates = 0             # cycles vus mais pas encore comptes (phase de chauffe)
        self.armed = warmup == 0

    def push(self, m: float, t: float) -> None:
        self.lp += self.al * (m - self.lp)
        v = self.lp
        thr = max(self.min_amplitude, self.hysteresis * self.amp)
        if self.state == 0:
            if v > self.peak: self.peak = v
            if self.peak - v > thr * 0.5 and self.peak > self.valley + thr:
                self.state = 1; self.valley = v
        else:
            if v < self.valley: self.valley = v
            if v - self.valley > thr * 0.5 and self.peak - self.valley > thr:
                dt = t - self.last_t
                amp = self.peak - self.valley
                gated = self.period > 0 and dt < self.period_gate * self.period
                if dt >= self.min_period and not gated:
                    if dt <= self.max_period or self.last_t < 0:
                        if self.armed:
                            self.reps += 1
                        else:
                            # chauffe : on attend `warmup` cycles consecutifs de periode coherente
                            ok = self.last_t > 0 and dt <= self.max_period and (self.period == 0 or abs(dt - self.period) <= 0.5 * self.period)
                            self.candidates = self.candidates + 1 if (ok or self.last_t < 0) else 1
                            if self.candidates >= self.warmup:
                                self.armed = True
                                self.reps = self.candidates
                        if self.last_t > 0 and dt <= self.max_period:
                            self.dts.append(dt)
                            if len(self.dts) > 12: self.dts.pop(0)
                            self.period = dt if self.period == 0 else 0.6 * self.period + 0.4 * dt
                    else:
                        # tres long silence : on repart en chauffe
                        if self.warmup and not self.armed: self.candidates = 0
                    self.amp = amp if self.amp == 0 else 0.7 * self.amp + 0.3 * amp
                    self.last_t = t
                self.state = 0; self.peak = v

    def pending(self) -> int:
        """Cycle entame mais pas referme a la fin de la serie (derniere repetition) : 1 s'il est plausible."""
        thr = max(self.min_amplitude, self.hysteresis * self.amp)
        if self.armed and self.state == 1 and self.peak - self.valley > thr:
            return 1
        return 0

    def regularity(self) -> int:
        if len(self.dts) < 2: return len(self.dts)
        s = sorted(self.dts); med = s[len(s) // 2]
        return sum(1 for d in self.dts if abs(d - med) <= 0.35 * med)


class RepCounter2:
    def __init__(self, gravity_tau=1.5, **axis_kw):
        self.ag = 1.0 / (1.0 + gravity_tau * RATE)
        self.g = None; self.n = 0
        self.axes = [AxisCounter(**axis_kw) for _ in range(3)]
        self.best = 0

    def feed(self, xs, ys, zs) -> int:
        for x, y, z in zip(xs, ys, zs):
            self.n += 1; t = self.n / RATE
            if self.g is None: self.g = [float(x), float(y), float(z)]
            for i, v in enumerate((x, y, z)):
                self.g[i] += self.ag * (v - self.g[i])
                self.axes[i].push(v - self.g[i], t)
        # choix de l'axe : regularite, puis amplitude
        scores = [(a.regularity(), a.amp, i) for i, a in enumerate(self.axes)]
        scores.sort(reverse=True)
        self.best = scores[0][2]
        return self.reps

    @property
    def reps(self) -> int:
        return self.axes[self.best].reps

    def final(self) -> int:
        """Nombre de repetitions a la fin de la serie, en comptant la derniere si elle est entamee."""
        a = self.axes[self.best]
        return a.reps + a.pending()


def count2(xs, ys, zs, **kw) -> int:
    c = RepCounter2(**kw)
    for i in range(0, len(xs), RATE):
        c.feed(xs[i:i + RATE], ys[i:i + RATE], zs[i:i + RATE])
    return c.final()
