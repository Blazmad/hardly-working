# Hardly Working Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer une application macOS native en barre de statut qui maintient la pastille de présence (Teams, Slack…) en vert pendant les absences de Clément, avec un interrupteur, et distribuable sous forme de fichier DMG.

**Architecture:** Une app SwiftUI de type *agent* (aucune icône dans le Dock) dont la scène est un `MenuBarExtra`. Les accès système (lecture de l'inactivité, mouvement de souris, permission Accessibilité) sont isolés derrière des protocoles Swift, ce qui permet de tester toute la logique de décision et la machine à états sans toucher au vrai système ni bouger la vraie souris. Le projet Xcode est généré par XcodeGen depuis un fichier `project.yml` versionné.

**Tech Stack:** Swift / SwiftUI (`MenuBarExtra`), CoreGraphics (`CGEventSource`, `CGEvent`), ServiceManagement (`SMAppService`), ApplicationServices (`AXIsProcessTrusted`), XcodeGen, `xcodebuild`, `hdiutil`, XCTest.

## Global Constraints

- **macOS 14.0 minimum** (`deploymentTarget`), requis par la forme à deux paramètres de `.onChange(of:) { ancienne, nouvelle in }` utilisée en tâche 6 — la forme à un paramètre est marquée obsolète à partir de 14.0.
  > Correction d'audit : une version antérieure de ce plan justifiait ce plancher par `MenuBarExtra` et `SMAppService`. C'est faux — ces deux API sont disponibles dès **macOS 13.0** (vérifié dans `SwiftUI.swiftinterface` et l'en-tête `SMAppService.h`). Le plancher 14.0 reste le bon choix, mais pour cette raison-là. Si un jour on veut descendre à 13.0, c'est le `.onChange` à deux paramètres qu'il faudra remplacer, rien d'autre.
- **Identifiant de paquet** : `com.madzar.hardlyworking`. **Nom produit affiché** : `Hardly Working`. **Nom de cible et de module** : `HardlyWorking` (sans espace).
- **Équipe de signature** : `DEVELOPMENT_TEAM = 272BX4J7SG`, `CODE_SIGN_STYLE = Automatic`. Le certificat *Apple Development* valide (jusqu'au 24/03/2027) appartient à cette équipe.
  > ⚠️ **Ne pas confondre les deux identifiants du certificat.** Son nom affiché est `Apple Development: c.madzar@hotmail.fr (X4857B4L79)`, mais `X4857B4L79` **n'est pas** le Team ID — c'est le champ `OU` du certificat qui l'est, soit `272BX4J7SG`. Une première version de ce plan utilisait la parenthèse et la construction échouait sur `No "Mac Development" signing certificate matching team ID "X4857B4L79"`. Pour retrouver la bonne valeur : `security find-certificate -a -c "Apple Development" -p | openssl x509 -noout -subject` et lire `OU =`.
- **`LSUIElement = YES`** — app agent : aucune icône dans le Dock, aucune fenêtre principale.
- **Toutes les chaînes visibles par l'utilisateur sont en anglais.**
- **Jamais de clic.** `Jiggler` ne produit que des événements `.mouseMoved`, jamais de `mouseDown`/`mouseUp`.
- **Intervalle de vérification : 20 s**, constante interne, jamais exposée dans l'interface. **Seuil d'inactivité** : défaut 240 s, choix offerts 120 / 180 / 240 / 300 / 600 s.
- **Aucune dépendance runtime dans l'app livrée.** XcodeGen et Homebrew sont des outils de construction uniquement — l'app expédiée ne dépend que de macOS.
- **`project.yml` est la source de vérité** ; `HardlyWorking.xcodeproj` est généré et git-ignoré. Ne jamais éditer le `.xcodeproj` à la main.
- **Chemin du projet** : `/Users/clementmadzar/Documents/Madzar/Code/hardly-working`.

---

## File Structure

```
Code/hardly-working/
├── project.yml                        # source de vérité du projet Xcode (XcodeGen)
├── Sources/
│   ├── HardlyWorkingApp.swift         # @main, scène MenuBarExtra, câblage
│   ├── IdleMonitor.swift              # adaptateur : temps d'inactivité système
│   ├── Jiggler.swift                  # adaptateur : mouvement de souris
│   ├── AccessibilityPermission.swift  # adaptateur : permission Accessibilité
│   ├── LoginItem.swift                # adaptateur : lancement au démarrage
│   ├── JiggleDecision.swift           # logique pure : faut-il bouger ?
│   ├── Settings.swift                 # réglages persistés
│   ├── PresenceController.swift       # machine à états + boucle
│   └── MenuView.swift                 # interface du menu
├── Tests/
│   ├── JiggleDecisionTests.swift
│   ├── SettingsTests.swift
│   └── PresenceControllerTests.swift
├── spikes/
│   └── idle-check.swift               # preuve des 2 hypothèses bloquantes
├── scripts/
│   └── build-dmg.sh
└── README.md
```

**Frontière testable :** `JiggleDecision`, `Settings` et `PresenceController` ne touchent jamais au système. Les quatre adaptateurs (`IdleMonitor`, `Jiggler`, `AccessibilityPermission`, `LoginItem`) sont chacun derrière un protocole et injectés, donc remplaçables par des doublures dans les tests.

---

### Task 1: Spike — lever les deux risques bloquants

Tout le produit repose sur deux hypothèses non vérifiées. Cette tâche les prouve **avant** d'écrire la moindre ligne d'application, avec un script Swift autonome (aucun projet Xcode nécessaire).

**Files:**
- Create: `spikes/idle-check.swift`

**Interfaces:**
- Produces: la preuve chiffrée que (1) `CGEventSource` renvoie le même compteur d'inactivité que `ioreg`, et (2) un événement souris synthétique le fait retomber.

- [ ] **Step 1: Écrire le script de spike**

Créer `spikes/idle-check.swift` :

```swift
#!/usr/bin/env swift
import CoreGraphics
import Foundation

/// Le compteur candidat pour l'app : ~0 correspond à kCGAnyInputEventType
/// (n'importe quel événement clavier ou souris).
func cgIdleSeconds() -> TimeInterval {
    let anyInput = CGEventType(rawValue: ~0)!
    return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
}

/// La référence connue : le compteur que lit déjà la version bash en production.
func ioregIdleSeconds() -> TimeInterval {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    process.arguments = ["-c", "IOHIDSystem"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard let line = output.split(separator: "\n").first(where: { $0.contains("HIDIdleTime") }),
          let raw = line.split(separator: "=").last,
          let nanoseconds = Double(raw.trimmingCharacters(in: .whitespaces))
    else { return -1 }
    return nanoseconds / 1_000_000_000
}

/// Déplace le curseur d'un pixel puis le ramène. Aucun clic.
func jiggleOnce() {
    let origin = CGEvent(source: nil)?.location ?? .zero
    for point in [CGPoint(x: origin.x + 1, y: origin.y), origin] {
        CGEvent(mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}

print("=== Hypothesis 1: does CGEventSource read the same counter as ioreg? ===")
print("Do not touch the mouse or keyboard for the next 12 seconds.")
for step in 1...4 {
    Thread.sleep(forTimeInterval: 3)
    print(String(format: "t=%2ds   CGEventSource=%6.1fs   ioreg=%6.1fs",
                 step * 3, cgIdleSeconds(), ioregIdleSeconds()))
}

print("")
print("=== Hypothesis 2: does a synthetic mouse event reset the counter? ===")
let before = cgIdleSeconds()
jiggleOnce()
Thread.sleep(forTimeInterval: 0.5)
let after = cgIdleSeconds()
print(String(format: "before=%.1fs   after=%.1fs", before, after))
print(after < before ? "PASS: the counter dropped." : "FAIL: the counter did not move.")
```

- [ ] **Step 2: Lancer le spike sans toucher souris ni clavier**

Run: `cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working && swift spikes/idle-check.swift`

**Important :** ne rien toucher pendant l'exécution (~15 s). Une frappe ou un mouvement de souris pendant le test remettrait les compteurs à zéro et invaliderait la mesure. Si les valeurs affichées restent proches de 0 tout du long, c'est que quelqu'un a touché la machine — relancer.

Expected:
- Hypothèse 1 : les deux colonnes progressent ensemble et concordent à ~1 s près (elles lisent le même compteur, échantillonné à un instant légèrement différent).
- Hypothèse 2 : `after` nettement inférieur à `before`, et le message `PASS`.

- [ ] **Step 3: Interpréter le résultat**

- Si les deux hypothèses passent → continuer, rien à changer dans le plan.
- Si l'hypothèse 1 échoue (écart important entre les colonnes) → essayer `.combinedSessionState` au lieu de `.hidSystemState`, relancer, et **noter dans le rapport quelle source est la bonne** : toutes les tâches suivantes doivent utiliser celle qui concorde avec `ioreg`.
- Si l'hypothèse 2 échoue → **STOP, remonter en BLOCKED.** Le mécanisme central du produit ne fonctionne pas comme prévu ; il faut reprendre la conception avant d'aller plus loin. Vérifier au passage si l'app qui exécute le shell dispose bien de la permission Accessibilité (Réglages Système → Confidentialité et sécurité → Accessibilité).

- [ ] **Step 4: Commit**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add spikes/idle-check.swift
git commit -m "spike: prouve que CGEventSource lit le compteur d'inactivité et qu'un CGEvent le réinitialise"
```

---

### Task 2: Squelette du projet — une app qui se construit et s'affiche

**Files:**
- Create: `project.yml`
- Create: `Sources/HardlyWorkingApp.swift`
- Modify: `.gitignore`

**Interfaces:**
- Produces: un projet Xcode généré par XcodeGen, une app `Hardly Working.app` qui se construit en Release et affiche une icône dans la barre de statut avec un menu « Quit » fonctionnel.

- [ ] **Step 1: Créer `project.yml`**

```yaml
name: HardlyWorking
options:
  bundleIdPrefix: com.madzar
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

settings:
  base:
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: 272BX4J7SG
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "5.0"

targets:
  HardlyWorking:
    type: application
    platform: macOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.madzar.hardlyworking
        PRODUCT_NAME: Hardly Working
        PRODUCT_MODULE_NAME: HardlyWorking
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSUIElement: YES
        INFOPLIST_KEY_NSHumanReadableCopyright: ""

  HardlyWorkingTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: HardlyWorking
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES

schemes:
  HardlyWorking:
    build:
      targets:
        HardlyWorking: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - HardlyWorkingTests
```

- [ ] **Step 2: Ignorer le projet généré**

Ajouter ces lignes à `.gitignore` (le fichier existe déjà et contient `.superpowers/`, `.DS_Store`, `build/`, `DerivedData/`, `*.dmg`) :

```
*.xcodeproj
```

- [ ] **Step 3: Écrire l'app minimale**

Créer `Sources/HardlyWorkingApp.swift` :

```swift
import SwiftUI

@main
struct HardlyWorkingApp: App {
    var body: some Scene {
        MenuBarExtra("Hardly Working", systemImage: "cup.and.saucer.fill") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
```

- [ ] **Step 4: Créer un dossier `Tests` vide mais valide**

XcodeGen échoue si le dossier source d'une cible n'existe pas. Créer un test bidon qui sera remplacé en tâche 4 :

Créer `Tests/JiggleDecisionTests.swift` :

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testProjectBuildsAndTestsRun() {
        XCTAssertTrue(true, "Remplacé par de vrais tests en tâche 4.")
    }
}
```

- [ ] **Step 5: Générer le projet et construire**

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
xcodegen generate
xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -configuration Release -derivedDataPath build build
```

Expected: `** BUILD SUCCEEDED **`, et `build/Build/Products/Release/Hardly Working.app` existe.

**Confirmé nécessaire sur cette machine** (le `TEST_HOST` par défaut ne gère pas l'espace dans `Hardly Working`, d'où l'erreur « Could not find test host »). Ajouter sous `HardlyWorkingTests.settings.base` :
```yaml
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Hardly Working.app/Contents/MacOS/Hardly Working"
        BUNDLE_LOADER: "$(TEST_HOST)"
```
puis régénérer et reconstruire.

- [ ] **Step 6: Vérifier que les tests se lancent**

Run:
```bash
xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -destination 'platform=macOS' -derivedDataPath build test
```

Expected: `** TEST SUCCEEDED **` avec le test bidon qui passe.

- [ ] **Step 7: Vérifier manuellement que l'app s'affiche**

Run: `open "build/Build/Products/Release/Hardly Working.app"`

Expected: une icône de tasse apparaît dans la barre de menus en haut à droite, **aucune icône n'apparaît dans le Dock** (c'est ce que prouve `LSUIElement`), et cliquer dessus affiche un menu contenant « Quit ». Cliquer « Quit » pour la fermer.

- [ ] **Step 8: Commit**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add project.yml .gitignore Sources Tests
git commit -m "feat: squelette du projet — app agent avec icône de barre de statut"
```

---

### Task 3: Adaptateurs système

Les quatre points de contact avec macOS, chacun derrière un protocole pour rester remplaçable en test.

**Files:**
- Create: `Sources/IdleMonitor.swift`
- Create: `Sources/Jiggler.swift`
- Create: `Sources/AccessibilityPermission.swift`
- Create: `Sources/LoginItem.swift`

**Interfaces:**
- Produces:
  - `protocol IdleMonitoring { func idleSeconds() -> TimeInterval }`, implémenté par `SystemIdleMonitor`
  - `protocol Jiggling { func jiggle() }`, implémenté par `MouseJiggler`
  - `protocol PermissionChecking { var isGranted: Bool { get }; func requestAccess(); func openSettings() }`, implémenté par `AccessibilityPermission`
  - `protocol LoginItemManaging { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) }`, implémenté par `LoginItem`

- [ ] **Step 1: Écrire `IdleMonitor.swift`**

```swift
import CoreGraphics
import Foundation

/// Fournit le temps écoulé depuis la dernière activité clavier ou souris.
protocol IdleMonitoring {
    func idleSeconds() -> TimeInterval
}

/// Lit le compteur d'inactivité réel de macOS — le même que celui consulté
/// par Teams, Slack et Discord pour décider d'afficher « away ».
struct SystemIdleMonitor: IdleMonitoring {
    func idleSeconds() -> TimeInterval {
        // ~0 correspond à kCGAnyInputEventType : n'importe quel événement d'entrée.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }
}
```

> Si la tâche 1 a conclu que `.combinedSessionState` est la bonne source, remplacer `.hidSystemState` ici.

- [ ] **Step 2: Écrire `Jiggler.swift`**

```swift
import CoreGraphics

/// Provoque une activité souris minimale, suffisante pour réinitialiser
/// le compteur d'inactivité du système.
protocol Jiggling {
    func jiggle()
}

/// Déplace le curseur d'un pixel puis le ramène à sa position exacte.
/// Imperceptible à l'œil, et n'émet jamais de clic.
struct MouseJiggler: Jiggling {
    func jiggle() {
        let origin = CGEvent(source: nil)?.location ?? .zero
        move(to: CGPoint(x: origin.x + 1, y: origin.y))
        move(to: origin)
    }

    private func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 3: Écrire `AccessibilityPermission.swift`**

```swift
import ApplicationServices
import AppKit

/// État de la permission Accessibilité, sans laquelle aucun événement
/// souris synthétique ne peut être émis.
protocol PermissionChecking {
    var isGranted: Bool { get }
    /// Déclenche la demande système (une popup, une seule fois par app).
    func requestAccess()
    /// Ouvre directement le bon panneau des Réglages Système.
    func openSettings()
}

struct AccessibilityPermission: PermissionChecking {
    var isGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Écrire `LoginItem.swift`**

```swift
import Foundation
import ServiceManagement

/// Contrôle l'inscription de l'app au démarrage de session.
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

/// S'appuie sur SMAppService : l'app apparaît dans
/// Réglages Système → Général → Ouverture, où l'utilisateur garde le contrôle.
struct LoginItem: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Hardly Working: login item update failed — \(error.localizedDescription)")
        }
    }
}
```

> `SMAppService` exige une app correctement signée. Depuis un dossier de construction, `register()` peut échouer — c'est normal et sans gravité. La vérification réelle se fait en tâche 7, une fois l'app installée dans `/Applications`.

- [ ] **Step 5: Vérifier que tout compile**

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -configuration Release -derivedDataPath build build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add Sources
git commit -m "feat: adaptateurs système (inactivité, mouvement souris, permission, démarrage auto)"
```

---

### Task 4: Logique pure et réglages — en TDD

**Files:**
- Create: `Sources/JiggleDecision.swift`
- Create: `Sources/Settings.swift`
- Modify (remplacer intégralement): `Tests/JiggleDecisionTests.swift`
- Create: `Tests/SettingsTests.swift`

**Interfaces:**
- Consumes: rien (aucune dépendance système).
- Produces:
  - `JiggleDecision.shouldJiggle(idleSeconds:thresholdSeconds:) -> Bool`
  - `Settings` (classe `ObservableObject`) avec `isEnabled: Bool`, `idleThresholdSeconds: Int`, et `Settings.availableThresholds: [Int]`

- [ ] **Step 1: Écrire les tests qui échouent**

Remplacer tout le contenu de `Tests/JiggleDecisionTests.swift` :

```swift
import XCTest
@testable import HardlyWorking

final class JiggleDecisionTests: XCTestCase {
    func testDoesNotJiggleBelowThreshold() {
        XCTAssertFalse(JiggleDecision.shouldJiggle(idleSeconds: 239, thresholdSeconds: 240))
    }

    func testJigglesExactlyAtThreshold() {
        XCTAssertTrue(JiggleDecision.shouldJiggle(idleSeconds: 240, thresholdSeconds: 240))
    }

    func testJigglesAboveThreshold() {
        XCTAssertTrue(JiggleDecision.shouldJiggle(idleSeconds: 500, thresholdSeconds: 240))
    }

    func testDoesNotJiggleWhenFreshlyActive() {
        XCTAssertFalse(JiggleDecision.shouldJiggle(idleSeconds: 0, thresholdSeconds: 240))
    }
}
```

Créer `Tests/SettingsTests.swift` :

```swift
import XCTest
@testable import HardlyWorking

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.madzar.hardlyworking.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreEnabledAtFourMinutes() {
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.idleThresholdSeconds, 240)
    }

    func testChangesArePersisted() {
        let settings = Settings(defaults: defaults)
        settings.isEnabled = false
        settings.idleThresholdSeconds = 600

        let reloaded = Settings(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertEqual(reloaded.idleThresholdSeconds, 600)
    }

    func testOfferedThresholdsIncludeTheDefault() {
        XCTAssertTrue(Settings.availableThresholds.contains(240))
        XCTAssertEqual(Settings.availableThresholds, [120, 180, 240, 300, 600])
    }
}
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -destination 'platform=macOS' -derivedDataPath build test
```

Expected: échec de compilation des tests — `cannot find 'JiggleDecision' in scope` et `cannot find 'Settings' in scope`. C'est l'échec attendu (RED).

- [ ] **Step 3: Écrire `JiggleDecision.swift`**

```swift
import Foundation

/// La seule règle métier du produit, isolée pour être testable sans le système.
enum JiggleDecision {
    /// Faut-il provoquer un mouvement de souris maintenant ?
    static func shouldJiggle(idleSeconds: TimeInterval, thresholdSeconds: Int) -> Bool {
        idleSeconds >= TimeInterval(thresholdSeconds)
    }
}
```

- [ ] **Step 4: Écrire `Settings.swift`**

```swift
import Foundation

/// Réglages persistés entre les lancements.
final class Settings: ObservableObject {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let idleThreshold = "idleThresholdSeconds"
    }

    /// Seuils proposés dans le menu, en secondes : 2, 3, 4, 5 et 10 minutes.
    static let availableThresholds: [Int] = [120, 180, 240, 300, 600]

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    @Published var idleThresholdSeconds: Int {
        didSet { defaults.set(idleThresholdSeconds, forKey: Key.idleThreshold) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.idleThreshold: 240,
        ])
        self.isEnabled = defaults.bool(forKey: Key.isEnabled)
        self.idleThresholdSeconds = defaults.integer(forKey: Key.idleThreshold)
    }
}
```

- [ ] **Step 5: Lancer les tests et vérifier qu'ils passent**

Run:
```bash
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -destination 'platform=macOS' -derivedDataPath build test
```

Expected: `** TEST SUCCEEDED **`, 7 tests passants (4 de décision + 3 de réglages), sans avertissement.

- [ ] **Step 6: Commit**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add Sources/JiggleDecision.swift Sources/Settings.swift Tests
git commit -m "feat: logique de décision et réglages persistés, couverts par des tests"
```

---

### Task 5: PresenceController — machine à états et auto-vérification, en TDD

Le cœur du produit, et l'endroit où se joue la correction majeure par rapport à la v1 : **une panne doit être visible, jamais silencieuse.**

**Files:**
- Create: `Sources/PresenceController.swift`
- Create: `Tests/PresenceControllerTests.swift`

**Interfaces:**
- Consumes: `IdleMonitoring`, `Jiggling`, `PermissionChecking` (tâche 3), `Settings`, `JiggleDecision` (tâche 4).
- Produces:
  - `enum PresenceState { case paused, active, needsPermission, ineffective }`
  - `PresenceController` (classe `@MainActor ObservableObject`) avec `state: PresenceState` en lecture seule, et exactement trois méthodes publiques : `refresh()` (à appeler au lancement et après tout changement de réglage), `stop()` et `tick()`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/PresenceControllerTests.swift` :

```swift
import XCTest
@testable import HardlyWorking

/// Renvoie une suite de valeurs scriptées, pour simuler le compteur
/// d'inactivité avant et après un mouvement de souris.
private final class FakeIdleMonitor: IdleMonitoring {
    private let values: [TimeInterval]
    private(set) var callCount = 0

    init(_ values: [TimeInterval]) { self.values = values }

    func idleSeconds() -> TimeInterval {
        defer { callCount += 1 }
        guard !values.isEmpty else { return 0 }
        return callCount < values.count ? values[callCount] : values[values.count - 1]
    }
}

private final class SpyJiggler: Jiggling {
    private(set) var jiggleCount = 0
    func jiggle() { jiggleCount += 1 }
}

private struct StubPermission: PermissionChecking {
    var isGranted: Bool
    func requestAccess() {}
    func openSettings() {}
}

@MainActor
final class PresenceControllerTests: XCTestCase {
    private func makeSettings(enabled: Bool = true, threshold: Int = 240) -> Settings {
        let suite = "com.madzar.hardlyworking.tests.\(UUID().uuidString)"
        let settings = Settings(defaults: UserDefaults(suiteName: suite)!)
        settings.isEnabled = enabled
        settings.idleThresholdSeconds = threshold
        return settings
    }

    private func makeController(
        idle: [TimeInterval],
        jiggler: SpyJiggler = SpyJiggler(),
        permissionGranted: Bool = true,
        settings: Settings
    ) -> PresenceController {
        PresenceController(
            idleMonitor: FakeIdleMonitor(idle),
            jiggler: jiggler,
            permission: StubPermission(isGranted: permissionGranted),
            settings: settings
        )
    }

    func testDoesNotJiggleBelowThreshold() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [100], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .active)
    }

    func testJigglesAboveThresholdAndStaysActiveWhenCounterDrops() {
        let jiggler = SpyJiggler()
        // 1re lecture : inactif depuis 300s → on bouge. 2e lecture (vérification) : 0s → succès.
        let controller = makeController(idle: [300, 0], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .active)
    }

    func testReportsIneffectiveWhenCounterDoesNotDrop() {
        let jiggler = SpyJiggler()
        // Le mouvement est émis mais le compteur ne bouge pas : panne silencieuse détectée.
        let controller = makeController(idle: [300, 300], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .ineffective)
    }

    func testIneffectiveStateClearsOnNextSuccess() {
        let jiggler = SpyJiggler()
        // tick 1 : 300 puis 300 → ineffective. tick 2 : 300 puis 0 → retour à active.
        let controller = makeController(idle: [300, 300, 300, 0], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(controller.state, .ineffective)
        controller.tick()
        XCTAssertEqual(controller.state, .active, "Une alerte ne doit jamais rester collée après un succès.")
    }

    func testPausedWhenDisabled() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [300, 0], jiggler: jiggler, settings: makeSettings(enabled: false))
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .paused)
    }

    func testNeedsPermissionWhenNotGranted() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [300, 0], jiggler: jiggler,
                                        permissionGranted: false, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0, "Sans permission, aucun mouvement ne doit être tenté.")
        XCTAssertEqual(controller.state, .needsPermission)
    }

    func testRespectsCustomThreshold() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [150, 0], jiggler: jiggler,
                                        settings: makeSettings(threshold: 120))
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1, "150s dépasse un seuil réglé à 120s.")
    }
}
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -destination 'platform=macOS' -derivedDataPath build test
```

Expected: échec de compilation — `cannot find 'PresenceController' in scope`.

- [ ] **Step 3: Écrire `PresenceController.swift`**

```swift
import Foundation

