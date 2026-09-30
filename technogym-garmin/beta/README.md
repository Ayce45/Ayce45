# Backend beta a la demande (GitHub Actions)

Option secondaire : le relais Cloudflare (`relay/`) est plus simple et permanent, voir le README principal.

La GitHub Action `beta-backend` (onglet Actions du depot, bouton "Run workflow", utilisable depuis
l'app GitHub sur telephone) demarre ce backend sur un runner GitHub, l'expose par un tunnel Cloudflare
sans compte (`https://xxx.trycloudflare.com`) et ecrit l'URL dans `beta/backend.txt` sur la branche.
La montre lit ce fichier au demarrage (reglage `discoveryUrl`) : pas besoin de retaper l'URL, qui change
a chaque lancement.

Secrets a definir dans le depot (Settings > Secrets and variables > Actions) :

| Secret | Contenu |
| --- | --- |
| `MYWELLNESS_EMAIL` | identifiant Technogym / Mywellness |
| `MYWELLNESS_PASSWORD` | mot de passe |
| `PAIR_TOKEN` | token d'appairage, le meme que celui compile dans le `.prg` de la montre |
| `ADMIN_TOKEN` | un mot de passe admin quelconque (endpoints admin) |

Limites : un lancement dure au plus 6 h (defaut 3 h), l'URL change a chaque lancement, aucune donnee
n'est conservee entre deux lancements (les pulsations et resultats sont perdus a l'arret). C'est un
banc de test pour la beta, pas un hebergement : pour une utilisation reguliere, passer au relais
Cloudflare Worker ou a un backend heberge (voir README principal).
