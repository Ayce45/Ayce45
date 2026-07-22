# daily.dev Widget

Widget Android (Kotlin + Jetpack Glance) qui affiche ton feed daily.dev personnalisé
en petites cards sur l'écran d'accueil, à la manière de l'extension Chrome.

- **2x2** : une card héro (vignette + titre)
- **4x2** : liste de 3 cards compactes
- **4x4+** : liste scrollable de cards complètes (vignette, titre, source, ▲ upvotes, 💬 commentaires)
- Rafraîchissement périodique (WorkManager, 15 min à 3 h) + bouton ↻ manuel
- Tap sur une card → ouvre l'article

> ⚠️ Ce widget utilise l'API GraphQL **non officielle** de daily.dev
> (`https://api.daily.dev/graphql`), la même que la webapp. Elle peut changer
> sans préavis — voir « Resynchroniser la requête » ci-dessous.

## Installation

### Via GitHub Actions (recommandé)

Chaque push sur `dailydev-widget/` déclenche le workflow **Android APK** qui
publie `app-debug.apk` en artifact : onglet *Actions* → dernier run → section
*Artifacts* → télécharger, transférer sur le téléphone et installer (autoriser
les sources inconnues).

### En local

Ouvrir le dossier `dailydev-widget/` dans Android Studio, ou :

```bash
cd dailydev-widget
./gradlew :app:assembleDebug
# APK : app/build/outputs/apk/debug/app-debug.apk
```

## Configuration : récupérer le cookie de session

Le feed personnalisé nécessite ton cookie de session daily.dev :

1. Sur un ordinateur, ouvre [app.daily.dev](https://app.daily.dev) connecté.
2. Ouvre les DevTools (F12) → onglet **Network** → recharge la page.
3. Clique sur une requête **graphql** → section *Request Headers*.
4. Copie la valeur complète de l'en-tête **Cookie** (elle contient `da2=...; da3=...`).
5. Envoie-la sur ton téléphone (par exemple via une note), ouvre l'app
   **daily.dev Widget**, colle le cookie et enregistre.

Le cookie est stocké chiffré (Android Keystore) et exclu des sauvegardes.
Quand il expire, le widget affiche « Session expirée » — un tap ramène à
l'écran de configuration pour recoller un cookie frais.

## Resynchroniser la requête GraphQL

Si le widget affiche une erreur alors que le cookie est frais, le schéma a
probablement changé. Capture la vraie requête `Feed` via DevTools (même
procédure que ci-dessus, onglet *Payload*) et mets à jour
`app/src/main/java/dev/ayce/dailydev/data/api/FeedQuery.kt`.

## Checklist de test manuel

- [ ] Placer un widget 2x2, 4x2 et 4x4 → les trois layouts s'affichent
- [ ] Coller le cookie → les cards apparaissent après le refresh
- [ ] Tap sur une card → l'article s'ouvre dans le navigateur
- [ ] Bouton ↻ → le feed se rafraîchit
- [ ] Corrompre le cookie dans les réglages → card « Session expirée » au refresh suivant
- [ ] Mode avion → badge « hors ligne », le contenu en cache reste affiché