/// Ce que l'app est en train de faire, et ce que l'icône doit refléter.
enum PresenceState: Equatable {
    /// L'utilisateur a coupé l'app.
    case paused
    /// Tout va bien : la surveillance tourne.
    case active
    /// La permission Accessibilité manque — rien ne peut fonctionner.
    case needsPermission
    /// Le mouvement a été émis mais n'a eu aucun effet sur le compteur.
    case ineffective
}

/// Chef d'orchestre : décide quand bouger la souris, et vérifie que ça a servi.
@MainActor
final class PresenceController: ObservableObject {
    /// Fréquence de sondage. Volontairement non exposée dans l'interface.
    static let checkInterval: TimeInterval = 20

    @Published private(set) var state: PresenceState = .paused

    private let idleMonitor: IdleMonitoring
    private let jiggler: Jiggling
    private let permission: PermissionChecking
    private let settings: Settings
    private var timer: Timer?

    init(idleMonitor: IdleMonitoring,
         jiggler: Jiggling,
         permission: PermissionChecking,
         settings: Settings) {
        self.idleMonitor = idleMonitor
        self.jiggler = jiggler
        self.permission = permission
        self.settings = settings
    }

    /// À appeler au lancement et à chaque changement de réglage.
    func refresh() {
        stop()

        guard settings.isEnabled else {
            state = .paused
            return
        }
        guard permission.isGranted else {
            state = .needsPermission
            return
        }

        state = .active
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Un cycle de la boucle. Séparé de la minuterie pour être testable directement.
    func tick() {
        guard settings.isEnabled else {
            stop()
            state = .paused
            return
        }
        guard permission.isGranted else {
            stop()
            state = .needsPermission
            return
        }

        let idle = idleMonitor.idleSeconds()
        guard JiggleDecision.shouldJiggle(idleSeconds: idle,
                                          thresholdSeconds: settings.idleThresholdSeconds) else {
            state = .active
            return
        }

        jiggler.jiggle()

        // Auto-vérification : sans elle, une panne serait totalement silencieuse.
        // L'état d'alerte est transitoire — il se lève dès qu'un mouvement réussit.
        let afterJiggle = idleMonitor.idleSeconds()
        state = afterJiggle >= TimeInterval(settings.idleThresholdSeconds) ? .ineffective : .active
    }
}
```

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

Run:
```bash
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -destination 'platform=macOS' -derivedDataPath build test
```

Expected: `** TEST SUCCEEDED **`, 14 tests passants (4 + 3 + 7), sans avertissement.

- [ ] **Step 5: Commit**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add Sources/PresenceController.swift Tests/PresenceControllerTests.swift
git commit -m "feat: machine à états avec auto-vérification du mouvement (panne visible, jamais silencieuse)"
```

---

### Task 6: Interface — le menu de la barre de statut

**Files:**
- Create: `Sources/MenuView.swift`
- Modify (remplacer intégralement): `Sources/HardlyWorkingApp.swift`

**Interfaces:**
- Consumes: `PresenceController`, `PresenceState`, `Settings`, `PermissionChecking`, `LoginItemManaging`, ainsi que les implémentations concrètes `SystemIdleMonitor`, `MouseJiggler`, `AccessibilityPermission`, `LoginItem`.
- Produces: l'app complète et fonctionnelle, avec une icône dont l'apparence reflète les quatre états.

- [ ] **Step 1: Écrire `MenuView.swift`**

```swift
import SwiftUI

/// Le contenu du menu déroulant de la barre de statut.
struct MenuView: View {
    @ObservedObject var controller: PresenceController
    @ObservedObject var settings: Settings

    let permission: PermissionChecking
    let loginItem: LoginItemManaging

    @State private var launchAtLogin: Bool = false

    var body: some View {
        // Bandeau d'alerte : affiché seulement quand quelque chose ne va pas.
        if controller.state == .needsPermission {
            Text("Accessibility permission required")
            Button("Open Accessibility Settings…") {
                permission.requestAccess()
                permission.openSettings()
            }
            Divider()
        } else if controller.state == .ineffective {
            Text("Mouse nudge had no effect — check Accessibility permission")
            Button("Open Accessibility Settings…") {
                permission.openSettings()
            }
            Divider()
        }

        Toggle("Active", isOn: $settings.isEnabled)

        Divider()

        Picker("Idle threshold", selection: $settings.idleThresholdSeconds) {
            ForEach(Settings.availableThresholds, id: \.self) { seconds in
                Text("\(seconds / 60) min").tag(seconds)
            }
        }

        Toggle("Launch at login", isOn: $launchAtLogin)

        Divider()

        Button("Quit Hardly Working") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        // Ces modificateurs portent sur le dernier élément du menu, mais leur effet
        // est global à la vue : ils synchronisent l'interface avec le contrôleur.
        .onAppear {
            launchAtLogin = loginItem.isEnabled
            controller.refresh()
        }
        .onChange(of: settings.isEnabled) { _, _ in
            controller.refresh()
        }
        .onChange(of: settings.idleThresholdSeconds) { _, _ in
            controller.refresh()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            loginItem.setEnabled(newValue)
            // Relire l'état réel : si l'inscription a échoué, la case doit se décocher
            // au lieu de mentir à l'utilisateur.
            launchAtLogin = loginItem.isEnabled
        }
    }
}
```

> Note SwiftUI : dans un `MenuBarExtra` de style menu, le corps de la vue est une liste d'éléments de menu — pas besoin de conteneur `VStack`.

- [ ] **Step 2: Remplacer `HardlyWorkingApp.swift`**

Remplacer intégralement le contenu par :

```swift
import SwiftUI

@main
struct HardlyWorkingApp: App {
    @StateObject private var settings: Settings
    @StateObject private var controller: PresenceController

    // Adaptateurs sans état interne : les instancier ici est sans conséquence.
    private let permission = AccessibilityPermission()
    private let loginItem = LoginItem()

    init() {
        // Une seule instance de Settings, partagée entre le contrôleur et le menu.
        // Deux instances distinctes casseraient la réactivité de l'interface.
        let sharedSettings = Settings()
        _settings = StateObject(wrappedValue: sharedSettings)
        _controller = StateObject(wrappedValue: PresenceController(
            idleMonitor: SystemIdleMonitor(),
            jiggler: MouseJiggler(),
            permission: AccessibilityPermission(),
            settings: sharedSettings
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller,
                     settings: settings,
                     permission: permission,
                     loginItem: loginItem)
        } label: {
            Image(systemName: iconName)
        }
    }

    /// L'icône reflète l'état : actif, en pause, ou problème à régler.
    private var iconName: String {
        switch controller.state {
        case .active:          return "cup.and.saucer.fill"
        case .paused:          return "cup.and.saucer"
        case .needsPermission,
             .ineffective:     return "exclamationmark.triangle.fill"
        }
    }
}
```

- [ ] **Step 3: Construire et vérifier que les tests passent toujours**

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -destination 'platform=macOS' -derivedDataPath build test
```

Expected: `** TEST SUCCEEDED **`, les 14 tests passent toujours.

- [ ] **Step 4: Vérifier manuellement l'interface**

Run: `open "build/Build/Products/Release/Hardly Working.app"`

> Construire d'abord en Release si nécessaire : `xcodebuild -project HardlyWorking.xcodeproj -scheme HardlyWorking -configuration Release -derivedDataPath build build`

Expected, en cliquant sur l'icône de la barre de statut :
- le menu affiche « Active » (coché), « Idle threshold » avec un sous-menu 2/3/4/5/10 min, « Launch at login », et « Quit Hardly Working » ;
- décocher « Active » fait passer l'icône à sa variante creuse ;
- changer le seuil ne provoque pas de plantage ;
- si la permission Accessibilité n'est pas accordée à l'app, le bandeau d'alerte apparaît en haut du menu et l'icône est un triangle d'avertissement.

Quitter l'app à la fin de la vérification.

- [ ] **Step 5: Commit**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add Sources
git commit -m "feat: menu de la barre de statut, icône réactive à l'état, câblage complet"
```

---

### Task 7: Empaquetage DMG et vérification réelle de bout en bout

**Files:**
- Create: `scripts/build-dmg.sh`

**Interfaces:**
- Consumes: l'app complète (tâches 2 à 6).
- Produces: `dist/Hardly Working.dmg`, prêt à être installé ou envoyé.

- [ ] **Step 1: Écrire `scripts/build-dmg.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hardly Working"
SCHEME="HardlyWorking"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

cd "$PROJECT_DIR"

echo "==> Génération du projet Xcode"
xcodegen generate

echo "==> Construction en Release"
xcodebuild -project HardlyWorking.xcodeproj \
           -scheme "$SCHEME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           build

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { echo "App introuvable : $APP_PATH" >&2; exit 1; }

echo "==> Vérification de la signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Étape future, quand le certificat Developer ID sera disponible :
#   codesign --force --deep --options runtime \
#            --sign "Developer ID Application: ..." "$APP_PATH"
#   xcrun notarytool submit "$DMG_PATH" --keychain-profile "..." --wait
#   xcrun stapler staple "$DMG_PATH"
# Rien d'autre ne change dans ce script.

echo "==> Préparation du contenu du DMG"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Création du DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo ""
echo "DMG prêt : $DMG_PATH"
ls -lh "$DMG_PATH"
```

- [ ] **Step 2: Rendre le script exécutable et ignorer la sortie**

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
chmod +x scripts/build-dmg.sh
printf "dist/\n" >> .gitignore
```

- [ ] **Step 3: Construire le DMG**

Run: `bash scripts/build-dmg.sh`

Expected: le script se termine sur `DMG prêt : …/dist/Hardly Working.dmg` et le fichier existe, de taille raisonnable (quelques centaines de Ko à quelques Mo).

- [ ] **Step 4: Installer l'app depuis le DMG**

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
hdiutil attach "dist/Hardly Working.dmg"
cp -R "/Volumes/Hardly Working/Hardly Working.app" /Applications/
hdiutil detach "/Volumes/Hardly Working"
ls -d "/Applications/Hardly Working.app"
```

Expected: l'app est présente dans `/Applications`.

- [ ] **Step 5: Lancer et accorder la permission Accessibilité**

Run: `open "/Applications/Hardly Working.app"`

Au premier lancement, l'app détecte l'absence de permission et affiche le bandeau d'alerte. Cliquer « Open Accessibility Settings… », puis **demander à Clément d'activer « Hardly Working » dans la liste** (une case à cocher — action humaine obligatoire, impossible à automatiser).

**Point à confirmer ici** (seul moyen de trancher) : l'URL `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` a été auditée comme ouvrant bien le panneau *Confidentialité et sécurité*, mais l'ancrage précis sur la ligne **Accessibilité** n'a pas pu être garanti hors exécution réelle. Noter dans le rapport ce que le clic ouvre effectivement : le bon volet directement, ou seulement la page Confidentialité et sécurité à faire défiler. Si l'ancrage échoue, ce n'est pas bloquant (la permission reste accordable) — le signaler comme finding mineur, sans corriger dans cette tâche.

Expected après activation : l'icône repasse à la tasse pleine et le bandeau d'alerte disparaît du menu.

- [ ] **Step 6: Vérifier le lancement au démarrage**

Dans le menu, cocher « Launch at login ». La case doit **rester cochée** : si elle se décoche seule, c'est que `register()` a échoué (le code relit délibérément l'état réel plutôt que de mentir).

