# Technogym (Mywellness) vers Garmin

Deux produits, un backend commun :

1. **Appli de synchro.** Tu lances le backend, une page web te demande tes identifiants Technogym et
   Garmin, tu cliques : chaque seance de ton programme Mywellness devient un workout structure Garmin
   Connect (exercices, series, charges, repos), la seance du jour est planifiee sur le calendrier. Un job
   peut refaire ce push chaque matin a 6h.
2. **Compagnon de seance sur la montre (app Connect IQ "Spotter for Technogym").** Seance du jour sur la montre,
   guidage serie par serie (cible reps / charge, repos avec vibration, blocs cardio a duree), activite FIT
   Strength. Bidirectionnel via le backend : ce que tu fais sur les machines Technogym apparait sur la
   montre en cours de seance, et ce que tu saisis sur la montre (poids libres) est renvoye au backend puis,
   une fois active, ecrit dans Mywellness.

| Synchro | Montre |
| --- | --- |
| ![page synchro](docs/screenshots/11-page-synchro.png) | ![serie](docs/screenshots/05-serie-cible.png) ![live](docs/screenshots/12-live-machines.png) |

Captures reelles : page servie par le backend, simulateur Connect IQ (Forerunner 965) branche sur le
backend local et la vraie seance Mywellness. `[M]` = exercice deja enregistre par une machine Technogym.

## Securite des identifiants

* Aucun identifiant, mot de passe ou jeton n'est dans le depot : `.env`, `data/` (jetons Garmin,
  `credentials.json`, SQLite) et `watch/keys/` sont gitignores. Les fixtures de test sont des reponses
  reelles anonymisees (UUID renumerotes, noms retires).
* Les identifiants ne sont envoyes qu'a `core.mywellness.com` / `services.mywellness.com` et
  `sso.garmin.com` / `connectapi.garmin.com`.
* Le depot est public : ne mets jamais tes identifiants dans un fichier versionne. Pour effacer aussi
  l'historique des premiers commits (qui contiennent un id utilisateur Mywellness et un id de salle, non
  secrets) : `git rebase -i <commit de base>` puis squash, ou `git filter-repo`, puis `git push --force-with-lease`.

## 1. Appli de synchro

```
cd technogym-garmin
uv venv .venv && . .venv/bin/activate && uv pip install -e ".[dev]"   # ou pip install -e .
python run.py --open        # ouvre http://127.0.0.1:8000
```

Saisis les identifiants, coche "se souvenir" si tu veux qu'ils soient gardes sur cet ordinateur
(`data/credentials.json`, droits 600), clique **Synchroniser vers Garmin**. Resultat : un lien par workout
cree (`TG Seance 1`, `TG Seance 2`, ...), la seance du jour marquee "planifiee aujourd'hui", et les exercices
sans equivalent Garmin signales. Relancer la synchro remplace les workouts du meme nom.

Execution reelle du 2026-09-30 : 3 workouts crees en 22 s (Seance 1 : 39 steps, Seance 2 : 25, Seance 3 :
24), Seance 1 planifiee, aucun exercice sans correspondance.

Sans interface (serveur, Docker) : identifiants dans `.env` et `POST /garmin/push-today` ou le job
APScheduler (`PUSH_HOUR`, `TZ`).

## 2. Compagnon de seance sur la montre (app Connect IQ "Spotter for Technogym")

