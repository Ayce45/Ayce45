# POC : lire une seance Technogym en direct, sans toucher aux machines

Question : quand je m'entraine sur les machines de la salle, puis-je recuperer en direct, depuis mon
compte Mywellness, ce que les machines enregistrent (exercice en cours, exercices termines, series,
charges) pour l'afficher sur la montre ?

Reponse courte : **oui, a l'echelle de l'exercice.** Chaque machine envoie au cloud Technogym le debut
et la fin de chaque exercice (avec ses series reelles) ; l'app mobile Mywellness ne fait rien d'autre
qu'interroger ce cloud. Le backend de ce projet lit exactement les memes donnees avec le compte
utilisateur. Ce qui n'existe pas cote cloud : le detail serie par serie pendant l'exercice (il arrive
d'un bloc a la fin de l'exercice).

## 1. Ce que l'app mobile fait vraiment (analyse de l'APK Mywellness 6.7.12)

APK `com.technogym.mywellness` (aptoide, md5 `22094891ce6c8b53e443433162e51a2d`), 4 fichiers dex,
129 054 chaines, analyse avec androguard (chaines, references croisees, decompilation ciblee).

**Comment l'app apprend qu'un exercice a ete fait sur une machine : par notification push.**
L'enum `PushNotificationTopics` liste les evenements que le cloud Technogym pousse au telephone
(OneSignal / Firebase). Ceux qui concernent la seance en salle :

| Topic push | Sens |
| --- | --- |
| `LoginDoneOnEquipment` | l'utilisateur s'est identifie sur une machine (badge NFC, QR, app) |
| `StartWorkoutSession` | une seance performee est ouverte (machine, kiosque Unity Self ou app) |
| `StartExerciseOnEquipment` | un exercice demarre sur une machine |
| `EndExerciseOnEquipment` | l'exercice se termine sur la machine |
| `ExerciseDoneOnEquipment` | l'exercice est enregistre (series, charges) dans la seance |
| `ExercisesHasBeenSaved` | des exercices ont ete sauvegardes |
| `CloseWorkoutSession` | la seance est fermee |

A la reception, l'ecran d'accueil (`CurrentWorkoutFragment`) recoit l'evenement
`RefreshCurrentWorkout` et recharge la seance courante. Sans push, il ne recharge que toutes les
10 minutes (`CurrentWorkoutLastUpdate` + 10 min, methode `c0`) ou au retour au premier plan.

**Ce qu'il appelle pour recharger** (decompilation de `tk.g.i`) :
`POST services.mywellness.com/{facilityUrl}/Training/User/{userId}/GetCurrentWorkoutSession`,
c'est a dire la meme action que celle utilisee par ce projet. Le client "workout" de l'app appelle
aussi `GET https://workout.mywellness.com/v2/enduser/workout/current` (modele
`CurrentWorkoutSession(hasCurrentWorkout=...)`), verifie sur le compte : `{"hasCurrentWorkout": false}`
hors seance, avec le meme jeton Bearer et les en-tetes `X-MWAPPS`.

**Ce que l'app ne fait pas** : aucun canal temps reel vers les machines. SignalR n'est utilise que
pour la messagerie avec le coach (`RealTimeMessenger`). Le Bluetooth sert au capteur cardio
(`BleHeartRateService`) et a la connexion a certains equipements (`EquipmentConnectionService`, scan
BLE) ; le NFC HCE (`UnityNfcHceService`) sert a se connecter sur la console Unity. Rien de tout cela
n'est necessaire pour lire les resultats : ils transitent par le cloud.

