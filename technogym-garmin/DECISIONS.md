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

## 2026-09-30 : ecrans facon activite Garmin, priorite a l'app montre

* Demande : moins de texte, des ecrans comme les vraies activites Garmin. Reference prise sur les pages de
  donnees des activites Course et Musculation : pages defilantes UP / DOWN, champs a etiquette petite et
  valeur en chiffres, coeur pour la FC coloree par zone (zones du profil utilisateur via `UserProfile`),
  jauge de zones, separateurs fins, points de page sur le bord. Trois pages (Exercice, Cardio, Séance) et
  la liste des exercices en menu natif `Menu2` avec `IconMenuItem`.
* Icones dessinees en primitives (`Icons.mc`) plutot qu'en bitmaps : nettes a toutes les resolutions,
  colorables, pas de ressources par appareil. Codes : coche verte = terminé, triangle orange = en cours,
  cercle gris = à faire, ondes vertes = équipement connecté, coeur = FC, chronometre = durée.
* L'appli de synchro (programme vers workouts Garmin) est mise de cote a la demande de l'utilisateur : le
  code reste mais n'est plus le produit ; README recentre sur l'app montre.
* Backend beta : le tunnel public depuis cet environnement a ete refuse par la politique de l'outil (ingress
  externe). Alternatives documentees dans le README : tunnel Cloudflare lance par l'utilisateur sur son PC
  (sans compte), relais Cloudflare Worker sans etat (compte necessaire), backend complet heberge. Pages
  statiques (GitHub Pages, artefact) exclues : pas d'execution serveur.

## 2026-09-30 : relais Cloudflare, fiche exercice, page Séance

* Backend beta sans ordinateur : l'utilisateur a un compte Cloudflare. Le glisser-deposer Pages accepte un
  `_worker.js` (verifie dans la doc Cloudflare : "a _worker.js file is supported by both Wrangler and drag and
  drop deployments"). `relay/_worker.js` reimplemente en JavaScript le sous-ensemble utilise par la montre
  (`/health`, `/live`, `/live/hr`, `/live/mark`) avec la meme compaction que `app/mywellness/live.py`, testee
  hors ligne sur les captures reelles (`relay/relay.test.mjs`). Identifiants et token dans les secrets du
  projet Cloudflare ; les pulsations sont accusees mais pas conservees (pas de stockage sans KV).
* GitHub Action `beta-backend` gardee comme seconde option (backend Python complet, 3 h, URL publiee dans
  `beta/backend.txt`, lue par la montre via `discoveryUrl`). Le tunnel n'est jamais lance depuis cet
  environnement : c'est l'utilisateur qui declenche le workflow.
* Visuels Technogym : chaque exercice expose `pictureUrl`, `imageFrames` (en pratique une image 750x950),
  `equipmentPictureUrl`, `videoUrl` (mp4) et `muscles`. Connect IQ ne lit pas de video ; la fiche exercice
  affiche l'image via `Communications.makeImageRequest` (telechargement et redimensionnement par le
  telephone) et les muscles en francais. Le simulateur exige un compte Garmin pour ces images : verifie sur
  montre uniquement.
* Page Séance : grille compacte en haut et champ "SUIVANT" au centre-bas (nom + séries) ; la page Exercice
  n'affiche plus que l'evenement du moment en bas.
* Le `.prg` personnel (URL du relais et token compiles) n'est pas versionne : `resources-beta/` est ignore
  par git et le binaire est remis directement a l'utilisateur.

## 2026-09-30 : identifiants dans Garmin Connect, relais multi-utilisateur

* Remarque de l'utilisateur : des identifiants dans les secrets Cloudflare ne servent qu'a une personne. Le
  relais devient multi-utilisateur : la montre envoie l'identifiant et le mot de passe Technogym saisis dans
  les reglages de l'app (type `password` dans `settings.xml`) en en-tetes `X-MW-Email` / `X-MW-Password` ;
  le relais se connecte pour cet utilisateur, garde le jeton Mywellness en memoire (cle = SHA-256 des
  identifiants, 500 utilisateurs max en cache, rien d'ecrit) et le cache `/live` est par utilisateur.
  Les identifiants valent authentification : plus de token d'appairage dans ce mode. Le mode perso (secrets +
  token) reste pour les binaires sideloades, car un mot de passe ne doit jamais etre compile dans un `.prg`.
