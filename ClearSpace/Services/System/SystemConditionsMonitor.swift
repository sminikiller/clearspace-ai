import Foundation
import Network
import Observation
import UIKit

/// Lettura dello spazio del dispositivo. iOS espone lo spazio del telefono, non quello del piano iCloud.
enum DeviceStorage {

    static func snapshot(now: Date = Date()) -> StorageSnapshot? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return StorageSnapshot(date: now, totalBytes: Int64(total), availableBytes: available)
    }
}

/// Motivo per cui le analisi costose vengono sospese.
enum PauseReason: Equatable, Sendable {
    case user
    case thermal
    case lowBattery
    case lowPowerMode

    var message: String {
        switch self {
        case .user: return "Analisi in pausa."
        case .thermal: return "In pausa: il dispositivo è caldo. L'analisi riprenderà da sola."
        case .lowBattery: return "In pausa: batteria scarica. Collega l'alimentazione per continuare."
        case .lowPowerMode: return "In pausa: è attivo il risparmio energetico."
        }
    }
}

/// Osserva rete, batteria e temperatura per rispettare le modalità "solo Wi‑Fi" e "pausa per batteria".
@MainActor
@Observable
final class SystemConditionsMonitor {

    private(set) var isOnline = true
    /// Connessione non a consumo (Wi‑Fi o cavo).
    private(set) var isOnUnmeteredNetwork = false
    private(set) var batteryLevel: Float = 1
    private(set) var isCharging = false
    private(set) var isLowPowerMode = false
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isStarted = false

    private let pathMonitor = NWPathMonitor()

    func start() {
        guard !isStarted else { return }
        isStarted = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let unmetered = online && !path.isExpensive && !path.isConstrained
            Task { @MainActor in
                self?.isOnline = online
                self?.isOnUnmeteredNetwork = unmetered
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "clearspace.network-monitor"))

        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
            ProcessInfo.thermalStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshDeviceState()
                }
            }
            observers.append(token)
        }
        refreshDeviceState()
    }

    private func refreshDeviceState() {
        let device = UIDevice.current
        // Sul simulatore il livello non è disponibile (-1): viene trattato come batteria carica.
        batteryLevel = device.batteryLevel < 0 ? 1 : device.batteryLevel
        isCharging = device.batteryState == .charging || device.batteryState == .full
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
    }

    /// Indica se le analisi costose vanno sospese per proteggere batteria e temperatura.
    func heavyWorkPauseReason(pauseOnLowBattery: Bool) -> PauseReason? {
        if thermalState == .serious || thermalState == .critical {
            return .thermal
        }
        guard pauseOnLowBattery, !isCharging else { return nil }
        if isLowPowerMode { return .lowPowerMode }
        if batteryLevel < 0.20 { return .lowBattery }
        return nil
    }

    /// Indica se è consentito scaricare contenuti da iCloud con la rete attuale.
    func canDownload(wifiOnly: Bool) -> Bool {
        guard isOnline else { return false }
        return wifiOnly ? isOnUnmeteredNetwork : true
    }

    var networkDescription: String {
        if !isOnline { return "Nessuna connessione" }
        return isOnUnmeteredNetwork ? "Wi‑Fi" : "Rete cellulare o a consumo"
    }
}
