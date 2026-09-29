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