* Choix "identifiants a chaque requete" plutot que "jeton Mywellness stocke sur la montre" : plus simple, pas
  d'expiration a gerer cote montre, et le canal est HTTPS de bout en bout (telephone -> relais). A revoir si
  Technogym propose un jour un OAuth.
* `/auth/check` ajoute au relais pour verifier les identifiants depuis la montre sans lire la seance.
* URL par defaut de l'app : `https://spotter-b6j.pages.dev` ; l'utilisateur du store n'a que deux champs a
  remplir.

## 2026-09-30 : exercice libre, recuperation, retours de la vraie montre

* Premiers retours sur la Forerunner 955 reelle : les polices sont plus hautes que dans le simulateur, les
  textes fixes se chevauchaient. L'accueil est passe en mise en page mesuree (hauteur rendue par
  `Ui.drawWrapped`), textes raccourcis ("Suivre", "Reprendre", "n/N terminés"), et la page Séance sans
  seance affiche le message au lieu d'une grille de zeros.
* Titres : equipement en grand, exercice en dessous (demande de l'utilisateur) ; sans equipement, la famille
  Technogym (Étirement, Cardio, Poids libres). Listes en "Équipement · Exercice".
* Exercice libre (`FreeExerciseView`) : le but de l'app pour les exercices hors equipement. Compteur de
  repetitions prerempli avec la cible du programme (pas de comptage automatique : Connect IQ n'expose pas le
  compteur de repetitions de l'activite Musculation de Garmin ; un comptage par accelerometre est possible
  plus tard mais c'est un projet a part), START = serie faite -> lap FIT, recuperation automatique du repos
  prescrit (`RestTime` remonte dans `target_sets[].rest_s` par le backend et le relais) avec vibrations,
  puis exercice marque terminé dans la seance Technogym par `MarkPhysicalActivityAsDone` (`/live/mark`
  dans le backend et le relais). Les series reelles restent dans le FIT.
* Fin de recuperation sur equipement : impossible a detecter, le cloud Technogym ne publie les series
  qu'a la fin de l'exercice (verifie sur la seance test). Compensation : l'action "Récupération" lance le
  compte a rebours du repos prescrit avec vibration, un appui START par serie.
* START sur la page Exercice ouvre un menu d'actions (comme le bouton Lap), la liste est dedans ; appui
  long UP garde le menu general.
* GitHub Action `beta-backend` retiree a la demande de l'utilisateur (relais Cloudflare deploye par lui).
  Le fichier `beta/backend.txt` reste pour la decouverte d'URL.

## 2026-09-30 : comptage des repetitions par accelerometre

* Demande : compter les repetitions automatiquement. Il existe des algorithmes ouverts (RecoFit, Microsoft
  Research 2014 : autocorrelation et detection de pics, +/-1 rep dans 93 % des series ; comptage de pas par
  fenetres glissantes) mais pas d'implementation Connect IQ. Ecrit ici en deux versions identiques : reference
  Python (`tools/reps/repcounter2.py`) et module Monkey C (`watch/source/RepCounter.mc`), temps reel, sans FFT.
* Donnees d'evaluation : MM-Fit (Strömbäck et al. 2020, montre au poignet gauche, 100 Hz, series de 10 reps
  annotees a la video), telecharge par requetes HTTP Range sur le zip de 1,7 Go (23 Mo lus). Reglage des
  parametres sur 5 seances, verification sur 6 seances jamais vues : +/-1 repetition dans 75 % des series
  (82 % hors curls) avec la regle anti faux departs retenue, 80 % (88 %) sans elle mais avec un faux mouvement
  par minute de repos bruite. Les curls de MM-Fit sont alternes et comptent les deux bras : la montre gauche ne voit
  qu'un bras sur deux et compte la moitie, ce qui est le bon comportement pour un capteur de poignet.
* Choix de conception : trois detecteurs, un par axe, et l'axe retenu est celui aux cycles les plus reguliers
  (pas le plus energique : sur les curls, l'axe le plus energique est la rotation lente du poignet). Le cycle
  entame a l'appui START compte pour une repetition. Le compteur part de zero quand il est actif ; UP / DOWN
  corrigent et figent la valeur, qui reste celle envoyee dans le lap FIT.
* Reglable dans Garmin Connect (`autoReps`), actif par defaut ; permission `Sensor` ajoutee au manifeste.
  Non testable dans le simulateur (pas de flux accelerometre) : premiere validation reelle a faire a la
  salle, en comparant la valeur affichee et le compte reel sur quelques series.

## 2026-09-30 : derniere fois, fin de serie auto, fin de seance, muscles et 1RM, charge

* Cinq manques releves face a Garmin Musculation, Hevy et Strong ont ete traites d'un bloc, le simulateur
  servant a verifier chaque ecran (captures `docs/screenshots/30` a `37`).
* Derniere fois et record : le backend et le relais lisent `ActivityHistory` (90 jours, 8 seances au plus,
  cache 10 min) et joignent a chaque exercice de la seance courante ses series de la derniere fois
  (`last_sets`, `last_on`) et sa meilleure charge (`best_weight_kg`), par `physicalActivityId` puis par nom.
  La montre affiche "Préc. 4x10x35kg · 29/09" sur la fiche et l'ecran de serie, et "RECORD !" quand la
  charge validee depasse la meilleure connue. Aucun stockage cote relais : tout est recalcule par utilisateur.
* Fin de serie automatique : quand le compteur de repetitions est actif et n'a pas vu de repetition depuis
  `autoEndSetS` secondes (6 s, reglable, 0 = jamais), la serie est validee et la recuperation demarre. Une
  correction manuelle (UP / DOWN) desactive l'automatisme pour la serie, la montre ne doit pas valider a la
  place de l'utilisateur qui reprend la main.
* Ecran de fin de seance (`SessionSummaryView`) : Terminer la séance affiche la grille durée, exercices,
  MOVEs, kcal, FC moyenne / max et volume (somme reps x charge des series libres). START enregistre le FIT.
  Fermer la seance cote Technogym reste une option du menu (`CloseWorkoutSession` via `/live/close`) parce
  que la salle la ferme d'elle-meme a la deconnexion et qu'une fermeture prematuree perdrait les exercices
  restants.
* Carte musculaire : `muscles[].muscleType` est dessine sur une silhouette de face en primitives (pas de
  bitmap, une seule ressource pour tous les ecrans), zones Technogym regroupees par famille. 1RM : la valeur
  `currentReferenceValues.Rm1` de Technogym est reprise telle quelle, sans estimation maison (Epley ou
  autre), pour ne pas contredire ce que l'utilisateur voit dans l'app Technogym.
* Charge ajustable : appui long UP pendant la serie ouvre Charge, selecteur par pas de `weightStepKg`, avec
  les disques par cote pour une barre de `barKg` (20 kg par defaut, reglable pour les barres de 15 ou 10).
  La charge est memorisee par exercice dans `Application.Storage` et reproposee la fois suivante, avant la
  cible du programme.
* Simulateur : `makeImageRequest` declenche une boite de dialogue Garmin Connect a chaque visuel, ce qui
  bloquait les captures automatiques ; la variante simulateur (`resources-sim`) coupe les visuels par la
  propriete `loadImages`, absente des reglages exposes. Les menus d'appui long se declenchent au clavier
  (touche Menu) et non par un clic long a la souris.

## 2026-09-30 : analyse de marche et business model

* Demande : combien de personnes utilisent Technogym et portent une Garmin, et quel modele economique.
  Reponse dans `docs/marche-et-business-model.md`, chiffres publics sources (Technogym FY 2024 : 22 M de comptes
  Mywellness, 100 000 centres ; Garmin : environ 45 M d'utilisateurs Connect, 15 % du marche des montres ;
  store Connect IQ : 100 000 telechargements pour la meilleure app de musculation).
* Estimation : 200 000 a 800 000 personnes dans le monde s'entrainent dans une salle Technogym connectee avec une
  Garmin ; objectif realiste 5 000 a 30 000 installations en trois ans. Vente directe a 4,99 EUR = revenu
  d'appoint ; l'echelle vient du B2B (clubs equipes Technogym) ou d'un partenariat Technogym.
* Decision : avant toute monetisation, demander un accord Enterprise API a Technogym et publier une politique de
  confidentialite du relais ; beta gratuite d'abord, payant ensuite, dossier B2B a 2 000 utilisateurs.
* Suite (meme jour) : l'utilisateur tranche pour une app gratuite avec limitations, sans API Entreprise pour
  l'instant, mesurer qui paie, puis proposer a Technogym. Consequences : freemium en une seule app via l'essai
  Connect IQ (illimite en duree, limite en fonctions), gratuit = direct, FC, MOVEs, liste, fiche ; payant 4,99 EUR
  = exercice libre, derniere fois et records, charge et disques, fin de seance. Prealables : politique de
  confidentialite, telemetrie anonyme, message pour les comptes sans mot de passe (Apple, Google, Facebook).

## 2026-09-30 : deux editions, gratuite (10 seances) et Pro

* Demande : une app gratuite limitee a 10 seances et une app payante complete. Compter des seances est aussi
  simple que compter des series : `/live` porte l'identifiant de seance Technogym (`workout_id`, sinon `idCr`),
  donc la gratuite compte les seances distinctes suivies en mode live et rouvrir la meme seance ne consomme rien.
* Realisation : memes sources, propriete `edition` (`free` par defaut, `pro` dans `resources-pro/` qui change
  aussi le nom en "Spotter Pro for Technogym"), `manifest-pro.xml` avec son propre identifiant, `monkey-pro.jungle`,
  `build.sh --pro`. Le binaire perso (`monkey-beta.jungle`) est desormais Pro + reglages personnels. Quota dans
  `Application.Storage` (`freeSessions`, liste des identifiants), compteur "Gratuit : n/10 séances" sur l'accueil,
  et quand le quota est atteint la seance ouverte n'est pas chargee : message jaune vers Spotter Pro sur l'accueil
  et l'ecran live, START sans effet.
* Verifie dans le simulateur (captures 38 a 40) : compteur 0/10 puis 1/10 apres une seance, nom "Spotter Pro",
  blocage avec quota force a 0 via `resources-sim`. Le simulateur conserve stockage et reglages dans
  `/tmp/com.garmin.connectiq/GARMIN/APPS/{DATA,SETTINGS}` ; "Reset All App Data" ne vide que l'app courante et les
  reglages persistes priment sur les valeurs compilees : il faut supprimer ces fichiers pour tester une valeur.
* Limites assumees : le compteur est local a la montre (reinstaller le remet a zero) ; la Pro ne peut etre
  vendue qu'apres ouverture du compte marchand Garmin (100 USD/an) et relecture de la fiche.

## 2026-09-30 : deblocage par la boutique Connect IQ (une seule app possible)

* Question : avec un essai Connect IQ, qui sait qui a paye ? Garmin. La boutique signe l'app verrouillee ou
  debloquee selon l'achat (Garmin Pay, lie au compte Garmin, valable sur toutes les montres du compte) et
  `AppBase.isTrial()` renvoie cet etat sur la montre. Le developpeur ne voit jamais l'acheteur : seulement des
  rapports de ventes agreges (portail developpeur, compte marchand > Documents). Pour un binaire de
  developpement ou sideloade, `isTrial()` vaut toujours true.
* Realisation : `Model.isPro = edition == "pro" || !isTrial()`. La propriete `edition` reste le repli pour le
  binaire perso et le simulateur ; `getTrialDaysRemaining()` renvoie null (pas de limite de duree, la limite est
  en seances). Les deux chemins de publication restent ouverts : une seule app "payante avec essai" (recommande,
  une fiche) ou deux apps (manifest-pro.xml conserve).
* Le compteur de seances gratuites reste local a la montre dans les deux cas.
* Suite : l'utilisateur retient la version a une seule app payante avec essai. Le binaire perso reprend le
  manifeste du store (meme identifiant, `edition=pro` dans `resources-beta/`), les binaires de la variante Pro
  sortent de `dist/`, textes "Essai : n/10 séances" et "Vos 10 séances d'essai sont utilisées. Débloquez Spotter
  dans la boutique Connect IQ". La variante a deux apps reste dans le depot sans etre le chemin par defaut.

## 2026-09-30 : depot prive, relais en dur

* Le code devient payant : le dossier `technogym-garmin` part avec son historique dans le depot prive
  `Ayce45/Spotter` (branche `main`, `git subtree split`), et sort du depot public.
* La decouverte de l'URL du relais via `beta/backend.txt` sur GitHub disparait (un depot prive ne sert pas de
  fichiers bruts sans authentification, et l'URL Pages ne changera pas) : `Net.DEFAULT_BACKEND` en dur, le
  reglage `backendUrl` ne sert plus qu'au backend perso et au simulateur.
