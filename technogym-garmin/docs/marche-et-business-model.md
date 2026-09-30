# Spotter for Technogym : analyse de marché et business model

Etat au 30 septembre 2026. Chiffres publics, sources en fin de document. Les estimations sont signalees comme
telles, avec les hypotheses qui les produisent, pour pouvoir les refaire quand une donnee change.

## En une page

* Technogym revendique 70 millions de personnes qui s'entrainent sur ses equipements, 100 000 centres et
  22 millions d'utilisateurs enregistres sur Mywellness. Garmin compte environ 45 millions d'utilisateurs actifs
  de Garmin Connect (estimation, Garmin ne publie pas le chiffre) et 15 % des montres connectees vendues au
  T2 2026, en croissance sur le segment premium.
* Le croisement "s'entraine dans une salle Technogym connectee" et "porte une Garmin" represente, selon nos
  hypotheses, **300 000 a 800 000 personnes dans le monde**, dont la moitie en Europe. C'est une niche, mais une
  niche solvable et frustree : le besoin "mes seances Technogym dans Garmin" est documente sur les forums Garmin
  depuis 2021 et l'integration officielle Technogym x Garmin ne va que dans un sens (donnees Garmin vers l'app
  Technogym).
* Sur le store Connect IQ, la meilleure app de musculation (F3b Strength Training+, 3 $) depasse 100 000
  telechargements en six ans ; les autres sont a 10 000 et 50 000. **Objectif realiste pour Spotter : 5 000 a
  30 000 installations en trois ans**, avec 10 a 25 % de payants a 4,99 EUR, soit 20 000 a 100 000 EUR de revenu
  cumule en vente directe. Ce n'est pas une entreprise, c'est un produit rentable pour une personne.
* La valeur est ailleurs : Spotter est la seule app qui met une seance Technogym en direct au poignet d'une
  Garmin. Le business model qui change d'echelle est **B2B (salles et chaines equipees Technogym) ou un partenariat
  avec Technogym**, dont le positionnement "ecosysteme ouvert" et le programme partenaires (Enterprise API) rendent
  la conversation possible. La vente directe sert alors de preuve (utilisateurs, notes, retention).
* Prerequis avant tout argent : passer de l'API privee a un accord API Technogym (partenaire Enterprise API) et
  publier une politique de confidentialite pour le relais. Sans cela, le produit peut etre coupe du jour au
  lendemain.

## 1. Le marche en chiffres

### Technogym

| Donnee | Valeur | Source |
| --- | --- | --- |
| Chiffre d'affaires 2024 | 901 M EUR (+11,5 %), B2B 717 M, particuliers 184 M | communique FY 2024 |
| Personnes qui s'entrainent sur Technogym | "plus de 70 millions", 100 000 centres, 500 000 foyers | communique FY 2024 |
| Utilisateurs enregistres Mywellness | plus de 22 millions, 23 000 centres connectes | rapport annuel 2024 |
| Europe hors Italie | 416 M EUR, 46 % du CA ; l'Italie est le pays le mieux penetre | communique FY 2024 |
| App "Technogym" (Google Play) | 1 M+ telechargements, 4,4 / 5 sur 26 000 avis | Google Play |
| Ancienne app "mywellness" | 1 M+ telechargements, 2,5 / 5, retiree du Play Store en aout 2025 | Google Play, AppBrain |
| Strategie 2025 | "Healthness", IA, "trillions de donnees" de l'ecosysteme, ecosysteme ouvert | communique FY 2024 |