"Spotter for Technogym" est le nom de **notre** app (elle n'existe pas sur le store Connect IQ) ; elle apparait dans la
liste des activites de la montre comme n'importe quelle app et enregistre une activite Musculation.

**Mode live (par defaut, START sur l'accueil).** La seance est geree comme d'habitude depuis la salle
(bornes, machines, app Technogym) ; la montre se contente de montrer ou on en est et d'enregistrer
l'activite :

* chrono de seance, `faits / total` et arc de progression ;
* exercice courant (premier non fait cote Technogym) : nom, statut (`Connectee` = machine en reseau,
  `A faire`, `Fait`, `Fait machine`), series prescrites ou, une fois fait, series reelles remontees par la
  machine (`4 x 10 x 35 kg`) ; UP / DOWN pour parcourir les autres exercices, "Suivant : ..." en bas ;
* frequence cardiaque du poignet en grand (max en petit) : l'activite est enregistree, donc le capteur
  optique est actif et la **diffusion cardio** de la montre (reglage systeme "Diffuser pendant l'activite",
  ANT+ / Bluetooth) peut alimenter la console d'une machine Technogym qui accepte un capteur ;
* toutes les 10 s la montre relit `GET /live` (seance courante Technogym) ; quand une machine ou l'app
  valide un exercice, la montre vibre, affiche `<exercice> : fait` et pose un lap dans le FIT ;
* toutes les 30 s elle envoie ses echantillons cardio au backend (`POST /live/hr`), qui les stocke par
  seance (base pour les ecrire ensuite dans Technogym via `analitics.hr`) ;
* START : menu (actualiser, revenir a l'exercice en cours, mode guide, terminer et sauver, abandonner).

**Mode guide (menu de l'accueil).** Ancien parcours ou la montre dicte la seance prescrite : serie cible
`10 reps x 80 kg`, START = fait, saisie reps puis charge, repos avec vibration, blocs cardio / etirements en
compte a rebours, resume, sauvegarde FIT puis envoi des resultats (`POST /workout/{id}/results`, mise en
attente si hors ligne). Les exercices deja faits sur machine y apparaissent `[M]`.

Les textes de la montre reprennent le vocabulaire de l'app Technogym (séance d'entraînement, exercices,
équipement, MOVEs, "Terminé", "À faire") ; la fiche store prete a publier est dans `docs/store-listing.md`.

Captures (simulateurs fr965 et fr955, rejeu de la seance reelle du 2026-09-30) : `docs/screenshots/14-live-*.png`,
`15-live-*.png`, `16-live-*.png`.

Installation : `docs/connectiq.md` (compilation, simulateur, sideload). Binaires prets :
`watch/dist/spotter.iq` (tous appareils) et `watch/dist/spotter-<modele>.prg` (fr965, fr265, venu3,
vivoactive5, fenix7, epix2pro47mm, fenix843mm). Appairage : `POST /auth/pair` puis `backendUrl` (https
obligatoire sur une vraie montre) et `pairToken` dans les reglages de l'app via Garmin Connect Mobile.

## Architecture

```
Mywellness (API privee)  <->  app/mywellness  ->  FastAPI (app/api)   ->  app/garmin  ->  Garmin Connect
   programme prescrit          client, cache      GET  /  (page synchro)    conversion       workouts + planif
   seance performee du jour    live, writeback    GET  /workout/today       push (job 6h)
   ecriture manuelle                              GET  /workout/{id}/live
                                                  POST /workout/{id}/results
                                                       ^  HTTPS via le telephone (BLE)
                                                  watch/ (Connect IQ, Monkey C)
```

* `app/mywellness/` : client HTTP, modeles, service programme (seance du jour, cache, secours YAML),
  historique, `live.py` (etat machines), `writeback.py` (montre -> Mywellness).
* `app/garmin/` : client `garminconnect`, mapping exercices valide contre le catalogue Garmin, conversion,
  push + planification.
* `app/api/` : FastAPI, page web de synchro (`ui.py`), SQLite (tokens d'appairage, resultats, journal).
* `app/jobs/` : APScheduler, push quotidien.  `watch/` : app Connect IQ et outils de build.
* `docs/` : `mywellness-api.md`, `connectiq.md`, `limitations.md`, `garmin-push-capture.json`, captures.
* `DECISIONS.md` : journal des choix faits sans consultation.

## Endpoints

| Methode | Route | Auth | Role |
| --- | --- | --- | --- |
| GET | `/` | aucune (local) | page web de synchronisation |
| POST | `/ui/sync` | aucune (local) | synchronisation depuis la page (formulaire) |
| GET | `/health` | aucune | etat |
| POST | `/auth/pair` | `X-Admin-Token` | token d'appairage pour la montre |
| GET | `/workout/today` | pair ou admin | seance du jour (`?day=` optionnel) |
| GET | `/workout/all`, `/workout/{id}` | pair ou admin | seances du programme |
| GET | `/live` | pair ou admin | seance courante Technogym (bornes, machines, app) : exercices faits / en cours / a faire, series |
| POST | `/live/hr` | pair ou admin | echantillons cardio de la montre `{"samples": [[t, bpm], ...]}` |
| POST | `/live/start`, `/live/close` | pair ou admin | ouvrir / fermer la seance cote Technogym (voir limites : `StartWorkoutSession` repond `notFound`) |
| GET | `/workout/{id}/live` | pair ou admin | etat Technogym d'une seance donnee (mode guide) |
| POST | `/workout/{id}/results` | pair ou admin | series faites (montre -> backend, puis Mywellness si active) |
| GET | `/workout/{id}/results` | pair ou admin | resultats stockes |
| GET | `/history`, `/history/{idCr}` | pair ou admin | historique Mywellness |
| POST | `/garmin/push-today` | admin | push + planification du workout du jour |

Le token d'appairage se passe en en-tete `X-Pair-Token` ou en query `?token=`. La page web et `/ui/*`
sont prevus pour un backend local ; derriere un domaine public, protegez-les (reverse proxy avec auth) ou
desactivez-les.

## POC live : lire ce que font les machines, sans y toucher

Verifie (`docs/live-poc.md`) : les machines Technogym ecrivent chaque exercice dans le cloud a la fin de
l'exercice (series, charges, heure, console d'origine), et l'app mobile ne fait que relire ce cloud sur
notification push. Le backend lit les memes donnees avec ton compte : `GET /workout/{id}/live` et
`python scripts/poc_live.py` (poll 15 s, affiche les changements). A lancer pendant ta prochaine seance
pour mesurer la latence reelle et voir la seance courante ouverte.

## Etat de l'ecriture Mywellness (montre -> Technogym)

Verifie le 2026-09-30 sur une seance reelle : `MarkPhysicalActivityAsDone` marque un exercice fait dans
la seance ouverte (series prescrites, visible dans l'app en 4 s). C'est ce que fait `writeback.py` quand
`MYWELLNESS_WRITEBACK=1`. L'ecriture de series reelles differentes de la prescription
(`SavePerformedPhysicalActivity`) attend un `summaryData.stepData` dont le format n'est pas encore trouve ;
les series reelles saisies sur la montre restent dans le backend. Pour poursuivre :

```
python scripts/test_writeback.py --list
python scripts/test_writeback.py --idcr <idCr> --day 2026-09-29 --position 3     # 1 rep, 5 kg, puis tentative de suppression
```

Si la relecture montre la serie et que la suppression fonctionne, mettre `MYWELLNESS_WRITEBACK=1`.

## Deploiement

`cp .env.example .env` puis `docker compose up -d --build` : port 8000, job planifie dans le meme processus,
donnees dans `./data`. Reverse proxy TLS obligatoire devant pour la montre (Caddy, Traefik, Cloudflare
Tunnel). Le `docker build` n'a pas ete execute dans l'environnement de developpement (pas de demon).

## Tests et verification

```
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest -q      # 25 tests sur des reponses Mywellness reelles anonymisees
python scripts/explore_mywellness.py             # reconnaissance de l'API avec ton compte
```

Ce qui a ete reellement execute : login Mywellness et lecture du programme (3 seances, 27 exercices) ;
backend local servant la vraie seance ; push et planification de workouts dans Garmin Connect (job et page
web) ; app Connect IQ compilee pour 64 appareils et testee dans le simulateur fr965 sur le parcours complet,
y compris la reprise d'un envoi en attente et le mode live sur la seance faite la veille sur machines.

## Rejouer une seance sans aller a la salle

`LIVE_REPLAY_PATH=scratch/poc_live_log.jsonl LIVE_REPLAY_STEP=4 python run.py` : `GET /live` sert, une
capture toutes les 4 s, le journal enregistre par `scripts/poc_live.py` pendant une vraie seance, au lieu
d'interroger Technogym. C'est ainsi que l'ecran live a ete teste dans le simulateur (donnees reelles,
chronologie compressee). Les autres endpoints continuent de parler a Mywellness.

## Prochaines etapes

1. Prochaine seance en salle : lancer l'app sur la montre avant de badger, verifier la latence machine ->
   montre et la lisibilite ; activer la diffusion cardio de la montre et voir si la console la capte.
2. Ecrire la frequence cardiaque stockee (`hr_samples`) dans la seance Technogym par exercice
   (`SavePerformedPhysicalActivity`, `analitics.hr`), une fois l'ecriture "save" validee avec
   `scripts/test_writeback.py`, puis activer `MYWELLNESS_WRITEBACK=1`.
3. Trouver comment l'app ouvre une seance (l'action `StartWorkoutSession` du portail repond `notFound`
   pour toutes les seances du programme : code mort dans l'app) pour permettre "Demarrer la seance" depuis
   la montre.
4. Tester sur la vraie montre (modele a confirmer) : lisibilite, tactile, HTTPS.
5. Exposer le backend en https (Caddy ou Cloudflare Tunnel) pour la montre.
6. Progression : proposer la charge de la derniere seance reussie sur la montre.
7. Enrichir `exercise_map.json` au fil des programmes (rapport de mapping dans la synchro).
8. Glance "seance du jour", publication eventuelle sur le store Connect IQ.
