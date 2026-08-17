# Hardly Working — design

## Problème

Quand Clément s'éloigne de son Mac, Teams bascule son statut en « away » (pastille orange) au bout de quelques minutes. Il ne veut pas que son absence soit visible : l'objectif est de **maintenir la pastille verte pendant qu'il est loin du poste**, sans y penser et sans que ça interfère quand il utilise réellement la machine.

Une première version en bash existe (`Code/teams-presence/`, fonctionnelle). Elle résout le problème mais souffre de trois fragilités structurelles, toutes liées au fait que c'est un script lancé par `launchd` :

1. **Dépendance à Homebrew** — nécessite `cliclick`, à installer séparément ; impossible à distribuer à quelqu'un d'autre sans lui faire installer Homebrew.
2. **Permission Accessibilité instable** — la permission est attachée au chemin versionné du binaire (`.../cliclick/5.1/bin/cliclick`) ; un `brew upgrade cliclick` la révoque silencieusement. Aucune popup ne peut la redemander (un job `launchd` sans interface ne peut pas afficher de dialogue).
3. **Protection TCC de `~/Documents`** — a nécessité un contournement (déploiement d'une copie du script hors zone protégée) qui impose de relancer `install.sh` après chaque modification.

Cette v2 est une **vraie application macOS native**, ce qui supprime les trois d'un coup : pas de dépendance externe, permission demandée par une vraie popup et attachée à l'identité stable de l'app, et une app dans `/Applications` n'est pas concernée par la protection de `~/Documents`.

## Identité

- **Nom** : Hardly Working — jeu de mots anglais (« working hard, or hardly working ? ») : sonne comme « travailleur acharné », signifie « en train de ne rien faire ». Vérifié libre : aucune app macOS de ce nom trouvée. (« Look Busy », premier choix, est déjà pris par [lookbusy.app](https://lookbusy.app/).)
- **Identifiant de paquet** : `com.madzar.hardlyworking`
- **Cible** : macOS 14 minimum (requis par `MenuBarExtra` et `SMAppService`), Apple Silicon et Intel.

## Architecture

Une application Swift/SwiftUI unique, **sans aucune dépendance externe**, livrée sous forme de paquet `.app` dans un fichier `.dmg`. L'app est de type *agent* (`LSUIElement`) : aucune icône dans le Dock, aucune fenêtre principale, uniquement une icône dans la barre de statut.

Découpage en unités courtes à responsabilité unique, avec la logique de décision isolée du système pour rester testable :

| Fichier | Responsabilité | Dépend de |
|---|---|---|
| `HardlyWorkingApp.swift` | Point d'entrée, scène `MenuBarExtra`, câblage des composants | tous |
| `IdleMonitor.swift` | Lire le temps d'inactivité système, en secondes | système (`CGEventSource`) |
| `Jiggler.swift` | Exécuter le micro-mouvement de souris | système (`CGEvent`) |
| `PresenceController.swift` | Chef d'orchestre : minuterie, décision, état courant | `IdleMonitor`, `Jiggler`, `Settings` |
| `Settings.swift` | Préférences persistées | `UserDefaults` |
| `AccessibilityPermission.swift` | Vérifier / demander la permission Accessibilité | système (`AXIsProcessTrusted`) |
| `LoginItem.swift` | Activer / désactiver le lancement au démarrage | `SMAppService` |
| `MenuView.swift` | Interface du menu de la barre de statut | `PresenceController`, `Settings` |

**Frontière testable** : la décision « faut-il bouger la souris maintenant ? » est une fonction pure prenant (temps d'inactivité, seuil, actif ou non) et ne touchant à rien. Les accès système (`IdleMonitor`, `Jiggler`) sont des adaptateurs fins, injectables par protocole pour permettre de tester `PresenceController` sans bouger la vraie souris.

## Mécanismes techniques

### Détection de l'inactivité

`CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: <tous types>)` renvoie le nombre de secondes écoulées depuis le dernier événement clavier/souris. **C'est le même compteur que celui lu par Teams** (et par Slack, Discord…). Remplace l'appel à `ioreg` de la v1.

> À vérifier dès la première tâche d'implémentation : la constante exacte représentant « n'importe quel type d'événement » et le bon paramètre de source (`.hidSystemState` vs `.combinedSessionState`). L'implémentation doit comparer la valeur retournée à celle de `ioreg -c IOHIDSystem` (référence connue) avant de construire quoi que ce soit dessus.

### Le mouvement de souris

Envoi d'un événement souris natif : déplacement de +1 pixel puis retour de −1 pixel, posté sur le tap d'événements HID. C'est le mécanisme qu'utilise `cliclick` en interne, et la v1 a **mesuré** qu'il réinitialise effectivement le compteur d'inactivité et maintient Teams en vert. Le risque technique est donc faible, mais reste à confirmer explicitement.

Le mouvement doit rester imperceptible (1 pixel, aller-retour immédiat) et ne **jamais** émettre de clic.

### Lancement au démarrage

`SMAppService.mainApp.register()` / `.unregister()`. L'app apparaît alors dans Réglages Système → Général → Ouverture, où l'utilisateur garde le contrôle. Remplace le fichier LaunchAgent de la v1.

### Permission Accessibilité

Vérification via `AXIsProcessTrusted()`. Si absente, l'app :
- affiche l'icône de barre de statut en **état d'alerte** (visuellement distinct d'actif et d'en pause) ;
- affiche dans le menu une ligne d'explication et un bouton ouvrant directement le panneau Réglages Système → Confidentialité et sécurité → Accessibilité ;
- ne prétend jamais être active alors qu'elle ne peut rien faire.

Contrairement à la v1, l'app peut ici déclencher une vraie demande système, et la permission est attachée à l'identité du paquet (identifiant + signature), donc stable d'une version à l'autre.

## Rendre les pannes visibles

C'est la faiblesse n°1 corrigée par rapport à la v1 : quand elle cassait, elle ne faisait rien, silencieusement, sans que rien ne l'indique.

**Auto-vérification** : après chaque mouvement, `PresenceController` **relit le temps d'inactivité**. S'il n'est pas retombé sous le seuil, le mouvement n'a pas eu l'effet attendu → l'app bascule en état d'alerte et l'explique dans le menu. Cette seule vérification attrape toutes les pannes connues et à venir (permission révoquée, API changée, restriction macOS nouvelle), qui se présentent toutes identiquement : « l'app tourne, mais ne fait rien ».

L'état d'alerte est **transitoire, jamais collant** : il se lève automatiquement dès qu'un mouvement suivant réussit. Aucune action de l'utilisateur n'est requise pour l'effacer — sinon une panne passagère laisserait une alerte trompeuse en permanence.

## Interface

Trois états visuels de l'icône dans la barre de statut : **actif**, **en pause**, **alerte** (permission manquante ou mouvement sans effet). Icônes issues de SF Symbols, donc adaptées automatiquement au thème clair/sombre sans chaîne graphique à maintenir.

Menu déroulant (validé) :

```
┌────────────────────────────────┐
│  ✓  Actif                      │
├────────────────────────────────┤
│     Inactivité : 4 min      ▸  │   sous-menu : 2 / 3 / 4 / 5 / 10 min
│     Lancer au démarrage     ✓  │
├────────────────────────────────┤
│     Quitter                ⌘Q  │
└────────────────────────────────┘
```

> Le schéma illustre un état d'exemple où l'utilisateur a **déjà activé** le lancement au démarrage. Par défaut cette case est décochée (voir Réglages ci-dessous) : une app distribuée ne s'ajoute pas au démarrage sans un geste explicite.

En état d'alerte, une ligne d'explication et un bouton d'action s'ajoutent en tête du menu.

## Réglages et valeurs par défaut

Persistés dans `UserDefaults` :

| Réglage | Défaut | Notes |
|---|---|---|
| Actif | activé | dès le premier lancement, une fois la permission accordée |
| Seuil d'inactivité | 4 min (240 s) | Microsoft ne documente pas le vrai seuil Teams (~5 min estimé) ; d'où le réglage exposé dans le menu |
| Fréquence de vérification | 20 s | non exposé dans l'interface (détail d'implémentation) |
| Lancer au démarrage | désactivé | choix explicite de l'utilisateur, jamais imposé |

Quand l'app est en pause, la minuterie est **arrêtée** (aucun sondage en tâche de fond), pas seulement ignorée.

## Effet de bord assumé

Le compteur d'inactivité réinitialisé est aussi celui qui déclenche la mise en veille système : **le Mac ne se met plus en veille tout seul** tant que l'app est active. Déjà constaté et accepté sur la v1. L'interrupteur du menu rend désormais cet effet **contrôlable** (couper en partant le soir), ce qui n'était pas le cas avant.

## Distribution

`scripts/build-dmg.sh` : compile en Release, signe avec le certificat *Apple Development* existant, et produit un `.dmg` avec la disposition classique « glisser vers Applications ».

**Signature et notarisation** : non incluses dans cette version. Distribuer publiquement une app sans certificat *Developer ID* + notarisation impose à l'utilisateur, depuis macOS 15, un passage par Réglages Système → Confidentialité et sécurité → « Ouvrir quand même » avec mot de passe administrateur (le contournement clic-droit → Ouvrir a été supprimé). Y remédier nécessite l'Apple Developer Program (99 €/an) — décision différée volontairement.

L'architecture doit garantir que cet ajout futur ne soit **que deux commandes de plus** dans `build-dmg.sh` (`codesign` avec l'identité Developer ID, puis `notarytool submit` et `stapler staple`), sans rien réarchitecturer.

## Retrait de la v1

Une fois la v2 installée et vérifiée :
- désinstaller le service bash (`Code/teams-presence/uninstall.sh`) — les deux ne doivent jamais tourner en même temps ;
- ajouter un renvoi en tête du `README.md` de `teams-presence` indiquant qu'il est remplacé par Hardly Working ;
- le dépôt `teams-presence` est **conservé** comme historique (il contient l'enquête TCC, réutilisable).

## Hors périmètre (YAGNI)

- **Landing page / site de téléchargement** — deuxième projet, à concevoir une fois l'app existante.
- **Notarisation et certificat Developer ID** — voir Distribution ; décision différée.
- **Publication sur l'App Store** — la revue éditoriale rejetterait probablement ce type d'outil, et ce n'est pas l'objectif.
- **Pause temporaire à réactivation automatique**, **plages horaires**, **ligne d'état en direct dans le menu** — écartés lors du cadrage au profit du menu « essentiel ».
- **Icônes personnalisées / identité graphique** — SF Symbols suffit pour une v1.
- **Support macOS 13 et antérieur.**

## Tests

**Automatisés** (unitaires, sans toucher au système) :
- la décision de déclenchement selon (inactivité, seuil, état actif) — y compris la limite exacte du seuil ;
- les transitions d'état (actif ↔ pause ↔ alerte), notamment que la minuterie s'arrête réellement en pause ;
- la persistance des réglages ;
- la logique d'auto-vérification : un mouvement dont le compteur ne retombe pas doit produire l'état d'alerte.

`IdleMonitor` et `Jiggler` sont injectés par protocole, donc remplaçables par des doublures de test — c'est ce qui permet de tester `PresenceController` sans bouger la vraie souris ni attendre 4 minutes.

**Manuel** (indispensable — c'est le seul test qui prouve que le produit remplit sa fonction) :
- laisser le Mac inactif 5-6 minutes avec Teams ouvert et l'app active, constater que la pastille reste verte ;
- vérifier qu'en usage normal (souris utilisée), aucun mouvement parasite ni clic n'a lieu ;
- couper via le menu, constater que Teams repasse en orange après quelques minutes ;
- révoquer la permission Accessibilité dans les Réglages et vérifier que l'app bascule bien en état d'alerte au lieu de faire semblant de fonctionner.

## Risques identifiés

| Risque | Gravité | Traitement |
|---|---|---|
| L'API `CGEventSource` ne renvoie pas le compteur attendu | bloquant | vérifié en tâche 1, croisé avec `ioreg` avant de construire dessus |
| L'événement synthétisé ne réinitialise pas le compteur | bloquant | même mécanisme que `cliclick`, déjà mesuré sur la v1 ; confirmé en tâche 1 |
| macOS durcit encore les permissions | latent | l'auto-vérification rend la panne visible au lieu de silencieuse |
| Le nom se révèle déjà déposé | faible | recherche effectuée, aucun conflit ; à revérifier avant publication publique |