Puis ouvrir le panneau système pour confirmer :

Run: `open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"`

Expected: « Hardly Working » apparaît dans la liste de Réglages Système → Général → Ouverture. En cas d'échec, chercher le message `Hardly Working: login item update failed` :

Run: `log show --last 5m --predicate 'eventMessage CONTAINS "Hardly Working"' --info 2>/dev/null | tail -20`

- [ ] **Step 7: Vérification réelle de bout en bout — le seul test qui prouve le produit**

Pour ne pas attendre 4 minutes, régler temporairement le seuil sur **2 min** dans le menu, puis **ne plus toucher souris ni clavier pendant 5 minutes**, Teams ouvert et visible.

Expected:
- la pastille Teams **reste verte** pendant toute la durée ;
- pendant l'observation, mesurer le compteur pour objectiver (dans un terminal, sans toucher la souris) :

```bash
for i in $(seq 1 12); do
  printf "%s  idle=%s\n" "$(date +%H:%M:%S)" \
    "$(ioreg -c IOHIDSystem | awk -F' = ' '/HIDIdleTime/ {print int($2/1000000000); exit}')"
  sleep 15
done
```

Le compteur doit **monter puis retomber brutalement** à intervalles réguliers — c'est la preuve directe que l'app agit. Un compteur qui monte sans jamais retomber signifie que l'app ne fonctionne pas : remonter en BLOCKED avec la trace.

