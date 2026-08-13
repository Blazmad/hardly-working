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
    private static let checkInterval: TimeInterval = 20

    /// Temps laissé au système pour enregistrer le mouvement avant de vérifier.
    /// Mesuré sur la machine cible (`spikes/settling-time.swift`) : une relecture
    /// immédiate ne voit le mouvement que 2 fois sur 12 ; à partir de 5 ms, 12/12.
    /// 50 ms laisse une marge confortable tout en restant imperceptible.
    nonisolated static let defaultVerificationDelay: Duration = .milliseconds(50)

    /// Nombre d'échecs consécutifs avant de déclarer l'alerte. Un raté ponctuel
    /// de propagation ne doit jamais faire crier au loup : une alerte qu'on voit
    /// à tort est une alerte qu'on finit par ignorer.
    private static let failuresBeforeAlert = 2

    @Published private(set) var state: PresenceState = .paused

    private let idleMonitor: IdleMonitoring
    private let jiggler: Jiggling
    private let permission: PermissionChecking
    private let settings: Settings
    private let verificationDelay: Duration
    private var timer: Timer?
    private var consecutiveFailures = 0

    init(idleMonitor: IdleMonitoring,
         jiggler: Jiggling,
         permission: PermissionChecking,
         settings: Settings,
         verificationDelay: Duration = PresenceController.defaultVerificationDelay) {
        self.idleMonitor = idleMonitor
        self.jiggler = jiggler
        self.permission = permission
        self.settings = settings
        self.verificationDelay = verificationDelay
    }

    /// À appeler au lancement et à chaque changement de réglage.
    func refresh() {
        // Une panne constatée ne doit PAS être blanchie par un simple changement
        // de réglage : rien n'a prouvé qu'elle était résolue. On ne lève l'alerte
        // que sur une vérification réussie.
        let wasIneffective = (state == .ineffective)
        let priorFailures = consecutiveFailures

        stop()

        guard settings.isEnabled else {
            state = .paused
            return
        }

        // La boucle démarre MÊME sans permission : c'est elle qui détectera que
        // la permission a été accordée. Sans ça, l'utilisateur qui corrige la
        // permission dans les Réglages resterait bloqué jusqu'au redémarrage.
        if !permission.isGranted {
            state = .needsPermission
            consecutiveFailures = 0
        } else if wasIneffective {
            state = .ineffective
            consecutiveFailures = priorFailures
        } else {
            state = .active
            consecutiveFailures = 0
        }

        // Mode .common : sans lui, la minuterie ne se déclenche pas pendant que
        // l'utilisateur garde le menu de la barre de statut ouvert.
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        consecutiveFailures = 0
        // L'état suit l'arrêt : sinon un `stop()` laisserait l'icône afficher
        // « actif » au-dessus d'une boucle morte — exactement le mensonge que
        // tout ce mécanisme existe pour empêcher.
        state = .paused
    }

    /// Un cycle de la boucle. Séparé de la minuterie pour être testable directement.
    func tick() async {
        guard settings.isEnabled else {
            stop()
            return
        }
        guard permission.isGranted else {
            // On ne coupe PAS la minuterie : elle est le seul moyen de repérer
            // que la permission a été rendue.
            consecutiveFailures = 0
            state = .needsPermission
            return
        }

        let idle = idleMonitor.idleSeconds()
        guard JiggleDecision.shouldJiggle(idleSeconds: idle,
                                          thresholdSeconds: settings.idleThresholdSeconds) else {
            consecutiveFailures = 0
            state = .active
            return
        }

        jiggler.jiggle()

        // Le compteur système met quelques millisecondes à refléter l'événement :
        // relire tout de suite donnerait une fausse alerte 8 fois sur 10 (mesuré).
        if verificationDelay > .zero {
            try? await Task.sleep(for: verificationDelay)
        }

        // Auto-vérification : sans elle, une panne serait totalement silencieuse.
        // L'état d'alerte est transitoire — il se lève dès qu'un mouvement réussit.
        if idleMonitor.idleSeconds() >= TimeInterval(settings.idleThresholdSeconds) {
            consecutiveFailures += 1
            state = consecutiveFailures >= Self.failuresBeforeAlert ? .ineffective : .active
        } else {
            consecutiveFailures = 0
            state = .active
        }
    }
}
