import Foundation
import Observation

private let historyFileName = "history.v1.bin"

/// Totali accumulati nel tempo. Lo spazio su iPhone e quello su iCloud restano separati:
/// sommarli significherebbe contare due volte gli stessi contenuti.
struct LifetimeStats: Codable, Equatable, Sendable {
    var reviewed = 0
    var kept = 0
    var marked = 0
    var postponed = 0
    var deleted = 0
    var failed = 0
    var deviceBytesFreed: Int64 = 0
    var cloudBytesFreed: Int64 = 0
    var conditionalCloudBytes: Int64 = 0
}

private struct HistoryData: Codable {
    var reports: [CleanupReport] = []
    var stats = LifetimeStats()
    var learner = PreferenceLearner()
    var checklist: [String: Bool] = [:]
    var recentSearches: [String] = []
}

/// Storico delle operazioni eseguite, statistiche, abitudini apprese e checklist dell'assistente app.
@MainActor
@Observable
final class HistoryStore {

    private(set) var reports: [CleanupReport] = []
    private(set) var stats = LifetimeStats()
    private(set) var learner = PreferenceLearner()
    private(set) var checklist: [String: Bool] = [:]
    private(set) var recentSearches: [String] = []

    @ObservationIgnored private var saveRunning = false
    @ObservationIgnored private var saveDirty = false

    private let files: SecureFileStore

    init(files: SecureFileStore = SecureFileStore()) {
        self.files = files
    }

    func load() async {
        let files = self.files
        let loaded = await Task.detached(priority: .userInitiated) {
            files.load(HistoryData.self, from: historyFileName)
        }.value
        guard let loaded else { return }
        reports = loaded.reports
        stats = loaded.stats
        learner = loaded.learner
        checklist = loaded.checklist
        recentSearches = loaded.recentSearches
    }

    var lastReport: CleanupReport? { reports.first }

    // MARK: - Resoconti

    func add(_ report: CleanupReport) {
        reports.insert(report, at: 0)
        if reports.count > 200 {
            reports.removeLast(reports.count - 200)
        }
        stats.deleted += report.deletedCount
        stats.failed += report.failedCount
        stats.deviceBytesFreed += report.deviceBytesFreed
        stats.cloudBytesFreed += report.cloudBytesFreed
        stats.conditionalCloudBytes += report.conditionalCloudBytes
        scheduleSave()
    }

    /// Registra una nuova misura dello spazio libero per un resoconto (confronto prima/dopo).
    func updateSnapshotAfter(reportID: UUID, snapshot: StorageSnapshot) {
        guard let index = reports.firstIndex(where: { $0.id == reportID }) else { return }
        reports[index].snapshotAfter = snapshot
        scheduleSave()
    }

    // MARK: - Decisioni e abitudini

    func recordDecision(_ choice: SwipeChoice, bucket: LearningBucket) {
        stats.reviewed += 1
        switch choice {
        case .keep: stats.kept += 1
        case .delete: stats.marked += 1
        case .postpone: stats.postponed += 1
        }
        learner.record(choice, bucket: bucket)
        scheduleSave()
    }

    func revertDecision(_ choice: SwipeChoice, bucket: LearningBucket) {
        stats.reviewed = max(0, stats.reviewed - 1)
        switch choice {
        case .keep: stats.kept = max(0, stats.kept - 1)
        case .delete: stats.marked = max(0, stats.marked - 1)
        case .postpone: stats.postponed = max(0, stats.postponed - 1)
        }
        learner.revert(choice, bucket: bucket)
        scheduleSave()
    }

    // MARK: - Checklist e ricerche

    func isChecked(_ id: String) -> Bool {
        checklist[id] ?? false
    }

    func setChecked(_ checked: Bool, id: String) {
        checklist[id] = checked
        scheduleSave()
    }

    func rememberSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 8 {
            recentSearches.removeLast(recentSearches.count - 8)
        }
        scheduleSave()
    }

    // MARK: - Persistenza

    private func scheduleSave() {
        if saveRunning {
            saveDirty = true
            return
        }
        saveRunning = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            await self?.runSaveLoop()
        }
    }

    private func runSaveLoop() async {
        repeat {
            saveDirty = false
            await write()
        } while saveDirty
        saveRunning = false
    }

    private func write() async {
        let data = HistoryData(
            reports: reports,
            stats: stats,
            learner: learner,
            checklist: checklist,
            recentSearches: recentSearches
        )
        let files = self.files
        await Task.detached(priority: .utility) {
            try? files.save(data, as: historyFileName)
        }.value
    }

    func flush() async {
        await write()
    }
}