Remettre ensuite le seuil sur 4 min.

- [ ] **Step 8: Vérifier l'absence d'interférence en usage normal**

Utiliser la machine normalement (souris, clavier) pendant 2-3 minutes.

Expected: aucun saut de curseur perceptible, aucun clic parasite, rien ne se sélectionne ou ne s'ouvre tout seul.

- [ ] **Step 9: Commit**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add scripts/build-dmg.sh .gitignore
git commit -m "feat: script de construction du DMG et vérification de bout en bout"
```

---

### Task 8: Documentation et retrait de la version bash

**Files:**
- Create: `Code/hardly-working/README.md`
- Modify: `Code/teams-presence/README.md` (ajout d'un renvoi en tête)

**Interfaces:**
- Consumes: noms exacts des scripts, réglages et chemins des tâches 1 à 7.

- [ ] **Step 1: Écrire le README**

Créer `Code/hardly-working/README.md` :

````markdown
# Hardly Working

Une petite app macOS en barre de statut qui empêche Teams (ou Slack, Discord…) de vous afficher « away » quand vous vous éloignez de votre Mac.

*Working hard, or hardly working?*

## Comment ça marche

Teams s'appuie sur le compteur d'inactivité de macOS : le temps écoulé depuis votre dernière action clavier ou souris. Hardly Working consulte ce compteur toutes les 20 secondes et, dès qu'il dépasse le seuil choisi, déplace le curseur d'un pixel puis le remet exactement où il était — imperceptible, sans jamais cliquer, et sans aucune gêne si vous êtes en train d'utiliser la souris.

Après chaque mouvement, l'app **vérifie que le compteur est bien retombé**. Si ce n'est pas le cas, l'icône passe en alerte et le menu explique pourquoi — l'app ne prétend jamais fonctionner quand ce n'est pas le cas.

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
````

- [ ] **Step 2: Désinstaller le service bash**

Les deux ne doivent jamais tourner en même temps.

Run:
```bash
cd /Users/clementmadzar/Documents/Madzar/Code/teams-presence
bash uninstall.sh
launchctl list | grep teams-presence || echo "Service bash bien arrêté."
```

Expected: `teams-presence désinstallé.` puis `Service bash bien arrêté.`

- [ ] **Step 3: Ajouter le renvoi dans le README de la v1**

Insérer ces lignes juste après le titre `# teams-presence` de `Code/teams-presence/README.md` :