Consequence pour nous : on ne recoit pas les push OneSignal (ils sont adresses a l'app), mais on peut
interroger le cloud a la frequence voulue. Le poll de 15 a 20 s du backend / de la montre fait le meme
travail que le push, avec au plus 20 s de retard.

## 2. Ce que le cloud expose pendant une seance (verifie sur le compte)

Seance du 2026-09-29 (Seance 3, faite en salle, sans aucune intervention de ce projet) relue avec
`scripts/poc_live.py --once --day 2026-09-29` :

```
seance du jour idCr=1146 Programme ... - Seance 3 debut=2026-09-29 15:22:31 +02:00 fermee='2026-09-29' faits=5/6
   pos 1 Exercice Personnalise par temps : Done fait a 15:38:26 via VisioWow
   pos 2 Exercice avec objectif temps     : Done fait a 15:56:35 via UnityCoach
   pos 3 Leg press Sel                    : ToDo
   pos 4 Flexion du buste                 : Done fait a 16:06:38 via UnityStrength  [{IsoReps 15, IsoWeight 40} x4]
   pos 5 Obliques debout                  : Done fait a 16:15:43 via UnitySelf      [{Duration 30}]
   pos 6 Position de l'enfant             : Done fait a 16:15:45 via UnitySelf      [{Duration 30}]
```

Lecture :

* la seance performee (`idCr`) est creee a l'ouverture (15:22, kiosque `UnitySelf`) : elle apparait
  dans `ActivityHistory` du jour des ce moment, avant tout exercice ;
* chaque exercice porte l'heure de fin `doneOn` et la console d'origine (`mwc_client_application` :
  `VisioWow` = console du velo, `UnityCoach` = console du Climb, `UnityStrength` = console de la machine
  de musculation, `UnitySelf` = kiosque / app) : l'entree est ecrite par la machine a la fin de
  l'exercice, pas a la fermeture de la seance ;
* pour la musculation, les series reelles (reps, charge) sont dans `performedPhysicalActivity.data.steps` ;
* pour le cardio, les series sont vides mais `CardioLog/{analyticsId}/Details` donne les courbes par
  seconde (682 echantillons Power / Rpm / HDistance pour le velo) des la fin de l'exercice ;
* un exercice non fait reste `ToDo` : la montre sait qu'il reste a faire (poids libres par exemple).

## 3. Le POC

`scripts/poc_live.py` (lecture seule) interroge toutes les 15 s :

1. `GetCurrentWorkoutSession` et `workout/current` : une seance est-elle ouverte ;
2. `ActivityHistory` du jour : l'`idCr` de la seance performee ;
3. `GetPerformedWorkoutSessionByIdCr` : statut et series de chaque exercice ;

et affiche uniquement les changements (`NOUVELLE seance`, `exercice pos 4 : ToDo -> Done via
UnityStrength series=[...]`, `seance fermee`). Journal complet dans `scratch/poc_live_log.jsonl`.

```
python scripts/poc_live.py                 # a lancer sur le telephone / PC pendant la seance
python scripts/poc_live.py --once --day 2026-09-29   # rejeu d'une seance passee
```

Le backend fait la meme chose pour la montre : `GET /workout/{id}/live` (service `app/mywellness/live.py`,
cache 15 s), interroge par l'app Connect IQ au demarrage, a chaque ecran de serie et toutes les 20 s.

## 4. Resultats de la seance test du 2026-09-30 (a blanc, depuis le telephone)

Poll toutes les 10 s, heures locales (Europe/Paris) :

| Evenement | Heure cote Technogym | Vu par le poll | Latence |
| --- | --- | --- | --- |
| Seance 2 ouverte depuis l'app (`TgAppAndroidCoach`, contexte salle) | 10:05:31 | 10:05:40 | 9 s |
| Exercice 7 (poulie, `Offline`) valide dans l'app, 4 x 10 x 12,5 kg | 10:08:03 | 10:08:14 | 11 s |
| Exercices 8 et 9 valides dans l'app | 10:08:4x | 10:08:51 | < 10 s |
| Exercice 4 marque fait **par le backend** (`MarkPhysicalActivityAsDone`) | 10:10:41 | 10:10:45 | 4 s |
| Exercice 2 marque fait par le backend | 10:11:4x | 10:11:49 | < 10 s |

Observations :

* `GetCurrentWorkoutSession` renvoie, pendant la seance, la seance complete : `idCr`, `startedOn`, et
  pour chaque exercice `executionStatus` (ToDo / Done), `doneOn`, `doneMove`, `doneCalories`,
  `doneDuration`, `equipmentConnectedDevice` (`FullConnected` = machine en reseau, `Offline` = poulie,
  etirement, poids libres), les `steps` prescrits et `currentReferenceValues` (Rm1, Vo2Max estimes).
  La seance performee n'apparait dans `ActivityHistory` qu'apres le premier exercice fait.
* Le sens montre -> Technogym fonctionne : `MarkPhysicalActivityAsDone {position, userWorkoutSessionId,
  idCr, partitionDate}` a marque deux exercices faits dans la seance ouverte, avec les series prescrites,
  `manuallyDone: true`, client `EndUserWebSite`, visibles dans l'app. `SavePerformedPhysicalActivity`
  (series reelles differentes de la prescription) exige `summaryData.stepData` et des proprietes
  `{"name", "um", "value"}` ; le format des pas reste a trouver (`ExerciseDataNotValid`).
* Le backend `/workout/{id}/live` utilise desormais la seance courante en priorite (avant meme l'historique).

## 5. POC montre : l'ecran live (2026-09-30)

But : je gere ma seance avec les bornes, les machines et l'app ; ma montre me montre ou j'en suis et
enregistre l'activite (frequence cardiaque). Realise dans `watch/` (app Connect IQ "TG Live", ecran
`LiveView`, module `Live`) et teste dans le simulateur fr965 contre le backend :

* backend : `GET /live` renvoie la seance courante Technogym (`GetCurrentWorkoutSession`) sous forme
  simplifiee : `name`, `done_count / total_count`, `current_position`, et par exercice `status`
  (todo / doing / done), `device` (`FullConnected` = machine en reseau), `source` (machine / manual),
  `target_sets` (prescrit) et `sets` (fait), `done_on`. Cache 15 s cote backend.
* montre : poll toutes les 10 s, affichage exercice courant + series + FC, vibration et lap FIT quand un
  exercice passe a "fait", envoi des echantillons cardio toutes les 30 s (`POST /live/hr`).
* test : la seance a blanc du matin (journal `scratch/poc_live_log.jsonl`, 68 captures reelles de
  `GetCurrentWorkoutSession`) a ete rejouee par le backend (`LIVE_REPLAY_PATH`, une capture toutes les
  4 s), donnees cardio simulees par le simulateur (Simulation > Activity Data). Resultat : ouverture de
  seance detectee, 5 exercices passes a "fait" avec vibration, series reelles affichees
  (`4 x 10 x 12.5 kg` pour la poulie validee dans l'app, `4 x 10 x 35 kg` pour un exercice marque par le
  backend), 458 echantillons cardio (135 a 162 bpm) stockes dans `hr_samples` en 7 min 37 s.
  Captures : `docs/screenshots/14-live-exercice-courant.png`, `15-live-fait-machine.png`, `16-live-fait-app.png`.

Ouvrir la seance depuis la montre : pas encore possible. `StartWorkoutSession` (Training/User) repond
`{"notFound": true}` pour les trois seances du programme, quelle que soit la salle ou le corps envoye ; la
decompilation montre que l'app n'appelle jamais cette action (seul l'adaptateur JSON existe), elle ouvre
la seance par un autre chemin (kiosque, machine, ou API "workout") qui reste a trouver. En attendant, la
seance s'ouvre depuis la borne, une machine ou l'app, et la montre la detecte en moins de 10 s.

## 6. Verifie / pas verifie

| | Etat |
| --- | --- |
| Les machines ecrivent chaque exercice dans le cloud a la fin de l'exercice, avec series et charges | **verifie** (horodatages `doneOn` et consoles d'origine de la seance du 29/09) |
| L'app mobile lit ces donnees par `GetCurrentWorkoutSession` et se rafraichit sur push | **verifie** (decompilation) |
| Le backend lit les memes donnees avec le compte utilisateur | **verifie** (`poc_live.py`, `/workout/{id}/live`) |
| Latence app / backend -> cloud -> poll | **mesuree** : 4 a 11 s avec un poll de 10 s |
| Latence machine connectee -> cloud | **a mesurer** en salle (la seance test etait a blanc, sans machine) |
| Contenu de `GetCurrentWorkoutSession` pendant une seance ouverte | **verifie** (seance test du 30/09 : statut, doneOn, type de connexion, series prescrites par exercice) |
| Ecriture montre -> Technogym (exercice marque fait) | **verifie** (`MarkPhysicalActivityAsDone`, 4 s de latence) |
| Ecriture de series reelles differentes de la prescription | **schema connu** (decompile de l'app : `steps[].stepData` en `{name, um, value}`), ecriture reelle a valider avec `scripts/test_writeback.py --mode save` |
| Frequence cardiaque par exercice vers Technogym | **schema connu** (`analitics.hr: [{t, hr}]`), a valider de la meme facon ; l'affichage en direct sur la console reste reserve a la diffusion systeme de la montre |
| Detail serie par serie pendant l'exercice | **non disponible** cote cloud (les series arrivent avec `ExerciseDoneOnEquipment`) |
| Ecran live sur la montre (exercice courant, faits / a faire, series, FC) | **verifie** en simulateur sur rejeu de la seance reelle du 30/09 (section 5) |
| Frequence cardiaque montre -> backend | **verifie** (`POST /live/hr`, 458 echantillons stockes) ; ecriture dans Technogym a faire |
| Ouvrir la seance depuis la montre | **non** : `StartWorkoutSession` repond `notFound`, chemin de l'app a trouver |

Prochaine seance en salle : lancer `python scripts/poc_live.py` avant de badger sur la premiere
machine et me transmettre `scratch/poc_live_log.jsonl`. Il contiendra la forme exacte de la seance
courante et la latence reelle, ce qui permettra d'affiner l'ecran "Machine : fait" de la montre
(par exemple afficher l'exercice en cours des `StartExerciseOnEquipment`).
