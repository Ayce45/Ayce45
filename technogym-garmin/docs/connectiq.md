# App Connect IQ "Spotter for Technogym" : compilation, simulateur, sideload

Application de type **device app** (Monkey C), dossier `watch/`.

## Ce que fait l'app

| Ecran | Role |
| --- | --- |
| Accueil | seance du jour (nom, date, nb d'exercices), rafraichie depuis le backend au lancement ; sinon cache `Application.Storage` et mention "Hors ligne". START pour demarrer. Menu (appui long UP) : Actualiser, Exercices, Envoyer resultats, Abandonner. |
| Serie (musculation) | exercice courant, machine, "Serie i/n", cible `reps x kg`, chrono depuis l'affichage, arc de progression. START = serie faite. DOWN = liste des exercices (saut possible). Appui long UP = menu (Annuler derniere serie, Passer l'exercice, Exercices, Terminer, Abandonner). |
| Saisie | reps puis charge, pre-remplies avec la cible. UP/DOWN ajustent (pas de charge reglable), START valide le champ, BACK annule. |
| Repos | compte a rebours (cible `rest_s`), vibration + son a zero puis serie suivante. START = passer, UP/DOWN = +/- 15 s. |
| Bloc a duree (cardio, etirement) | duree cible + puissance ou niveau ; START lance le compte a rebours, START pendant = terminer maintenant, BACK = passer. |
| Resume | duree, nb de series, volume souleve. START = **sauvegarde FIT d'abord**, puis envoi `POST /workout/{id}/results`. En echec, la seance est stockee en attente (`pending`) et renvoyee au prochain lancement ou via le menu. |

Enregistrement : `ActivityRecording` sport Training / sous-sport Strength, un lap par serie, developer fields
de lap `reps`, `charge` (kg) et `exercice` (position). Le SDK ne permet pas d'ecrire les messages FIT "Set" :
les reps/charges detaillees sont envoyees au backend, pas dans le FIT (voir `docs/limitations.md`).

Reprise : la progression (exercice, serie, resultats) est persistee a chaque serie ; si l'app est fermee
puis relancee, l'accueil indique "En cours : i/n" et START reprend ou l'on en etait (nouvelle activite FIT).

Reglages (Garmin Connect Mobile > appareil > Applications Connect IQ > Spotter for Technogym > Parametres) :

| Cle | Role |
| --- | --- |
| `backendUrl` | URL du backend, **https obligatoire** sur une vraie montre (`https://muscu.exemple.fr`) |
| `pairToken` | token obtenu par `POST /auth/pair` (en-tete `X-Pair-Token`, aussi passe en `?token=`) |
| `autoStartRest` | lancer le repos automatiquement apres une serie |
| `vibrateOnRestEnd` | vibrer/sonner en fin de repos ou de bloc |
| `weightStepKg` | pas d'ajustement de la charge (2.5 par defaut) |

Appareils declares dans `manifest.xml` : Forerunner 165/245/255/265/570/745/945/955/965/970, Fenix 6/7/8/9/E,
Epix 2, Enduro 3, Venu 2/3/4/Sq2/X1, Vivoactive 4/5/6 (API 3.2 minimum). Ajouter un modele = une ligne
`<iq:product id="..."/>` et son dossier dans `~/.Garmin/ConnectIQ/Devices`.

## Installer la chaine de compilation (Linux, sans SDK Manager graphique)

1. SDK : telecharger le zip Linux depuis `https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json`
   (cle `linux` de la derniere entree, ici `connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip`) et le
   decompresser dans `~/.Garmin/ConnectIQ/Sdks/<nom du zip sans .zip>/`. Le compilateur est
   `bin/monkeyc` (Java 17+ requis, `java -version`).
2. Appareils et polices : le SDK Manager les telecharge derriere un login Garmin. Le script
   `watch/tools/fetch_devices.py` reproduit ce flux (login SSO -> jeton OAuth `CIQ_SDK_MANAGER` ->
   `api.gcs.garmin.com/ciq-product-onboarding`) avec `GARMIN_EMAIL` / `GARMIN_PASSWORD` du `.env` :

   ```
   .venv/bin/python watch/tools/fetch_devices.py            # liste integree (64 montres recentes)
   .venv/bin/python watch/tools/fetch_devices.py --list     # tous les identifiants disponibles
   .venv/bin/python watch/tools/fetch_devices.py fr965 venu3
   ```

   Destination : `~/.Garmin/ConnectIQ/Devices/<id>/` et `~/.Garmin/ConnectIQ/Fonts/`.
3. Cle developpeur (une fois, gitignoree) :

   ```
   mkdir -p watch/keys
   openssl genrsa -out watch/keys/developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in watch/keys/developer_key.pem -out watch/keys/developer_key.der -nocrypt
   ```

