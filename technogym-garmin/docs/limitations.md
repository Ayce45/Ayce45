# Limites connues

## Ce que Garmin Connect ne verra pas

* **Series detaillees dans le FIT.** Le SDK Connect IQ n'expose pas l'ecriture des messages FIT `Set`
  (reps, charge, type d'exercice par serie) qu'utilise l'activite Musculation native de la montre. L'app
  enregistre une activite Training / Strength avec un lap par serie et trois developer fields de lap
  (`reps`, `charge`, `exercice`). Garmin Connect affiche donc la duree, la FC, les laps et ces champs
  developpeur dans la section "Connect IQ", mais pas le tableau de series natif ni le volume total. Les
  series reelles sont dans le backend (`GET /workout/{id}/results`).
* **Workout structure : pas de niveau ou de puissance cible sur les blocs cardio.** Le workout Strength
  Garmin accepte des steps a duree avec categorie d'exercice (velo, stepper, elliptique) mais pas de
  cible de puissance / niveau exploitable par la montre. La cible est mise dans la description du step
  ("86 W", "niveau 9") et affichee comme texte.
* **Correspondance des exercices.** Le catalogue Garmin (1531 exercices) n'a pas d'equivalent exact pour
  plusieurs machines Technogym (chest press, lower back, cable stations). Le mapping
  `app/garmin/exercise_map.json` choisit alors la categorie seule (`BENCH_PRESS`, `HYPEREXTENSION`) ou un
  exercice proche (`WEIGHTED_CRUNCH` pour Total abdominal, `STANDING_HIP_ABDUCTION` pour Abductor). Tout
  inconnu tombe sur `TOTAL_BODY`. Le rapport de mapping est renvoye par `POST /garmin/push-today`.
* **Un workout planifie par jour.** Le job du matin cree "TG <seance> <date>" et le planifie a la date du
  jour, en remplacant un eventuel workout du meme nom. Si la seance suggeree par Technogym change dans la
  journee (coach qui modifie le programme), il faut relancer `POST /garmin/push-today`.

## Fragilite des API non officielles

* **Mywellness** : API privee des apps utilisateur Technogym, sans contrat. Les identifiants d'app
  (`X-MWAPPS-APPID`) peuvent etre revoques, les actions renommees, le format des reponses change sans
  preavis. Le client se reconnecte une fois sur erreur d'auth et le backend garde un cache de 5 min ; la
  montre garde la derniere seance en cache. Dernier recours : `PROGRAM_OVERRIDE_PATH` (YAML a la main).
* **Ecriture Mywellness** : les actions existent (`StartWorkoutSession`, `SavePerformedPhysicalActivity`,
  `CloseWorkoutSession`) mais le format de `summaryData` n'a pas ete confirme sur un vrai compte (cela
  aurait cree des seances fantomes dans l'historique). Le renvoi est desactive par defaut
  (`MYWELLNESS_WRITEBACK=0`) ; a activer en connaissance de cause, et verifier la premiere seance dans
  l'app Mywellness.
* **Garmin Connect** : `garminconnect` s'appuie sur le SSO web / mobile de Garmin, avec rotation
  d'empreinte TLS pour contourner les limites Cloudflare. Un `429 Too Many Requests` est possible depuis
  une IP partagee (observe avec `garth`), un changement de flux de login peut casser le push. Les jetons
  sont persistes (`data/garmin_tokens.json`) pour limiter les logins. Si le compte active la MFA, le
  premier login doit se faire en interactif (`prompt_mfa`), le job planifie ne peut pas saisir le code.
* **Telechargement des appareils Connect IQ** : `watch/tools/fetch_devices.py` reproduit le flux du SDK
  Manager (client `CIQ_SDK_MANAGER`) ; meme fragilite que ci-dessus.

## Mode live (machines -> montre)

* La montre voit un exercice "fait sur machine" quand la machine Technogym l'a envoye a Mywellness, c'est
  a dire a la fin de l'exercice (pas serie par serie) et avec le delai de synchronisation du cloud
  Technogym, observe entre quelques secondes et une minute. Le poll est toutes les 20 s.
* Les blocs cardio machine ne remontent pas de series detaillees (duree / puissance sont dans les
  analytics CardioLog, pas dans les steps) : la montre affiche "Machine : fait" sans detail.
* Si la seance n'a pas ete ouverte sur une machine (que des poids libres), `session_found` est faux : la
  montre fonctionne en mode autonome et l'ecriture vers Mywellness ouvre la seance elle-meme.

## Choix de la seance du jour

Le programme est "cyclique" : `workoutSessionStatus = Suggested` cote Technogym, sinon la seance qui
suit la derniere performee. Une seance faite aujourd'hui reste la seance du jour. Si vous faites deux
seances le meme jour ou changez l'ordre, la montre permet de sauter a un autre exercice mais pas de
choisir une autre seance : utiliser `GET /workout/{id}` (ou `GET /workout/all`) pour la pousser a la
main, ou attendre le lendemain.

## Montre

* HTTPS obligatoire pour `makeWebRequest` sur une vraie montre : le backend doit etre expose derriere un
  reverse proxy TLS (Caddy, Traefik, Cloudflare Tunnel). En local, le simulateur accepte http si on
  decoche "Use Device HTTPS Requirements".
* Le reseau passe par le telephone (BLE puis Garmin Connect Mobile). Sans telephone, seul le cache est
  disponible ; les resultats sont mis en attente et renvoyes plus tard.
* Reponses limitees en taille par le firmware (quelques Ko a quelques dizaines de Ko selon le modele) :
  le backend omet les champs nuls et la seance du jour fait ~4 Ko pour 11 exercices.
* Interface pensee pour les montres a 5 boutons (START / BACK / UP / DOWN, appui long UP pour le menu) ;
  sur les modeles tactiles (Venu, Vivoactive), le tap vaut START, le balayage haut/bas vaut UP/DOWN.
  Non teste sur un vrai appareil dans cette session : uniquement dans le simulateur fr965.
* Pas de widget / glance : l'app se lance depuis la liste des applications.