```markdown

> **⚠️ Remplacé par [Hardly Working](../hardly-working/).**
> Ce script bash fonctionne toujours mais n'est plus utilisé : la version native
> supprime la dépendance à Homebrew, la permission Accessibilité qui cassait à
> chaque `brew upgrade`, et le contournement de la protection TCC de `~/Documents`.
> Ce dépôt est conservé pour son historique — notamment l'enquête sur TCC.
```

- [ ] **Step 4: Commit dans les deux dépôts**

```bash
cd /Users/clementmadzar/Documents/Madzar/Code/hardly-working
git add README.md
git commit -m "docs: README d'installation, d'utilisation et de construction"

cd /Users/clementmadzar/Documents/Madzar/Code/teams-presence
git add README.md
git commit -m "docs: renvoie vers Hardly Working, qui remplace ce script"
```

---

## Post-plan verification

- [ ] L'app tourne depuis `/Applications`, l'icône est en état actif, et Teams reste vert après 5 minutes sans toucher la machine.
- [ ] Décocher « Active » : après quelques minutes, Teams repasse bien en orange (preuve que l'interrupteur coupe réellement).
- [ ] Retirer la permission Accessibilité dans les Réglages Système : l'app doit basculer en icône d'alerte au cycle suivant (≤ 20 s) au lieu de faire semblant de fonctionner. Puis la remettre.
- [ ] Aucun processus `teams-presence` ne tourne encore (`launchctl list | grep teams-presence` ne renvoie rien).