Lecture : les 70 millions comptent toute personne ayant couru sur un tapis Technogym, hotel compris. La base
qui nous concerne est celle des comptes Mywellness (22 millions d'inscrits) : ce sont les gens qui badgent sur
les equipements et dont la seance existe dans le cloud, donc ceux que Spotter peut suivre.

### Garmin et Connect IQ

| Donnee | Valeur | Source |
| --- | --- | --- |
| Utilisateurs actifs Garmin Connect | environ 45 M (fourchette 42 a 49 M), estimation | the5krunner 2026 |
| Segment Fitness 2024 | 1,77 Md USD, +32 % | Garmin 10-K |
| Part de marche montres connectees | 11 % (T2 2024), 15 % (T2 2026), a egalite avec Samsung | Counterpoint, Omdia |
| Europe | 15 % du marche mondial des montres connectees | Counterpoint |
| Apps payantes Connect IQ | depuis aout 2024, via Garmin Pay, 100 USD/an de frais developpeur, 15 % de commission, prix par paliers, 4,99 USD recommande, garantie 48 h | Garmin, the5krunner |
| Apps de musculation sur le store | F3b Strength Training+ : 100 000+ telechargements, 3 USD, 4,0 / 5 ; GymRun : 50 000+ ; Custom Workouts : 10 000+ | apps.garmin.com |
| Ordre de grandeur des stars du store | Spotify 10 M+, cadran GLANCE 1 M+ | apps.garmin.com |

Lecture : Garmin gagne des parts sur le premium, exactement le profil qui paie une app a 5 EUR. Mais une app de
musculation Connect IQ reste un produit de niche : 100 000 telechargements en six ans pour la meilleure, gratuite
pendant 10 minutes puis 3 USD.

### Salles de sport et montres

| Donnee | Valeur | Source |
| --- | --- | --- |
| Membres de salles en Europe 2024 | 71,6 M, penetration 8,9 % | EuropeActive / Deloitte 2025 |
| Membres qui possedent une montre ou un tracker | 40 % (Etats-Unis) | Glofox |
| Apps de suivi de muscu | Hevy : 5 a 16 M d'utilisateurs selon la source, environ 2 M USD/an de revenu, sans marketing paye | Hevy, RevenueCat, OBJ |

Lecture : les gens paient deja pour suivre leurs series (Hevy, Strong), a la main, sur telephone. Spotter fait la
saisie a leur place a partir des machines.

## 2. Combien de personnes pourraient etre interessees

Entonnoir, du plus large au plus etroit. Chaque etape est une hypothese explicite.

| Etape | Hypothese | Bas | Haut |
| --- | --- | --- | --- |
| Comptes Mywellness enregistres | chiffre Technogym | 22 M | 22 M |
| dont actifs (badgent au moins une fois par mois) | 25 % a 40 % des inscrits (les comptes crees a l'inscription en salle puis oublies sont nombreux) | 5,5 M | 8,8 M |
| dont porteurs d'une montre connectee | 35 % a 45 % (40 % des membres US possedent un tracker ou une montre ; plus en salle premium) | 1,9 M | 4,0 M |
| dont Garmin | 12 % a 20 % (15 % de parts mondiales, plus en Europe et chez les sportifs d'endurance qui frequentent les salles Technogym premium) | 230 k | 790 k |
| dont montre compatible (Connect IQ 4+, System 7 pour le paiement) | 80 % a 90 % du parc Garmin recent | **190 k** | **710 k** |

Contre-verification par le cote Garmin : 45 M d'utilisateurs actifs, 30 a 40 % membres d'une salle (13 a 18 M),
salle equipee Technogym avec Mywellness actif dans 5 a 8 % des cas hors Italie (23 000 centres connectes sur
environ 300 000 salles dans le monde, mais surrepresentes dans le premium ou sont les Garmin), soit 650 k a 1,4 M.
Les deux approches se recoupent autour de **quelques centaines de milliers de personnes**, dont environ la moitie
en Europe (Italie, Royaume-Uni, Allemagne, France, Espagne, Benelux) et une part notable dans les hotels et
clubs premium (Middle East, Etats-Unis).

Marche adressable en pratique (ceux qu'on peut atteindre par le store Connect IQ, avec un bouche a oreille dans
les salles et les forums Garmin) : les apps de musculation du store plafonnent a 100 000 installations. Une app
qui ne sert qu'aux clients Technogym vise plus bas : **5 000 a 30 000 installations en trois ans** est l'objectif
credible, 50 000 le scenario optimiste avec le relais de Technogym ou d'une chaine.

Qui sont-ils : des adultes 30 a 55 ans, deja "quantifies" (ils portent une Garmin, ils veulent la seance dans
Garmin Connect pour leur charge d'entrainement), membres de salles moyennes et premium, souvent coureurs ou
cyclistes qui font de la muscu en complement. Le besoin exprime sur les forums Garmin depuis 2021 : "Does anybody
actually know how to get activities from Technogym Mywellness to Garmin Connect ?", sans reponse de Garmin ni de
Technogym. L'integration officielle annoncee par Technogym (programme Garmin Connect Developer) fait l'inverse :
elle amene sommeil, VFC et repos de la Garmin vers l'app Technogym.

## 3. Concurrence et substituts

| Solution | Ce qu'elle fait | Ce qu'elle ne fait pas |
| --- | --- | --- |
| App Technogym (telephone) | seance guidee, badge, historique, MOVEs | rien au poignet Garmin ; seance non exportee vers Garmin Connect |
| Integration officielle Technogym x Garmin | donnees sante Garmin dans l'app Technogym | sens inverse absent ; pas de direct |
| Activite Musculation Garmin native | compteur de reps, FC, FIT | ignore les machines, pas de programme Technogym, pas de charge machine |
| F3b Strength Training+, GymRun, Custom Workouts (Connect IQ) | saisie de series au poignet, calories, programmes | aucune connexion aux equipements de la salle |
| Hevy, Strong, Jefit (telephone) | journal de seances, social, progression, 2 M USD/an pour Hevy | saisie manuelle ; integration Garmin limitee |
| Apple Watch | l'app Technogym vise iOS en priorite (a verifier : compagnon Apple Watch) | hors marche Garmin |

Personne ne fait "la seance Technogym en direct sur une Garmin, avec ecriture retour dans Technogym". C'est
etroit, mais c'est libre, et la barriere technique (API Mywellness, limites de Connect IQ, relais) n'est pas
nulle.

## 4. Business models possibles

### A. App payante sur le store Connect IQ (vente directe)

* Mecanique : palier 4,99 EUR (recommandation Garmin), paiement Garmin Pay, 15 % de commission, 100 USD/an de
  frais developpeur, essai gratuit possible via l'API de trial. Achat lie au compte, valable sur toutes les
  montres de l'utilisateur.
* Scenarios de revenu cumule sur trois ans (prix 4,99 EUR, 85 % net) :

| Installations | Conversion payante | Payants | Revenu net cumule |
| --- | --- | --- | --- |
| 5 000 | 15 % | 750 | 3 200 EUR |
| 15 000 | 20 % | 3 000 | 12 700 EUR |
| 30 000 | 25 % | 7 500 | 31 800 EUR |
| 30 000, tout payant (pas de version gratuite) | 100 % | 30 000 | 127 000 EUR |

* Couts : relais Cloudflare (gratuit jusqu'a 100 000 requetes par jour ; une montre fait environ 400 requetes par
  seance, donc 250 seances par jour gratuites, ensuite 5 USD par mois), 100 USD Garmin, un nom de domaine, du
  temps de support. Marge quasi totale.
* Verdict : viable comme revenu d'appoint et comme preuve de traction, pas comme activite principale.

### B. Gratuit + abonnement "Pro"

* Gratuit : suivi en direct, FC, MOVEs. Pro (12 a 20 EUR/an) : historique et records, carte des muscles,
  calcul des disques, exercices libres avec compteur, export de la seance comme activite Musculation detaillee.
* L'abonnement recurrent passe mal dans Connect IQ (paliers Garmin Pay penses pour l'achat unique ; un paiement
  externe type Stripe est tolere mais ajoute de la friction sur une montre). Hevy prouve qu'un public paie 3 a
  4 USD par mois pour un journal de muscu, mais sur telephone.
* Verdict : a garder pour plus tard, si une app compagnon telephone voit le jour. Sur la montre seule, l'achat
  unique est plus simple.

### C. B2B : salles et chaines equipees Technogym

* Proposition : "vos membres Garmin voient leur seance au poignet et la retrouvent dans Garmin Connect", vendu
  comme service d'engagement (la retention est le probleme numero un des salles ; le membre qui voit ses
  progres reste). Marque blanche possible ("Spotter pour [Club]").
* Mecanique : accord API Technogym par le club (le club obtient sa facility URL et sa cle API Enterprise et
  les delegue au relais), donc plus d'API privee ni d'identifiants utilisateur dans la montre. Prix indicatif
  20 a 50 EUR par club et par mois, ou 0,50 a 1 EUR par membre actif Garmin et par mois.
* Cibles : chaines premium equipees Technogym en Europe (clubs a forte proportion de sportifs), hotels et
  clubs d'entreprise, salles independantes haut de gamme. Il faut verifier club par club la presence de
  Mywellness actif.
* Verdict : c'est la ou le revenu change d'echelle (100 clubs a 30 EUR = 36 000 EUR par an, recurrents), mais
  cela demande de vendre, du support, un contrat et une conformite RGPD serieuse. A n'ouvrir qu'avec des
  utilisateurs et des chiffres de retention en main.

### D. Partenariat ou rachat par Technogym

* Technogym vend un "ecosysteme ouvert", possede un programme partenaires (Enterprise API : demande au
  representant local, accord API, cle en trois jours ouvres) et collabore deja avec Garmin. Une app Connect IQ
  qui prolonge la seance Technogym au poignet sert leur discours "Healthness" et leur retention B2B.
* Chemin : d'abord la traction (quelques milliers d'utilisateurs, notes, retours de salles), un dossier chiffre
  (cette page), puis contact Technogym Digital (Cesena) avec deux options : Spotter devient l'app Connect IQ
  officielle (licence ou rachat), ou Technogym l'integre a son propre programme partenaires (Spotter garde son
  independance et un acces API legitime).