## Compiler

```
cd watch
./build.sh                 # bin/spotter-fr965.prg (debug, type check gradual)
./build.sh -d venu3        # autre appareil
./build.sh --iq            # bin/spotter.iq : paquet release, tous les appareils du manifest
./build.sh --pro --iq      # bin/spotter-pro.iq : edition Pro (manifest-pro.xml, resources-pro/)
./build.sh --pro -d fr955  # bin/spotter-pro-fr955.prg
./build.sh --sim           # variante simulateur (voir plus bas)
```

Sortie verifiee le 2026-09-29 : `BUILD SUCCESSFUL` pour fr965, fr265, venu3, vivoactive5, fenix7,
epix2pro47mm, fenix843mm, et `.iq` "106 OUT OF 106 DEVICES BUILT" (~140 Ko par appareil).

## Simulateur

Le simulateur (`bin/simulator`) est une application GTK qui charge webkit2gtk 4.0. Sur Ubuntu 24.04
(webkit 4.1 / libsoup3 seulement) il faut extraire les libs 22.04 :

```
apt-get install -y libsecret-1-0 libusb-1.0-0 libsoup2.4-1 libgtk-3-0 xvfb xdotool x11-apps imagemagick
mkdir -p /usr/local/lib/ciq-compat && cd /tmp
for f in libwebkit2gtk-4.0-37_2.50.4-0ubuntu0.22.04.1_amd64.deb libjavascriptcoregtk-4.0-18_2.50.4-0ubuntu0.22.04.1_amd64.deb; do
  curl -sSO "http://archive.ubuntu.com/ubuntu/pool/main/w/webkit2gtk/$f"; dpkg-deb -x $f x; done
curl -sSO http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2ubuntu1_amd64.deb; dpkg-deb -x libicu70_70.1-2ubuntu1_amd64.deb x
curl -sSO http://archive.ubuntu.com/ubuntu/pool/main/w/woff2/libwoff1_1.0.2-2ubuntu1_amd64.deb; dpkg-deb -x libwoff1_1.0.2-2ubuntu1_amd64.deb x
cp -a x/usr/lib/x86_64-linux-gnu/*.so* /usr/local/lib/ciq-compat/
```

(Sur Ubuntu 22.04 ou Debian 12, `apt-get install libwebkit2gtk-4.0-37` suffit et `CIQ_COMPAT_LIBS`
peut rester vide.)

Puis, backend lance sur `http://127.0.0.1:8000` avec un token cree par `POST /auth/pair` :

```
# variante simulateur : reglages par defaut = backend local + token (fichiers gitignores)
mkdir -p watch/resources-sim/settings
sed "s#<property id=\"pairToken\" type=\"string\"></property>#<property id=\"pairToken\" type=\"string\">VOTRE_TOKEN</property>#" \
    watch/resources/settings/properties.xml > watch/resources-sim/settings/properties.xml
printf 'project.manifest = manifest.xml\nbase.sourcePath = source\nbase.resourcePath = resources;resources-sim\n' > watch/monkey-sim.jungle
cd watch && ./build.sh --sim && ./run-sim.sh fr965
```

Dans le simulateur : Settings > decocher "Use Device HTTPS Requirements" (le backend local est en http).
Sans ecran, `run-sim.sh` demarre un `Xvfb :99` ; on pilote les boutons avec `xdotool` (clics sur START,
UP, DOWN, BACK de l'image de la montre, appui long UP = menu) et on capture avec `import -window root`.
Les captures de `docs/screenshots/` viennent de la : accueil avec la vraie seance du jour, bloc cardio,
saisie 12 reps / 77.5 kg, repos 45 s, menu, resume, "Resultats envoyes" apres reprise d'un envoi en attente.

## Sideload sur la montre

1. `./build.sh --iq` puis brancher la montre en USB (mode transfert de fichiers / MTP).
2. Copier `watch/bin/spotter.iq` **ou** le `.prg` de votre modele dans `GARMIN/Apps/` de la montre
   (le `.prg` d'un seul appareil suffit ; le `.iq` est l'archive multi-appareils pour le store ou pour un
   sideload via l'outil de votre choix).
3. Debrancher : l'app "Spotter for Technogym" apparait dans la liste des activites / applications.
4. Reglages via Garmin Connect Mobile (l'app doit avoir ete lancee une fois) : `backendUrl` en https et
   `pairToken`. Le telephone doit etre connecte a la montre pour le reseau (BLE -> GCM -> internet).

Sans passer par le store, l'app tourne en "developer mode" : elle est signee par votre cle, pas par Garmin.
