# Compteur de repetitions par accelerometre

Reference Python (`repcounter2.py`) du module Monkey C `watch/source/RepCounter.mc`, avec son evaluation sur
des donnees reelles de montre.

## Algorithme

Entree : accelerometre du poignet a 25 Hz (`Sensor.registerSensorDataListener`, blocs d'une seconde, milli-g).

1. **Gravite** retiree par un passe-haut lent (moyenne glissante exponentielle, constante 1,5 s), axe par axe.
2. **Lissage** passe-bas (constante 0,4 s) : on ne garde que le mouvement lent d'une repetition.
3. **Cycles** par axe : detection pic / creux avec hysteresis adaptative (50 % de l'amplitude recente, minimum
   80 milli-g), duree minimale d'un cycle 0,8 s, duree maximale 8 s (au-dela : repos), et filtrage des
   demi-cycles (un cycle plus court que la moitie de la periode apprise est ignore : supprime le double pic
   des fentes ou des pompes). **Chauffe** : le comptage ne demarre qu'apres deux cycles consecutifs de duree
   coherente, comptes retroactivement (aucun faux depart sur 5 minutes de bruit de repos simule, contre 14
   sans cette regle).
4. **Choix de l'axe** : celui dont les cycles sont les plus reguliers (nombre de cycles a +/-35 % de la duree
   mediane), a egalite le plus ample. Rend le comptage independant de l'orientation de la montre.
5. **Fin de serie** (START) : le cycle entame mais non referme compte pour une repetition.

Idee de depart : RecoFit (Morris et Saponas, CHI 2014), qui obtient +/-1 repetition dans 93 % des series avec
un capteur de bras et un traitement hors ligne (autocorrelation). Ici tout tourne en temps reel sur la montre,
sans FFT ni tampon long.

## Evaluation sur MM-Fit

Jeu de donnees MM-Fit (Strömbäck, Huang, Radu, IMWUT 2020) : montre TicWatch Pro au poignet gauche, 100 Hz,
10 exercices, series de 10 repetitions annotees a la video. Reechantillonne a 25 Hz comme sur la montre.
Reglage des parametres sur 5 seances (143 series), verification sur 6 autres seances (181 series) que
l'algorithme n'avait jamais vues.

Resultats (`eval_mmfit.py`, `sweep.py`) :

| Jeu | Series | +/-1 rep | Exact | Erreur moyenne |
| --- | --- | --- | --- | --- |
| reglage (w00 a w04) | 143 | 76 % | 53 % | 1,36 |
| test independant (w05 a w10) | 181 | 75 % | 43 % | 1,48 |
| test independant sans les curls | 164 | 82 % | 48 % | 1,09 |

Sans la regle de chauffe et avec un seuil de 60 milli-g, on monte a 80 % (88 % sans curls) mais on compte
alors environ un faux mouvement par minute de repos bruite : la version embarquee privilegie l'absence de
faux departs (on ramasse les halteres avant de commencer). Par exercice sur le test independant, seuil 60 :
rows, squats, tricep extensions 18/18 ; shoulder press 17/18 ; jumping jacks 17/19 ; situps 15/18 ; lunges
14/18 ; lateral raises 14/19 (surcompte) ; pushups 13/18 (sous-compte) ; **bicep curls 0/17**.

Les curls ne sont pas un echec de detection : MM-Fit les fait en alternant les bras et compte les deux bras,
alors que la montre gauche ne voit qu'un bras sur deux. Les trois axes trouvent proprement 5 cycles de 3,5 s
pour 10 repetitions annotees en 17 s. Un exercice alterne compte donc la moitie des repetitions sur la
montre : l'utilisateur corrige avec UP / DOWN, ce qui fige le compteur.

Reproduire :

```
python tools/reps/test_synthetic.py                       # signaux de synthese, 7/7 a +/-1
python tools/reps/fetch_mmfit.py <dossier>                # telecharge quelques seances par requetes Range (23 Mo)
python tools/reps/eval_mmfit.py <dossier>                 # evaluation, detail par serie
```

## Limites connues

* Exercices alternes (curl alterne, fentes alternees) : la montre compte le bras ou le cote qu'elle porte.
* Mouvements ou le poignet bouge peu (presse a cuisses, abdos sur machine) : peu de signal, compter a la main.
* Premiere repetition parfois manquee (seuil adaptatif en cours de calage), derniere rattrapee a START.
* Le comptage est un aide-memoire : la valeur affichee reste corrigeable et c'est elle qui part dans le lap
  de l'activite Garmin. Rien n'est ecrit dans Technogym au niveau de la serie (voir DECISIONS).
