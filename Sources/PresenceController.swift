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
