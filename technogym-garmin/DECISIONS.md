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

## 2026-09-30 : recadrage en deux produits

* **Appli de synchro** : page web servie par le backend (`GET /`), identifiants Mywellness et Garmin saisis
  dans le navigateur, bouton unique. Les identifiants ne sont plus requis dans `.env` (reste possible pour
  le job planifie) ; "se souvenir" les ecrit dans `data/credentials.json` (600, gitignore). Choix d'une page
  web locale plutot que d'un executable : zero dependance graphique, meme code que l'API, fonctionne en
  Docker. La synchro cree un workout Garmin par seance du programme (`TG Seance N`, remplace les anciens
  du meme nom) et planifie la seance du jour.
* **Compagnon live bidirectionnel** : nouvel endpoint `GET /workout/{id}/live` (etat de la seance
  performee du jour : exercices faits sur machine, series reelles). La montre l'interroge au demarrage,
  a chaque ecran de serie et toutes les 20 s : un exercice enregistre par une machine Technogym est marque
  `[M]`, l'ecran propose "Machine : fait, OK = suivant", ses series machine sont reprises dans les
  resultats (source `machine`). Sens montre -> Technogym : `writeback.py` reutilise la seance performee du
  jour si les machines l'ont deja ouverte (sinon `StartWorkoutSession`), ecrit chaque exercice saisi sur la
  montre avec `manuallyDone: true` et le format `GenericPhysicalActivityDataVO`, puis ferme la seance.
* L'ecriture reelle vers Mywellness n'a pas pu etre testee ici : l'environnement a refuse l'action
  (ecriture sur un systeme externe). `scripts/test_writeback.py` est fourni pour la faire soi-meme sur une
  serie identifiable (1 rep, 5 kg), avec tentative de suppression. `MYWELLNESS_WRITEBACK` reste a 0 tant
  que ce test n'a pas confirme le format.
* Anonymisation : les identifiants compacts (UUID sans tirets dans `mwc_full_workout_id`) et le prenom
  ont ete retires des fixtures et de la doc. Ils restent dans l'historique git des premiers commits (id
  utilisateur Mywellness et id de salle, non secrets) ; la reecriture d'historique a ete refusee par le
  mode automatique, la commande est donnee dans le README.
* `TODAY_OVERRIDE` (date forcee) ajoute pour rejouer dans le simulateur une seance deja faite sur machines.

## 2026-09-30 : POC lecture live (sans acces aux machines)

* L'utilisateur n'a pas la main sur les machines : le compagnon doit fonctionner en lisant ce que
  Technogym publie. Verification par analyse de l'APK Mywellness (chaines + decompilation androguard) :
  l'app mobile elle-meme ne parle pas aux machines pour les resultats, elle recoit des push OneSignal
  (`StartExerciseOnEquipment`, `ExerciseDoneOnEquipment`, ...) et relit `GetCurrentWorkoutSession`.
  Notre poll de 15 a 20 s remplace le push. Details et preuves horodatees dans `docs/live-poc.md`.
