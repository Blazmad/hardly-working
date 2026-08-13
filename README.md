# Hardly Working

Une petite app macOS en barre de statut qui empêche Teams (ou Slack, Discord…) de vous afficher « away » quand vous vous éloignez de votre Mac.

*Working hard, or hardly working?*

## Comment ça marche

Teams s'appuie sur le compteur d'inactivité de macOS : le temps écoulé depuis votre dernière action clavier ou souris. Hardly Working consulte ce compteur toutes les 20 secondes et, dès qu'il dépasse le seuil choisi, déplace le curseur d'un pixel puis le remet exactement où il était — imperceptible, sans jamais cliquer, et sans aucune gêne si vous êtes en train d'utiliser la souris.

Après chaque mouvement, l'app attend une fraction de seconde (le temps que macOS enregistre le geste) puis **vérifie que le compteur est bien retombé**. Un raté isolé ne déclenche rien : il faut **deux échecs consécutifs** pour que l'icône passe en alerte — un aléa ponctuel ne doit pas crier au loup. Une fois l'alerte levée, seul un mouvement qui réussit à nouveau à faire retomber le compteur peut l'effacer : décocher puis recocher « Active » ne suffit pas. L'app ne prétend jamais fonctionner quand ce n'est pas le cas.

## Installation

1. Ouvrir `Hardly Working.dmg` et glisser l'app dans Applications.
2. Lancer l'app — une icône de tasse apparaît dans la barre de menus.
3. **Accorder la permission Accessibilité** (obligatoire) : l'app l'indique au premier lancement et ouvre le bon panneau. Cocher « Hardly Working » dans Réglages Système → Confidentialité et sécurité → Accessibilité. Sans cette permission, macOS interdit tout mouvement de souris synthétique.

## Le menu

| Élément | Rôle |
|---|---|
| **Active** | L'interrupteur principal. Décoché, l'app ne surveille plus rien du tout. |
| **Idle threshold** | Délai d'inactivité avant d'agir : 2, 3, 4, 5 ou 10 min. Défaut : 4 min. |
| **Launch at login** | Démarrage automatique à l'ouverture de session. Désactivé par défaut. |

L'icône reflète l'état : tasse pleine (actif), tasse vide (en pause), triangle (problème à régler).

### Régler le seuil

Microsoft ne publie pas le délai exact au bout duquel Teams bascule en « away » (~5 min d'après nos mesures). Le défaut de 4 min passe juste en dessous. Si votre statut bascule quand même, descendre à 3 ou 2 min.

## À savoir

**Votre Mac ne se mettra plus en veille tout seul** tant que l'app est active : c'est le même compteur d'inactivité qui déclenche la veille. Décochez « Active » en partant le soir, ou fermez simplement le capot.

## Construire depuis les sources

Nécessite Xcode et XcodeGen (`brew install xcodegen`).

```bash
xcodegen generate                         # génère le projet Xcode depuis project.yml
open HardlyWorking.xcodeproj              # pour développer et déboguer
bash scripts/build-dmg.sh                 # construit l'app et produit dist/Hardly Working.dmg
```

`project.yml` est la source de vérité — le `.xcodeproj` est généré et non versionné.

### Tests

```bash
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj \
  -scheme HardlyWorking -destination 'platform=macOS' test
```

Les tests couvrent la logique pure (seuil, réglages, machine à états, auto-vérification) sans toucher au système ni bouger la vraie souris. La vérification que le produit remplit sa fonction reste manuelle : laisser le Mac inactif et constater que le statut reste vert.

## Distribution

Le DMG actuel est signé avec un certificat *Apple Development*, valable localement. Pour une distribution publique sans avertissement de sécurité, il faut un certificat *Developer ID* et la notarisation Apple — donc l'Apple Developer Program (99 €/an). Les commandes correspondantes sont déjà en commentaire dans `scripts/build-dmg.sh` : rien d'autre ne change.

Sans cela, un utilisateur qui télécharge le DMG devra passer par Réglages Système → Confidentialité et sécurité → « Ouvrir quand même » (le contournement clic-droit → Ouvrir a été supprimé dans macOS 15).

## Historique

Remplace [`teams-presence`](../teams-presence/), une première version en script bash. Cette v2 native supprime ses trois fragilités : dépendance à Homebrew (`cliclick`), permission Accessibilité cassée à chaque mise à jour, et contournement de la protection TCC du dossier `~/Documents`.
