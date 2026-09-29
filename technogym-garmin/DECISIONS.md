# Journal des decisions

Chaque decision prise sans consulter l'utilisateur est notee ici, avec le contexte et les alternatives.

## 2026-09-29 : organisation du depot

* Le seul depot GitHub accessible dans cette session est `ayce45/ayce45` (depot de profil). Le projet
  vit dans le sous-dossier `technogym-garmin/` de ce depot, sur la branche de travail fournie. Il est
  autonome (son propre `.gitignore`, `.env.example`, `docker-compose.yml`) et peut etre deplace dans un
  depot dedie sans modification.
* Python 3.11, environnement virtuel `.venv` gere par `uv`, dependances listees dans `pyproject.toml`.

## 2026-09-29 : source du code Mywellness de reference

* Le depot `technogym-mcp` cite dans la mission n'existe plus sous ce nom : son auteur l'a fusionne
  dans `health_mcp` (dossier `technogym/`). C'est ce code qui a servi de reference (login, en-tetes
  `X-MWAPPS`, historique). Le client du projet est une reecriture, pas une dependance : le paquet n'est
  pas publie sur PyPI et on a besoin d'actions qu'il ne connait pas.
* Le portail legacy `www.mywellness.com/cloud` utilise par `lcanis/gymexport` repond 302 vers
  technogym.com : abandonne.

## 2026-09-29 : programme prescrit

* L'app web `endusernext` n'affiche pas le programme. Les actions ont ete trouvees par force brute
  (oracle 404 HTML vs 200 "Mandatory data"), voir `docs/mywellness-api.md`. Resultat :
  `GetUserTrainingProgram` (structure) + `GetUserWorkoutSessionPhysicalActivity` (series prescrites,
  un appel par exercice). Pas besoin du fichier YAML de secours, mais il reste supporte
  (`PROGRAM_OVERRIDE_PATH`) au cas ou l'API change.
* Choix de la seance du jour : la seance marquee `workoutSessionStatus = Suggested` par Technogym.
  Si aucune n'est marquee, rotation cyclique : la seance qui suit (par `position`) la derniere seance
  performee dans l'historique ; a defaut la position 1. Une seance deja faite aujourd'hui reste "la
  seance du jour" (on ne saute pas a la suivante avant le lendemain) pour que la montre puisse
  reprendre / consulter la seance en cours.
* Les exercices cardio (`CardioPerConstWatt`, `CardioGoalTraining`) et les etirements sont conserves
  dans la seance simplifiee avec `kind = cardio | stretching` et des series `duration_s`. Le mode
  natif Garmin les convertit en steps temps ; la montre les affiche comme des blocs a duree.

## 2026-09-29 : retour des resultats vers Mywellness

* Des actions d'ecriture existent (`StartWorkoutSession`, `SavePerformedPhysicalActivity`,
  `CloseWorkoutSession`, `MarkPhysicalActivityAsDone`). Leur format exact de `summaryData` n'est pas
  observable sans creer une vraie seance dans l'historique de l'utilisateur. Decision : les resultats
  sont toujours stockes en SQLite cote backend ; le renvoi vers Mywellness est implemente mais
  desactive par defaut (`MYWELLNESS_WRITEBACK=0`) et documente comme experimental.

## 2026-09-29 : Garmin

* `garth` est deprecie par son auteur (message a l'import) ; `garminconnect` 0.3.2 embarque son
  propre client d'authentification avec 5 strategies et rotation d'empreinte TLS (`curl_cffi`). Le
  premier login `garth` a recu un 429 depuis cette IP, `garminconnect` a reussi. On utilise donc
  `garminconnect` seul, avec persistance des jetons dans `data/garmin_tokens.json`.
* Le catalogue d'exercices Garmin est lu depuis `https://connect.garmin.com/web-data/exercises/Exercises.json`
  (1531 exercices, 47 categories) et fige dans `app/garmin/garmin_exercises.json` pour valider le
  mapping hors ligne.

## 2026-09-29 : app Connect IQ

* Type device app, Monkey C, API minimale 3.2 (Menu2, Application.Storage, Activity.SPORT_TRAINING).
  64 appareils declares (Forerunner, Fenix, Epix, Enduro, Venu, Vivoactive recents) ; l'utilisateur n'a
  pas indique son modele, le simulateur a ete teste en fr965 et la compilation verifiee sur 7 familles.
* Pas de SDK Manager graphique sous Linux : SDK 9.2.0 depuis `sdks.json`, appareils et polices via un
  script qui rejoue le flux d'authentification du SDK Manager (idee reprise de `jeansch/ciqw`), avec les
  identifiants Garmin du `.env`. Documente dans `docs/connectiq.md`.
* Simulateur sur Ubuntu 24.04 : les libs webkit2gtk 4.0 (libsoup2) n'existent plus ; on extrait celles
  d'Ubuntu 22.04 dans `/usr/local/lib/ciq-compat` plutot que de changer de distribution. Xvfb + xdotool
  pour piloter sans ecran.
* Enregistrement FIT : sport Training / Strength, un lap par serie, developer fields de lap reps / charge /
  exercice (le SDK ne sait pas ecrire les messages FIT Set). Sauvegarde FIT avant tout envoi reseau ;
  envoi en echec = seance mise en attente dans Storage (5 max) et renvoyee au prochain lancement.
* Blocs cardio et etirements integres comme compte a rebours (duree cible, puissance / niveau affiches)
  plutot qu'ignores : la seance de la montre suit l'ordre exact du programme Technogym.
* Le token d'appairage est envoye en en-tete `X-Pair-Token` et en query `?token=` (certains firmwares
  filtrent les en-tetes personnalises). Le backend accepte les deux.
* Le backend accepte des horodatages entiers (epoch) dans les resultats : c'est ce que la montre produit
  sans bibliotheque de formatage ISO ; decouvert par le premier envoi reel depuis le simulateur (422).

## 2026-09-29 : binaires livres

* `watch/dist/` contient le `.iq` multi-appareils et des `.prg` debug pour 7 modeles, commites malgre leur
  taille (2,5 Mo) : sans la chaine de compilation, c'est le seul moyen de sideloader l'app depuis le depot.
  Ils sont signes par la cle developpeur generee dans cette session (`watch/keys/`, non versionnee) ;
  regenerer la cle et recompiler pour reprendre la main sur la signature.
