# daily.dev Widget

Widget Android (Kotlin + Jetpack Glance) qui affiche ton feed daily.dev personnalisé
en petites cards sur l'écran d'accueil, à la manière de l'extension Chrome.

- **2x2** : une card héro (vignette + titre)
- **Plus grand** : liste scrollable de grandes cards façon extension (logo + source, titre, date · temps de lecture, image pleine largeur, ▲ upvotes, 💬 commentaires)
- **« Charger plus »** en bas de liste : va chercher la page suivante du feed (plafonné à 30 articles — les widgets Android ne peuvent pas détecter le scroll pour charger automatiquement)
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

## Configuration : se connecter

Tout se fait depuis le téléphone :

1. Ouvre l'app **daily.dev Widget** → bouton **« Se connecter à daily.dev »**.
2. Connecte-toi dans la page qui s'ouvre — **GitHub ou email + mot de passe
   recommandés** (Google peut refuser la connexion dans une vue intégrée).
3. Dès que la connexion aboutit, le cookie de session est capturé et validé
   automatiquement, l'écran se ferme et le widget se rafraîchit.

Le cookie est stocké chiffré (Android Keystore) et exclu des sauvegardes.
Quand il expire, le widget affiche « Session expirée » — un tap rouvre la
page de connexion ; si la session y est encore active, le cookie se
recapture tout seul, sans re-login.

## Resynchroniser la requête GraphQL

Si le widget affiche une erreur alors que le cookie est frais, le schéma a
probablement changé. Capture la vraie requête `Feed` via DevTools (même
procédure que ci-dessus, onglet *Payload*) et mets à jour
`app/src/main/java/dev/ayce/dailydev/data/api/FeedQuery.kt`.

## Checklist de test manuel

- [ ] Placer un widget 2x2, 4x2 et 4x4 → les trois layouts s'affichent
- [ ] « Se connecter à daily.dev » (GitHub ou email) → capture automatique, les cards apparaissent
- [ ] Tap sur une card → l'article s'ouvre dans le navigateur
- [ ] Bouton ↻ → le feed se rafraîchit
- [ ] Corrompre le cookie dans les réglages → card « Session expirée » au refresh suivant
- [ ] Mode avion → badge « hors ligne », le contenu en cache reste affiché
