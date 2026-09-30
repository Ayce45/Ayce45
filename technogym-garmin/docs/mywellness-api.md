# API privee Mywellness (Technogym) : ce que l'on utilise

Reconnaissance effectuee le 2026-09-29 avec `scripts/explore_mywellness.py` (sortie reelle dans la
section "Sortie du script"). L'API officielle Technogym est reservee aux partenaires B2B ; on parle ici
de l'API JSON consommee par les applications utilisateur Technogym (app mobile Mywellness et app web
`endusernext.mywellness.com`). Rien n'est garanti : Technogym peut changer ces routes sans preavis.

Sources de depart :

* `technogym_mcp` de Erik Anker Kilberg Skallevold, aujourd'hui fusionne dans son depot `health_mcp`
  (dossier `technogym/`). Il documente le login et les actions d'historique.
* `lcanis/gymexport` (portail legacy `www.mywellness.com/cloud`). Ce portail redirige desormais vers
  technogym.com (302) : il n'est plus exploitable.
* Bundle JS de `endusernext.mywellness.com` (`assets/index-*.js`). Cette app ne contient que la partie
  reservation / cours / historique : le programme prescrit n'y est pas. Les hotes qu'elle declare :
  `core`, `services`, `workout`, `meet`, `cms`, `pay`, `iotcore`, `ioteam` .mywellness.com.
* Decouverte par force brute des actions `Training/User/{userId}/<Action>` (voir "Methode").

## Hotes et en-tetes

| Usage | URL |
| --- | --- |
| Login | `POST https://core.mywellness.com/v2/enduser/authentication/login` |
| Donnees | `POST https://services.mywellness.com/{facilityUrl}/Training/User/{userId}/<Action>` |
| Analytique cardio | `POST https://services.mywellness.com/{facilityUrl}/Training/CardioLog/{analyticsId}/Details` |

En-tetes envoyes sur toutes les requetes (sans eux : `ClientApplicationNotTrusted`) :

```
X-MWAPPS-APPID: EC1D38D7-D359-48D0-A60C-D8C0B8FB9DF9
X-MWAPPS-CLIENT: enduserweb
X-MWAPPS-CLIENTVERSION: 1.0,enduserweb
Accept: application/json
Authorization: Bearer <token>      (apres login)
```

Le corps est toujours du JSON, la reponse aussi. Format de reponse :

```json
{ "data": { ... }, "token": "<nouveau token>", "version": "10.0.276.0", "expireIn": 3600, "currentUtcTimestamp": "..." }
```

ou, en erreur (HTTP 200 quand meme) :

```json
{ "errors": [ { "field": "Position", "type": "Required", "details": "", "errorMessage": "Mandatory data", "message": "Mandatory data" } ] }
```

Une action inexistante renvoie un HTTP 404 avec une page HTML ASP.NET ("The resource cannot be found").
Une action existante appelee sans parametre renvoie HTTP 200 + `errors` "Mandatory data" : c'est
l'oracle utilise pour la decouverte.

`facilityUrl` est le slug d'une des salles du compte (`facilities[].url` dans la reponse de login).
Les actions de programme fonctionnent avec n'importe quelle salle du compte ; les actions de seance
performee doivent utiliser la salle ou la seance a eu lieu (`facilityId` de l'item d'historique).

## Login

```
POST https://core.mywellness.com/v2/enduser/authentication/login
{ "username": "<email>", "password": "<mot de passe>", "keepMeLoggedIn": true }
```

Reponse (extrait) : `token`, `userContext.id` (userId), `userContext.measurementSystem`,
`userContext.defaultCulture`, `facilities[] {id, url, name}`. Le token est valable 1 h (`expireIn`)
et chaque reponse en renvoie un nouveau. Le client re-login une fois sur erreur d'auth.

## Lecture : historique (repris de technogym_mcp)

| Action | Corps | Retour |
| --- | --- | --- |
| `ActivityHistory` | `{"startDay": "yyyyMMdd", "endDay": "yyyyMMdd", "justThisType": "WorkoutSession"}` (filtre optionnel) | `items[]` : `type` (WorkoutSession, Activity, Movement), `idCr`, `partitionDate`, `hour`, `minute`, `name`, `userWorkoutSessionId`, `facilityId`, `numberOfExerciseDoneWithGroups`, `numberOfExerciseToDoWithGroups`, `workoutEffectiveness`... |
| `GetPerformedWorkoutSessionByIdCr` | `{"idCr": 1146, "partitionDate": "20260929"}` | seance complete : `physicalActivities[]` avec `displayPrescibedPhysicalActivity.steps[]` (prescrit) et `performedPhysicalActivity.data.steps[]` (fait), `status` (Done, ToDo), `workoutEfficacy`, `doneSummary` |
| `GetHrSession` | `{"idCr": ..., "partitionDate": 20260929}` (entier) | echantillons de frequence cardiaque |
| `Training/CardioLog/{analyticsId}/Details` | `{}` | series temporelles machine (puissance, cadence, vitesse), FC, zones |
| `MyMovergy` | `{}` | `{"movergy": 1256}` |
| `Goal` | `{}` | objectif declare (`MoreStrength`...) |