* Risque symetrique : Technogym peut le faire seul. Mais il ne l'a pas fait depuis l'ouverture du store
  Connect IQ en 2015 ; leur priorite est l'app telephone et Apple.

### E. Ce qu'on ecarte

* Publicite ou sponsoring : incompatible avec une montre et un public payant.
* Vente de donnees : hors de question, et contraire au positionnement "le relais ne conserve rien".

## 5. Recommandation

1. **Legitimer l'acces** : demander un accord Enterprise API a Technogym au titre de partenaire developpeur
   (formulaire au representant local : nom du logiciel, scenario d'integration, contact). Meme si la reponse
   tarde, la demande documente la bonne foi. En parallele, publier une politique de confidentialite pour le
   relais (identifiants transmis, jamais stockes, hebergement Cloudflare, journaux desactives).
2. **Beta publique gratuite sur le store** (3 a 6 mois) : objectif 500 a 2 000 utilisateurs, recueil de
   retention (seances par semaine) et d'avis. Canaux : forums Garmin (les fils "Technogym vers Garmin Connect"),
   Reddit r/Garmin et r/technogym, les salles frequentees, la fiche store optimisee sur "Technogym".
3. **Passage au payant** a 4,99 EUR avec essai gratuit 14 jours, en gardant la lecture du direct gratuite si la
   base est petite (la valeur percue est dans l'exercice libre, l'historique et les records).
4. **Dossier B2B et Technogym** a 2 000 utilisateurs : retention, NPS, captures reelles, cette analyse.
   Premiers rendez-vous avec deux ou trois clubs premium equipes Technogym, puis Technogym.

## 6. Risques

| Risque | Gravite | Parade |
| --- | --- | --- |
| API Mywellness privee : coupure, changement, ou demande de retrait | forte | accord Enterprise API (etape 1), relais qui isole la montre des changements |
| Identifiants Technogym qui transitent par le relais | forte (RGPD, confiance) | pas de stockage, jeton en memoire seulement, politique de confidentialite, hebergement UE ; a terme OAuth ou cle par club |
| Technogym lance sa propre app Connect IQ | moyenne | vitesse, qualite, et proposer le partenariat avant |
| Relecture du store Connect IQ (nom, marque "Technogym") | moyenne | "for Technogym", mention non officielle, aucun logo, phrase de non-affiliation |
| Marche trop etroit | moyenne | c'est une niche assumee ; le B2B ou le partenariat font l'echelle, pas la vente directe |
| Support et compatibilite montres | faible | limiter aux modeles testes, FAQ, journal de diagnostic dans l'app |

## Sources

* Technogym, communique de resultats FY 2024 (901 M EUR, 70 M de personnes, 100 000 centres, Europe 416 M) :
  https://corporate.technogym.com/~/media/Files/T/Technogym-Corporate/investor-relations/shareholder-meetings/2025/technogym-fy-2024-results-press-release-eng-v1.pdf
* Technogym, rapport annuel 2024 (22 M d'utilisateurs Mywellness, 23 000 centres connectes) :
  https://corporate.technogym.com/~/media/Files/T/Technogym-Corporate/reports-and-presentation/2024/annual-report-2024-en.pdf
* Athletech News, Technogym tops 900 M EUR : https://athletechnews.com/technogym-tops-e900m-in-revenue/
* Technogym, integration etendue avec Garmin (donnees Garmin vers l'app Technogym) :
  https://www.technogym.com/en-US/stories/technogym-garmin-extended-integration/
* Technogym Enterprise API et processus partenaire : https://openplatformdocs.mywellness.com/ et
  https://help.perfectgym.com/hc/en-001/articles/39319250188433-Technogym-MyWellness-CRM-and-PerfectGym-Integration-Process-and-Frequently-Asked-Questions
* App Technogym sur Google Play : https://play.google.com/store/apps/details?id=com.technogym.tgapp&hl=en_US
* Forum Garmin, "Technogym Mywellness no exporting activity data to Garmin Connect" (2021) :
  https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/281645/technogym-mywellness-no-exporting-activity-data-to-garmin-connect
* the5krunner, estimation des utilisateurs Garmin Connect (45 M) : https://the5krunner.com/2026/05/01/garmin-connect-users-2026/
* the5krunner, Garmin a egalite avec Samsung (15 %, T2 2026) : https://the5krunner.com/2026/08/19/garmin-samsung-smartwatch-share/
* Garmin, 10-K 2024 (segment Fitness 1,77 Md USD) : https://www.sec.gov/Archives/edgar/data/1121788/000095017025057074/grmn-ars-20241228.pdf
* Garmin, apps payantes Connect IQ (aout 2024) :
  https://www.garmin.com/en-US/newsroom/press-release/wearables-health/garmin-enables-premium-app-purchases-in-the-connect-iq-store-and-unveils-fun-new-watch-faces-and-apps/
* the5krunner, conditions des apps payantes (100 USD, 15 %, paliers) :
  https://the5krunner.com/2024/08/07/garmin-connect-iq-store-allows-paid-for-apps-using-garmin-pay/
* F3b Strength Training+ (100 000+, 3 USD) : https://apps.garmin.com/en-US/apps/2b2e6e1c-81d2-48b5-8f1b-9ca7c77c3b96
* GymRun (50 000+) : https://apps.garmin.com/en-US/apps/a501e68d-9837-43ca-a08d-012cc85ec4db
* EuropeActive / Deloitte, marche europeen 2025 (71,6 M de membres) :
  https://www.healthclubmanagement.co.uk/health-club-management-news/European-fitness-sector-shows-strong-growth-reveals-EuropeActive-and-Deloitte/355485
* Glofox, statistiques d'adhesion (40 % des membres US possedent une montre ou un tracker) :
  https://www.glofox.com/blog/gym-membership-statistics/
* Hevy, revenu et utilisateurs : https://www.starterstory.com/hevy-breakdown et
  https://www.revenuecat.com/blog/growth/guillem-ros-hevy-podcast
