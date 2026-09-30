# Passage de main : reprendre Spotter dans une nouvelle session

Etat au 30 septembre 2026, fin de la session qui a construit le projet. Ce document permet a une nouvelle
session Claude Code (ou a une personne) de reprendre sur le depot prive `Ayce45/Spotter` sans rien perdre.
Aucun secret ici : les fichiers prives sont listes en section 3 et livres a part.

## 1. Ou est le code

* Source actuelle : depot public `Ayce45/Ayce45`, branche `ccr-a619a96d-3zoi93`, dossier `technogym-garmin/`.
  Dernier commit de cette branche = etat complet et coherent (tests, binaires `watch/dist`, docs).
* Destination : depot prive `https://github.com/Ayce45/Spotter`, vide au moment de l'ecriture. Le dossier doit
  devenir la racine du depot, avec son historique. Commandes, depuis un clone du depot public :

```
git clone https://github.com/Ayce45/Ayce45 ayce45 && cd ayce45
git checkout ccr-a619a96d-3zoi93
git subtree split --prefix=technogym-garmin -b spotter-export      # 34 commits, .gitignore inclus
git push https://github.com/Ayce45/Spotter spotter-export:main
```

  L'historique a ete relu : aucun mot de passe ni jeton ; il contient seulement l'ancienne URL
  `spotter.evanjuge-fr.workers.dev` (deux lignes, deja publique, sans valeur).