Les proprietes d'une serie sont des lignes `{physicalProperty, value, unitOfMeasure, ...}`.
Proprietes vues : `IsoReps` (repetitions), `IsoWeight` (charge en kg), `RestTime` (repos en s),
`Duration` (s), `Power` (W), `Level`, `Calories`, `Move`, `TotalIsoWeight`, `Rm1`.

## Lecture : programme prescrit (nouveau)

C'est la partie qui manquait a technogym_mcp.

### `GetUserTrainingProgram`

Corps `{}`. Retourne `userTrainingProgramDetails` :

* `id`, `name`, `assignedOn`, `expiresOn`, `lastUpdateDate`, `planAuthor`, `assignedByFacilityId`
* `workoutRotationMode.workoutRotationModeType` : `Cyclical` (les seances s'enchainent en boucle)
* `targetWorkouts`, `targetWorkoutPerWeek`
* `workoutSessions[]` : `id` (= `userWorkoutSessionId`), `position`, `name`, `workoutSessionStatus`
  (`Suggested` sur la seance que Technogym propose ensuite, `None` sinon), `physicalActivitiesCounter`,
  `displayDurationShort`, `physicalActivities[]`

Chaque `physicalActivities[]` decrit l'exercice sans ses charges : `position`, `physicalActivityId`,
`physicalActivityName`, `physicalActivityShortName`, `equipmentName`, `equipmentType`, `equipmentCode`,
`physicalActivityCode`, `physicalActivityType` (`StrengthLoad`, `CardioPerConstWatt`,
`CardioGoalTraining`, `Stretching`), `isCardio`, `targetType` (`IsoReps`, `Duration`), `targets[]`,
`onlyTrackManually`, `muscles[]`, `estimatedDuration`, `pictureUrl`, `videoUrl`.

### `GetUserWorkoutSession`

Corps `{}` : renvoie la seance suggeree. Corps `{"workoutSessionId": "<id>"}` : la seance demandee.
Meme structure que `workoutSessions[]` ci-dessus, plus `askForTPRenewal`, `editMode`.
(`userWorkoutSessionId` et `id` comme noms de parametre sont ignores.)

### `GetUserWorkoutSessionPhysicalActivity` : les series prescrites

```
{ "userWorkoutSessionId": "<id de seance>", "position": 2 }
```

Retourne `userPhysicalActivity` = l'exercice ci-dessus plus `displayPrescibedPhysicalActivity` :

* `target` : `IsoReps` ou `Duration`
* `steps[]` : une entree par serie, `properties[]` avec `IsoReps`, `IsoWeight`, `RestTime`
  (musculation), `Duration` + `Power` ou `Level` (cardio), `Duration` + `RestTime` (etirement)
* `constraints[]` : plages autorisees par la machine, dont le `WeightStack` (plaques, min, max)
* `extData.mwc_default_rep_duration` : duree d'une repetition en secondes (pour estimer la duree)

Exemple reel (Leg press Sel) : 4 series `IsoReps=10, IsoWeight=80, RestTime=45`.
Il faut un appel par exercice (10 a 11 par seance) ; le backend met le resultat en cache.

### `GetCurrentWorkoutSession`

`{}` -> `{"hasCurrentWorkout": false}` ou la seance en cours si une seance a ete demarree.

## Ecriture : tracking manuel (existe)

Les actions suivantes existent et repondent avec leurs champs obligatoires. Elles sont utilisees par
l'app mobile quand on coche un exercice fait "a la main". Signatures relevees a vide :

| Action | Message a vide | Parametres deduits |
| --- | --- | --- |
| `StartWorkoutSession` | `The UserWorkoutSessionId field is required.` | `{"userWorkoutSessionId": "<id>"}`. Avec un id inconnu : `{"notFound": true}`. Ouvre une seance performee (idCr + partitionDate) sur la salle de l'URL. |
| `CloseWorkoutSession` | repond `{"closed": false, ...}` sans seance ouverte | `{"idCr": ..., "partitionDate": "yyyyMMdd"}` |
| `SavePerformedPhysicalActivity` | `FacilityUrl or FacilityId are required` ; `You must specify PhysicalActivityId OR EquipmentCode, PhysicalActivityCode and TargetType` ; `You must specify one of SummaryData OR OutputBuffer` | `{"facilityUrl", "physicalActivityId", "idCr", "partitionDate", "position", "summaryData": {...}}` : enregistre un exercice fait avec ses series |
| `MarkPhysicalActivityAsDone` | champ `Position` requis | `{"userWorkoutSessionId", "position", "idCr", "partitionDate"}` : coche un exercice sans detail |
| `DeletePerformedPhysicalActivity` | Mandatory data x2 | supprime un exercice performe |
| `SaveUserPhysicalActivity` | `PhysicalActivityTemplateId is mandatory in creation` | ajoute un exercice au programme |
| `UpdateUserWorkoutSessionPhysicalActivity`, `ReplaceUserWorkoutSessionPhysicalActivity`, `DeleteUserWorkoutSessionPhysicalActivity` | Mandatory data | edition du programme |
| `SaveUserTrainingProgram`, `SaveGoal` | Mandatory data | edition du programme / objectif |

Sondes complementaires du 2026-09-30 (sans creation de donnees) : `summaryData` est desserialise dans le
type serveur `Technogym.MWApps.Training.ValueObject.PhysicalActivity.GenericPhysicalActivityDataVO`, le meme
objet que `performedPhysicalActivity.data` en lecture (`{"constraints": [], "data": [], "steps": [{"data":
[{"physicalProperty": "IsoReps", "value": 10}, {"physicalProperty": "IsoWeight", "value": 80}]}]}`). Un
`summaryData` vide repond `{"result": "ExerciseDataNotValid", "wasOnline": false, "equipmentFacilityId": ...}`
: `wasOnline: false` designe le tracking manuel. `MarkPhysicalActivityAsDone {"position": n}` sans seance
repond 200 sans effet. L'ecriture reelle (creation d'une serie) n'a pas ete executee dans la session de
developpement : `scripts/test_writeback.py` le fait sur une serie identifiable, avec tentative de suppression. Le backend implemente donc le retour vers Mywellness derriere un drapeau
(`MYWELLNESS_WRITEBACK=1`, desactive par defaut) avec le flux `StartWorkoutSession` ->
`SavePerformedPhysicalActivity` (une entree par exercice, `summaryData.steps` au format
`{physicalProperty, value}` identique a celui lu dans `performedPhysicalActivity.data.steps`) ->
`CloseWorkoutSession`. Les resultats sont toujours stockes en local (SQLite) quoi qu'il arrive.

