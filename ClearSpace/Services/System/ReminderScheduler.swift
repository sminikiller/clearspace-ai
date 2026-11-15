import Foundation
import BackgroundTasks
import UserNotifications

/// Promemoria locali che invitano a una nuova pulizia. Non avviano mai eliminazioni automatiche.
@MainActor
final class ReminderScheduler {

    private static let identifier = "clearspace.cleanup-reminder"

    /// Applica la frequenza scelta. Restituisce `false` se l'utente non ha autorizzato le notifiche.
    @discardableResult
    func apply(_ frequency: ReminderFrequency) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard frequency != .off else { return true }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "È il momento di una nuova pulizia"
        content.body = "Dai un'occhiata ai contenuti che occupano più spazio. Nulla viene eliminato senza la tua conferma."
        content.sound = .default

        let trigger: UNNotificationTrigger
        switch frequency {
        case .weekly:
            var components = DateComponents()
            components.weekday = 1
            components.hour = 18
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .monthly:
            var components = DateComponents()
            components.day = 1
            components.hour = 18
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .quarterly:
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 90 * 86_400, repeats: true)
        case .off:
            return true
        }

        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}

/// Prosecuzione delle analisi in background, quando iOS lo consente (dispositivo in carica e inattivo).
/// In background vengono eseguite soltanto analisi: mai eliminazioni.
@MainActor
final class BackgroundAnalysisScheduler {

    private var isRegistered = false

    /// Esegue l'analisi; restituisce `true` se è stata completata.
    var onRun: (@MainActor () async -> Bool)?
    /// Chiamato quando iOS sta per interrompere l'attività.
    var onExpiration: (@MainActor () -> Void)?

    /// Va chiamato all'avvio dell'app, prima che termini il lancio.
    func register() {
        guard !isRegistered else { return }
        let identifier = AppConfiguration.backgroundTaskIdentifier
        // Registrare un identificativo non dichiarato in Info.plist è un errore: lo si verifica prima.
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard permitted.contains(identifier) else { return }

        isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                guard let self else {
                    processingTask.setTaskCompleted(success: false)
                    return
                }
                await self.run(processingTask)
            }
        }
    }

    /// Chiede a iOS di riprendere l'analisi in un momento favorevole.
    func schedule() {
        guard isRegistered else { return }
        let request = BGProcessingTaskRequest(identifier: AppConfiguration.backgroundTaskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private func run(_ task: BGProcessingTask) async {
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.onExpiration?()
            }
        }
        let completed = await onRun?() ?? false
        task.setTaskCompleted(success: completed)
    }
}
