# Landing page Hardly Working — design

## Objectif

Une page unique présentant l'app et proposant son téléchargement. Hébergée sur un sous-domaine gratuit ; **aucun nom de domaine acheté**.

**Calendrier assumé** : la page est conçue complète, bouton de téléchargement inclus, mais tant que l'Apple Developer Program (99 €/an) n'est pas souscrit, le DMG n'est pas notarisé et macOS affiche un avertissement de sécurité bloquant à l'installation. La page est donc publiée mais **pas diffusée largement** avant cette étape. Le jour où la notarisation arrive, **rien ne change dans la page**.

## Ton — décision structurante

**La blague est assumée à 100 %.** Le produit sert à faire croire qu'on travaille pendant qu'on est ailleurs, et la page le dit.

**Mais l'humour vit dans le texte, pas dans le graphisme.** Le design reste impeccable et sérieux — registre d'un lancement produit Apple — et c'est le décalage avec ce qu'il annonce qui fait rire. Le pince-sans-rire fonctionne par contraste ; une page graphiquement rigolote serait à la fois moins drôle et moins crédible au moment de télécharger.

Rien de faux sur la page : pas de preuve sociale inventée, pas de témoignages, pas de compteur d'utilisateurs. Tout ce qui est affirmé est vérifiable.

## Identité visuelle

**Palette** — dérivée de l'icône de l'app, pas de la référence Dribbble :

| Rôle | Valeur | Usage |
|---|---|---|
| Accent | `#D8792E` (ambre) | un seul accent, jamais dilué |
| Accent profond | `#B4541A` | dégradés, survols |
| Encre | `#1E1813` | titres, texte |
| Encre douce | `#6E6259` (gris chaud) | sous-titres, légendes |
| Fond | `#FDFBF8` → `#F7EDE1` | dégradé vertical très léger |
| Vert de présence | `#30D158` (vert système macOS) | la pastille, et rien d'autre |

Les gris sont **chauds**, jamais neutres : ils tirent vers l'accent.

**Typographie** — pile système Apple (San Francisco). Choix délibéré : la page présente une app macOS, elle sera lue sur des Mac, elle parle donc la langue visuelle du système. Une police « de designer » sonnerait générique là où San Francisco sonne native. Le travail typographique porte sur les tailles et l'espacement : titre très large et resserré (`letter-spacing` négatif), sous-titre aéré, capitales espacées pour les étiquettes.

**Langue** : anglais, cohérent avec l'interface de l'app et l'audience visée.

## Le verre liquide

Employé à **un seul endroit** : la maquette de barre de menus, en héros. C'est là que l'app vit réellement, et c'est le matériau que macOS 26 emploie lui-même à cet endroit — le choix est motivé, pas décoratif.

Réalisation : `backdrop-filter: blur()`, dégradé de surface très léger, liseré intérieur clair en haut (reflet spéculaire), ombre portée douce et large. **Entièrement en CSS**, aucune image, donc net sur tout écran.

L'étendre à toute la page serait l'erreur classique — la page deviendrait du plastique translucide. **Un seul point de brillance, tout le reste calme.**

## Structure — quatre blocs

### 1. Héros

- Barre de navigation minimale : icône + nom à gauche, lien GitHub à droite.
- Badge en pilule : `For macOS 14 and later`.
- Titre : **`Your green dot doesn't need you.`** — « green dot » en ambre.
- Sous-titre, deux lignes : `Hardly Working keeps your status green while you're somewhere else. Entirely. Reliably. Quietly.`
- Bouton de téléchargement, avec le poids du fichier affiché (`1.4 MB`).
- Sous le bouton, une ligne discrète tant que la notarisation n'est pas faite : `Not notarized yet — macOS will ask you to allow it in System Settings.` Se retire en une ligne le jour venu, et reste cohérente avec le bloc « ce qu'on ne te cache pas ».
- **Gag visuel doublé d'une démo réelle** : une pastille `🟢 Available` qui ne change jamais, surmontant un compteur en chiffres tabulaires — `Away for 47 minutes` — dont les minutes s'incrémentent lentement. C'est exactement ce que fait le produit, montré plutôt que raconté.
- Maquette de la barre de menus en verre, menu ouvert, dépassant par le bas du bloc (comme la référence).

### 2. Trois arguments

Une vanne franche en ouverture, puis deux arguments qui rassurent. Chaque titre est suivi d'une ligne d'appui.

| Titre | Ligne d'appui | Vérité qu'elle porte |
|---|---|---|
| *It moves the cursor by one pixel. That's the entire crime.* | Nothing opens, nothing gets selected, nothing you'd have to explain. | jamais de clic, mouvement imperceptible |
| *It tells you when it stops working.* | Most jigglers just quietly die. You find out when someone asks where you were all afternoon. | l'auto-vérification — **le seul vrai avantage sur la concurrence** |
| *It waits until you've actually left.* | While you're using your Mac, it does nothing at all. No cursor fighting, no jumping. | aucune interférence en usage réel |

> **Révision après relecture de Clément.** Deux des punchlines initiales décrivaient un mécanisme interne (« it checks that the lie landed ») ou une fierté d'ingénieur (le poids du fichier) : personne ne s'en soucie. Elles ont été remplacées par ce qui inquiète réellement quelqu'un qui envisage cet outil — *est-ce que ça va me griller*, *est-ce que ça marche vraiment*, *est-ce que ça va me gêner quand je travaille*. La deuxième ne décrit plus le mécanisme mais **la catastrophe qu'il évite**, ce qui est à la fois plus drôle et plus vendeur.

### 3. Ce qu'on ne te cache pas

La veille système et le verrouillage automatique de session ne se déclenchent plus tant que l'app est active, avec le geste de compensation (`Ctrl-Cmd-Q`). Le fait de tout dire renforce le ton au lieu de le casser — **aucun concurrent ne le mentionne**, c'est le vrai facteur de différenciation.

### 4. Pied de page

Lien GitHub, `macOS 14+`, mention de signature, et la ligne de clôture : *« A green dot has never proven anything. »*

## Contraintes techniques

- **Un seul fichier HTML autonome** : CSS en ligne, aucune ressource externe, aucune police distante, aucun script tiers. Se charge instantanément et fonctionne hors ligne.
- **Thème clair et sombre** tous les deux traités, y compris l'état « système » non marqué.
- **Responsive** : lisible sur téléphone, même si l'audience est sur Mac.
- **Accessibilité** : contrastes conformes, focus clavier visible, `prefers-reduced-motion` respecté pour le compteur animé.
- Aucune donnée collectée, aucun cookie, aucun traceur — cohérent avec le propos.

## Hébergement

Décision différée à la mise en ligne, mais le cadre est posé :

| Option | Coût | Contrainte |
|---|---|---|
| **GitHub Pages** | gratuit | impose un **dépôt public** (celui de l'app est privé) → un second dépôt public dédié au site suffit, et se met en place sans quitter le terminal |
| **Cloudflare Pages · Netlify · Vercel** | gratuit | URL plus jolie (`hardly-working.pages.dev`), fonctionne avec un dépôt privé, mais demande une autorisation navigateur de la part de Clément |
| Nom de domaine | ~10-15 €/an | optionnel, se greffe plus tard sans rien refaire |

## Hors périmètre

- Collecte d'adresses e-mail (imposerait un service tiers).
- Démonstration animée du compteur d'inactivité, questions fréquentes, captures multiples — écartés au cadrage au profit d'une page courte.
- Traduction française — l'anglais suffit pour la v1.
- Toute mesure d'audience.