## Actions testees qui n'existent pas (404)

`GetCurrentTrainingProgram`, `GetTrainingProgram(s)`, `GetPrescribedWorkouts`, `GetPrescription`,
`GetWorkoutSessions`, `GetAssignedWorkouts`, `GetWorkoutPlan`, `GetPhysicalActivity`,
`GetPhysicalActivityDetails`, `GetPrescribedPhysicalActivity`, `GetUserPhysicalActivity`,
`GetWorkloads`, `SavePerformedWorkoutSession`, `SaveWorkoutSession`, `TrackWorkoutSession`, et les
variantes a segments de chemin (`Training/PhysicalActivity/{id}/Details`, etc.). Liste complete des
resultats positifs dans `scratch/probe_actions.json` (non versionne) et ci-dessous.

Actions existantes non utilisees : `GetWorkouts` (`{"lastSyncDate", "workouts": []}` : synchro d'apps
tierces), `MoveTrends`, `SearchEquipment`.

## Methode de decouverte

1. Login reproduit avec les en-tetes de technogym_mcp.
2. Lecture du bundle JS d'`endusernext.mywellness.com` : seule `GetPerformedWorkoutSessionByIdCr`
   y apparait (l'app web ne gere pas le programme).
3. Force brute de noms d'actions (verbes x noms, environ 8 400 combinaisons) contre
   `Training/User/{userId}/<Action>` avec un corps `{}`. Le 404 HTML signale une action inexistante,
   le 200 avec `errors` "Mandatory data" une action existante. Puis lecture des messages d'erreur
   pour deduire les parametres (`Position`, `UserWorkoutSessionId`, `FacilityUrl`...).

## Sortie du script

Extrait de `python scripts/explore_mywellness.py` le 2026-09-29 (identifiants dans `.env`) :

```
== 1. Login
   utilisateur ok, culture=fr-FR, unites=Metric, salles=2
== 2. Programme prescrit (GetUserTrainingProgram)
   "Programme d'entraînement de <prenom>" assigne le 2026-09-29 17:10:21 +00:00 expire le 2026-12-22
   rotation=Cyclical cible/semaine=2
   [1] Séance 1 status=Suggested exercices=10 duree=64 min.
        2. Leg press Sel: Extension des jambes [StrengthLoad] -> IsoReps=10,IsoWeight=80,RestTime=45 (x4)
        3. Leg extension Sel: Extension des jambes [StrengthLoad] -> IsoReps=10,IsoWeight=40,RestTime=45 (x4)
        4. Leg curl Sel: Flexion des jambes [StrengthLoad] -> 3 x IsoReps=10,IsoWeight=35,RestTime=45 ; IsoReps=10,IsoWeight=52.5,RestTime=60
        ...
   [2] Séance 2 status=None exercices=11 duree=61 min.
   [3] Séance 3 status=None exercices=6 duree=40 min.
== 3. Historique (ActivityHistory)
   90 elements sur 90 jours: {'Activity': 82, 'WorkoutSession': 8}
   - 2026-09-29 Programme d'entraînement de <prenom> - Séance 3 idCr=1146 exos=5/6
== 4. Signatures des actions d'ecriture
   StartWorkoutSession: The UserWorkoutSessionId field is required.
   SavePerformedPhysicalActivity: FacilityUrl or FacilityId are required; You must specify
   PhysicalActivityId OR EquipmentCode, PhysicalActivityCode and TargetType; You must specify one of
   SummaryData OR OutputBuffer
```

Les fixtures anonymisees de ces reponses sont dans `tests/fixtures/`.