* Ensuite : retirer `technogym-garmin/` du depot public (commit de suppression sur la branche ; l'historique
  public garde l'ancien code, une reecriture n'a pas ete voulue). Le fichier `beta/backend.txt` n'est plus
  necessaire (URL du relais en dur dans l'app).

## 2. Ce que fait le projet (resume)

* `watch/` : app Connect IQ "Spotter for Technogym" (Monkey C, SDK 9.2.0). Suit en direct la seance Technogym
  (bornes, machines, app) sur la montre : pages Exercice / Cardio / Séance, menu d'actions START, exercice
  libre avec compteur de repetitions par accelerometre et fin de serie auto, recuperation avec vibrations,
  fiche (visuel, muscles, 1RM, derniere fois), charge et disques, record, fin de seance, fermeture Technogym.
  Une seule app payante avec essai : verrouillee (`isTrial()`) = 10 seances distinctes, debloquee = sans limite.
  Details : `README.md` section 2, `DECISIONS.md` (journal complet des choix), captures `docs/screenshots/21` a `40`.
* `relay/_worker.js` : relais Cloudflare Pages sans etat (la montre ne peut pas lire les reponses Mywellness de
  200 Ko). Deploye par l'utilisateur sur `https://spotter-b6j.pages.dev` par upload du zip
  `relay/spotter-relay-pages.zip`. **Verifier que le zip deploye est le dernier** (il doit repondre a
  `POST /live/close` et renvoyer `last_sets`, `muscle_types`, `rm1_kg` dans `/live`). Test : `node relay/relay.test.mjs`.
* `app/` : backend FastAPI equivalent au relais, pour le developpement et le rejeu (`python run.py`,
  `LIVE_REPLAY_PATH=scratch/poc_live_log.jsonl LIVE_REPLAY_STEP=6`). Tests : `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest -q`
  (27 tests). L'ancienne app de synchro (programme Technogym vers workouts Garmin) est en retrait, section 1 du README.
* `tools/reps/` : algorithme de comptage de repetitions (reference Python + evaluation MM-Fit), `docs/marche-et-business-model.md`
  (analyse de marche, strategie), `docs/store-listing.md` (textes de la fiche store).

## 3. Fichiers prives, hors git (livres dans `spotter-handoff-private.tar.gz`)

| Fichier | Role | Ou le remettre |
| --- | --- | --- |
| `.env` | identifiants Mywellness et Garmin pour le backend local et les scripts | racine du depot |
| `watch/keys/developer_key.der` et `.pem` | **cle de signature Connect IQ**. La garder : une app du store doit etre mise a jour avec la meme cle, et un sideload signe autrement n'ecrase pas le precedent | `watch/keys/` |
| `watch/resources-beta/settings/properties.xml` | reglages compiles du binaire perso : identifiants Technogym, `edition=pro`, `backendUrl` vide (= relais en dur) | `watch/resources-beta/settings/` |
| `watch/monkey-beta.jungle` | jungle du binaire perso (manifest du store + `resources;resources-beta`) | `watch/` |
| `watch/resources-sim/settings/properties.xml` | variante simulateur : `backendUrl=http://127.0.0.1:8000`, `pairToken` de test, `loadImages=false` | `watch/resources-sim/settings/` |
| `scratch/poc_live_log.jsonl` | journal d'une vraie seance (captures `GetCurrentWorkoutSession`), base du rejeu et des captures d'ecran | `scratch/` |
| `scratch/pair_token.txt` | jeton d'appairage du backend local | `scratch/` |

Regle depuis le debut : aucun identifiant dans git ; avant chaque commit, `git diff --cached | grep -cE '<motifs des identifiants>'` doit
valoir 0. Les motifs a utiliser sont les premiers caracteres de chaque mot de passe et jeton (voir les fichiers prives).

## 4. Environnement de travail

* Toolchain : `docs/connectiq.md` (SDK Linux dans `~/.Garmin/ConnectIQ/Sdks/`, appareils via
  `watch/tools/fetch_devices.py`, bibliotheques de compatibilite du simulateur dans `/usr/local/lib/ciq-compat`,
  `LD_LIBRARY_PATH` a positionner). **Le compilateur `monkeyc` comme le simulateur exigent un DISPLAY** : lancer
  `Xvfb :99 -screen 0 1280x900x24 &` et `export DISPLAY=:99` avant `./build.sh`.
* Compilation : `watch/build.sh -d fr955` (debug), `--iq` (paquet store), `--sim` (variante simulateur),
  `--pro` (variante deux apps, non retenue). Binaire perso :
  `monkeyc -d fr955 -f watch/monkey-beta.jungle -o spotter-beta-fr955.prg -y watch/keys/developer_key.der -l 1 -w`.
* Simulateur : `watch/tools/sim/capture_all.sh` et `capture_tail.sh` rejouent tout le parcours et capturent chaque
  ecran (reperes des boutons et pieges dans l'en-tete des scripts). `makeImageRequest` ouvre une boite de dialogue
  Garmin Connect dans le simulateur : la variante `--sim` coupe les visuels (`loadImages=false`).
* Relais : `cd relay && zip spotter-relay-pages.zip _worker.js index.html`, puis upload dans le projet Pages
  `spotter-b6j` (Direct Upload). Pas de secret dans le relais : la montre envoie `X-MW-Email` / `X-MW-Password`,
  le relais garde le jeton Mywellness en memoire seulement.

## 5. Decisions en vigueur (details dans DECISIONS.md)

* Nom : "Spotter for Technogym", "Spotter" sur la montre, mention non officielle, aucun logo Technogym.
* Vocabulaire Technogym, ecrans facon activite Garmin, equipement en titre et exercice en sous-titre.
* Pas d'API Entreprise Technogym pour l'instant (API privee de l'app, identifiants saisis dans Garmin Connect) ;
  etre pret a basculer, la premiere question de Technogym portera sur l'acces aux donnees.
* Monetisation : une seule app payante 4,99 EUR avec essai (10 seances), etat tenu par la boutique ; mesurer,
  puis proposer a Technogym (partenariat ou petit rachat). Variante deux apps conservee dans le depot.
* URL du relais en dur (`Net.DEFAULT_BACKEND`), plus de decouverte via GitHub.

## 6. Prochaines etapes proposees

1. Importer dans `Ayce45/Spotter`, remettre les fichiers prives, verifier `./build.sh -d fr955` et `pytest`.
2. Re-uploader le zip du relais si ce n'est pas fait ; tester `/live` depuis la montre reelle avec le dernier
   binaire perso (relais en dur).
3. Politique de confidentialite (page sur le projet Pages) et telemetrie anonyme dans le relais (utilisateurs
   actifs par hash, seances suivies, retention) : sans chiffres, pas de dossier Technogym.
4. Compte developpeur Connect IQ, compte marchand (100 USD/an), fiche store depuis `docs/store-listing.md`,
   captures parmi `docs/screenshots/21` a `40`, prix 4,99 EUR avec essai.
5. Validation en salle : compteur de repetitions, fin de serie automatique (`autoEndSetS`), latence machine ->
   montre, diffusion cardio vers la console.
6. Comptes Technogym crees via Apple / Google / Facebook : pas de mot de passe, donc pas de connexion possible ;
   afficher un message clair, mesurer la proportion.
7. Ecriture des vraies series dans Technogym (`SavePerformedPhysicalActivity`) non validee, voir README
   "Etat de l'ecriture Mywellness".
