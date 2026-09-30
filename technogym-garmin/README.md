# Technogym (Mywellness) vers Garmin

Deux produits, un backend commun :

1. **Appli de synchro.** Tu lances le backend, une page web te demande tes identifiants Technogym et
   Garmin, tu cliques : chaque seance de ton programme Mywellness devient un workout structure Garmin
   Connect (exercices, series, charges, repos), la seance du jour est planifiee sur le calendrier. Un job
   peut refaire ce push chaque matin a 6h.
2. **Compagnon de seance sur la montre (app Connect IQ "TG Muscu").** Seance du jour sur la montre,
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

## 2. Compagnon de seance sur la montre

Parcours : accueil (seance du jour, cache si hors ligne) -> START -> pour chaque exercice : serie cible
`10 reps x 80 kg`, START = fait, saisie reps puis charge (UP / DOWN, START), repos 45 s avec vibration
-> serie suivante. Blocs cardio / etirements : compte a rebours de la duree cible. Appui long UP : menu
(annuler la derniere serie, passer l'exercice, liste des exercices, terminer, abandonner). Fin : resume,
START = sauvegarde FIT **puis** envoi des resultats ; en echec, mise en attente et renvoi automatique.

Live : au demarrage, a chaque ecran de serie et toutes les 20 s, la montre demande au backend l'etat de la
seance du jour cote Technogym. Un exercice termine sur une machine passe en `[M]` dans la liste, l'ecran
affiche "Machine : fait" avec les series enregistrees et START passe au suivant en reprenant ces series.
Les exercices faits hors machine (poids libres) sont saisis sur la montre et envoyes au backend
(`POST /workout/{id}/results`) ; avec `MYWELLNESS_WRITEBACK=1` le backend les ecrit dans Mywellness dans la
seance du jour (voir "Etat de l'ecriture Mywellness").

Installation : `docs/connectiq.md` (compilation, simulateur, sideload). Binaires prets :
`watch/dist/tgmuscu.iq` (tous appareils) et `watch/dist/tgmuscu-<modele>.prg` (fr965, fr265, venu3,
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
| GET | `/workout/{id}/live` | pair ou admin | etat Technogym de la seance du jour (machines) |
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

Les actions existent et leur format est connu (voir `docs/mywellness-api.md`) : `StartWorkoutSession`,
`SavePerformedPhysicalActivity` (objet `GenericPhysicalActivityDataVO`, `manuallyDone: true`),
`CloseWorkoutSession`. Le code est en place (`app/mywellness/writeback.py`) et teste sur un client factice,
mais la premiere ecriture reelle sur ton compte n'a pas ete executee dans la session de developpement.
Pour valider :

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

## Prochaines etapes

1. Valider l'ecriture Mywellness avec `scripts/test_writeback.py`, puis activer `MYWELLNESS_WRITEBACK=1`.
2. Tester sur la vraie montre (modele a confirmer) : lisibilite, tactile, HTTPS.
3. Exposer le backend en https (Caddy ou Cloudflare Tunnel) pour la montre.
4. Progression : proposer la charge de la derniere seance reussie sur la montre.
5. Enrichir `exercise_map.json` au fil des programmes (rapport de mapping dans la synchro).
6. Glance "seance du jour", publication eventuelle sur le store Connect IQ.