* Ajout de `GET workout.mywellness.com/v2/enduser/workout/current` (endpoint du client "workout" de
  l'app) dans le client et dans `/workout/{id}/live` (`has_current_workout`, `current`).
* `scripts/poc_live.py` : poll lecture seule, affiche les changements, journal JSONL ; a lancer en salle
  pour mesurer la latence reelle et capturer la forme de la seance courante ouverte.
* L'APK et ses chaines restent hors depot (`scratch/`).

## 2026-09-30 : seance test a blanc (depuis le telephone)

* Latences mesurees : ouverture de seance vue en 9 s, exercices valides dans l'app vus en 4 a 11 s (poll 10 s).
* Le retour montre -> Technogym passe par `MarkPhysicalActivityAsDone` (verifie sur la seance ouverte,
  a la demande de l'utilisateur) : exercice marque fait avec les series prescrites. La tentative d'ecrire
  des series reelles via `SavePerformedPhysicalActivity` a ete interrompue (format `stepData` inconnu,
  puis action refusee par le mode automatique) ; les series reelles restent cote backend.
* `/workout/{id}/live` lit la seance courante (`GetCurrentWorkoutSession`) en priorite : elle contient
  tout pendant la seance, alors que l'historique n'est alimente qu'apres le premier exercice.

## 2026-09-30 : format d'ecriture des series et frequence cardiaque

* Plutot que de deviner le format de `SavePerformedPhysicalActivity` par essais sur le compte, les
  adaptateurs JSON de l'app Mywellness ont ete decompiles : les series vont dans `summaryData.steps[].stepData`
  avec des proprietes `{name, um, value}`. `writeback.summary_data` produit ce schema ;
  `MYWELLNESS_WRITEBACK_MODE=save` l'active (repli automatique sur `MarkPhysicalActivityAsDone`), `mark`
  reste le defaut tant qu'une ecriture reelle n'a pas ete validee.
* Frequence cardiaque : Connect IQ ne peut pas emettre en capteur Bluetooth, et l'app Technogym n'embarque
  pas le SDK mobile Connect IQ (contrairement a QZ). Le chemin retenu : la montre lit le capteur du poignet,
  envoie au backend, qui ecrit les echantillons `{t, hr}` par exercice dans la seance Technogym (`analitics`).
  L'affichage en direct sur la console d'une machine reste reserve a la diffusion systeme de la montre.

## 2026-09-30 : POC montre "Spotter for Technogym" (suivi en direct)

* Recadrage demande : la seance est pilotee depuis la salle (bornes, machines, app), la montre montre ou on
  en est. L'app Connect IQ est renommee "Spotter for Technogym" (c'etait "TG Muscu", nom choisi ici, pas une app
  existante) et son ecran principal devient l'ecran live ; le mode guide (la montre dicte les series) reste
  accessible par le menu. Les binaires `watch/dist/tgmuscu*` sont remplaces par `spotter*`.
* Nouveau `GET /live` sans identifiant de seance : la montre n'a pas a savoir quelle seance est ouverte,
  le backend renvoie la seance courante Technogym telle quelle. `GET /workout/{id}/live` reste pour le
  mode guide.
* Frequence cardiaque : la montre lit son capteur pendant l'enregistrement et envoie des lots `[t, bpm]`
  toutes les 30 s (`POST /live/hr`, table `hr_samples`). Choix de stocker cote backend plutot que d'ecrire
  directement dans Technogym : l'ecriture par exercice (`analitics.hr`) depend de la validation de
  `SavePerformedPhysicalActivity`. La diffusion vers une console de machine reste le reglage systeme de
  la montre ; l'activite lancee par l'app suffit a l'activer.
* Test sans salle : mode rejeu du backend (`LIVE_REPLAY_PATH`) qui sert les captures reelles de
  `scripts/poc_live.py`. Prefere a des fixtures inventees : ce sont les vraies reponses de Technogym du
  matin, seule la chronologie est compressee.
* `StartWorkoutSession` repond `notFound` pour toutes les seances (3 corps, 2 salles) : l'app ne l'appelle
  pas (code mort). `POST /live/start` reste expose pour tester d'autres pistes, mais la montre ne propose
  pas "Demarrer la seance" ; la seance s'ouvre depuis la salle.
* Detail technique : un modele Pydantic declare dans `create_app` n'est pas resolu par FastAPI avec
  `from __future__ import annotations` (le corps devient un parametre de query, 422). Modele remonte au
  niveau module ; un handler journalise desormais le corps des 422 pour voir ce que la montre envoie.

## 2026-09-30 : nom de l'app

* Choix de l'utilisateur : **Spotter for Technogym** ("spotter" = celui qui assure sous la barre). Verification
  sur le store Connect IQ (API de recherche du store, 4 pages de resultats, locales fr et en) : aucune app
  nommee Spotter ; les seuls noms proches sont "LARA - Live Flight Radar & Plane Spotter" (aviation), Spotify
  et "Spotovka" (prix de l'electricite). Aucune app ne contient "Technogym" ni "Mywellness" : la niche est libre.
* Le nom complet sert au store et a la liste des apps ; la montre affiche "Spotter" (chaine `ShortName`) en
  en-tete pour gagner de la place. La marque tierce reste hors icone ; la description du store portera la
  mention "application non officielle, sans lien avec Technogym ni Garmin".
* Modele de l'utilisateur : Forerunner 955 (`fr955`, deja dans le manifeste) ; un `.prg` dedie est livre.

## 2026-09-30 : vocabulaire Technogym sur la montre

* Demande : que l'app parle comme Technogym. Les chaines francaises de l'app mobile ne sont pas dans l'APK
  recupere (App Bundle, ressources de langue dans un split absent) ; le vocabulaire a donc ete repris de la
  fiche Play Store et du site technogym.com en francais (seance d'entrainement, exercices, equipement,
  MOVEs, Wellness Passport, Technogym Coach, "Suivez vos progres") et des libelles renvoyes par l'API en
  francais (noms d'exercices, "Vous avez demarre une nouvelle seance"). Toutes les chaines de la montre
  sont passees en francais accentue avec ces mots ("Terminé", "À faire", "Équipement connecté",
  "Terminé sur équipement", "Séance en cours", "Suivre ma séance", "Mode Coach", "Résultats synchronisés").
* Les MOVEs (unite Technogym, champ `doneMove` de chaque exercice fait) sont affiches sur l'ecran live.
* Limite volontaire : pas de logo Technogym, pas de "officiel" ni "by Technogym", mention non officielle
  dans la fiche store (`docs/store-listing.md`). Le store Connect IQ refuse les apps qui se font passer
  pour une marque tierce, et l'utilisateur voulait lui-meme la mention "unofficial".
* Mise en page revue pour l'ecran rond 260 px de la Forerunner 955 : en-tete court (chrono + numero),
  statut seul, ligne "n/total terminés + MOVEs", FC compacte, pied de page avec points de suspension
  (`Ui.drawWrapped` signale desormais un texte coupe).
