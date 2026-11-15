import Charts
import SwiftUI

/// Risultati: ciò che è stato realmente fatto e lo spazio effettivamente recuperato,
/// con iPhone e iCloud sempre distinti.
struct ResultsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var currentSnapshot: StorageSnapshot?
    @State private var toast: String?

    private var stats: LifetimeStats { env.history.stats }

    private struct MonthlyPoint: Identifiable {
        let id: String
        let label: String
        let gigabytes: Double
    }

    var body: some View {
        NavigationStack {
            List {
                activitySection
                spaceSection
                comparisonSection
                chartSection
                historySection
                reminderSection
            }
            .navigationTitle("Risultati")
            .task(id: env.history.reports.count) {
                currentSnapshot = DeviceStorage.snapshot()
            }
            .toast($toast)
        }
    }

    // MARK: - Attività

    private var activitySection: some View {
        Section("Attività") {
            DetailRow(label: "Elementi esaminati", value: Format.count(stats.reviewed))
            DetailRow(label: "Conservati", value: Format.count(stats.kept))
            DetailRow(label: "Proposti per l'eliminazione", value: Format.count(stats.marked))
            DetailRow(label: "Rimandati", value: Format.count(stats.postponed))
            DetailRow(label: "Eliminati", value: Format.count(stats.deleted))
            if stats.failed > 0 {
                DetailRow(label: "Operazioni non riuscite", value: Format.count(stats.failed))
            }
        }
    }

    private var spaceSection: some View {
        Section {
            DetailRow(label: "Sull'iPhone", value: Format.bytes(stats.deviceBytesFreed))
            if stats.cloudBytesFreed > 0 || stats.conditionalCloudBytes == 0 {
                DetailRow(label: "Su iCloud", value: Format.bytes(stats.cloudBytesFreed))
            }
            if stats.conditionalCloudBytes > 0 {
                DetailRow(label: "Su iCloud, se Foto di iCloud è attivo", value: "fino a \(Format.bytes(stats.conditionalCloudBytes))")
            }
        } header: {
            Text("Spazio effettivamente recuperato")
        } footer: {
            Text("Conta soltanto ciò che è stato davvero eliminato. I valori di iPhone e iCloud non vanno sommati: sono gli stessi contenuti visti da due posizioni. Per le foto lo spazio diventa disponibile quando Eliminati di recente viene svuotato.")
        }
    }

    // MARK: - Confronto prima/dopo

    @ViewBuilder
    private var comparisonSection: some View {
        if let report = env.history.lastReport, let before = report.snapshotBefore {
            Section {
                DetailRow(label: "Spazio libero prima", value: Format.bytes(before.availableBytes))
                if let after = report.snapshotAfter {
                    DetailRow(label: "Spazio libero dopo", value: Format.bytes(after.availableBytes))
                    DetailRow(label: "Misurato il", value: Format.dateTime(after.date))
                }
                if let current = currentSnapshot {
                    DetailRow(label: "Spazio libero adesso", value: Format.bytes(current.availableBytes))
                }
                Button("Aggiorna la misura") {
                    measureAgain(reportID: report.id)
                }
            } header: {
                Text("Confronto prima/dopo")
            } footer: {
                Text("Dopo la sincronizzazione con iCloud e lo svuotamento di Eliminati di recente la misura può cambiare: aggiornala per vedere il risultato effettivo.")
            }
        }
    }

    private func measureAgain(reportID: UUID) {
        guard let snapshot = DeviceStorage.snapshot() else { return }
        env.history.updateSnapshotAfter(reportID: reportID, snapshot: snapshot)
        currentSnapshot = snapshot
        toast = "Misura aggiornata."
    }

    // MARK: - Andamento

    private var monthlyPoints: [MonthlyPoint] {
        let calendar = Calendar.current
        var totals: [String: (date: Date, bytes: Int64)] = [:]
        for report in env.history.reports {
            let components = calendar.dateComponents([.year, .month], from: report.date)
            guard let year = components.year, let month = components.month,
                  let monthStart = calendar.date(from: components) else {
                continue
            }
            let key = "\(year)-\(month)"
            let existing = totals[key]?.bytes ?? 0
            totals[key] = (monthStart, existing + report.deviceBytesFreed)
        }
        let ordered = totals.values.sorted { $0.date < $1.date }.suffix(6)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "MMM yy"
        return ordered.map { entry in
            MonthlyPoint(
                id: formatter.string(from: entry.date),
                label: formatter.string(from: entry.date),
                gigabytes: Double(entry.bytes) / Double(AppConfiguration.Thresholds.gigabyte)
            )
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        let points = monthlyPoints
        if points.count >= 2 {
            Section("Spazio liberato sull'iPhone per mese") {
                Chart(points) { point in
                    BarMark(
                        x: .value("Mese", point.label),
                        y: .value("GB", point.gigabytes)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 180)
                .padding(.vertical, 8)
                .accessibilityLabel("Grafico dello spazio liberato per mese")
            }
        }
    }

    // MARK: - Cronologia

    private var historySection: some View {
        Section("Cronologia delle operazioni") {
            if env.history.reports.isEmpty {
                Text("Nessuna operazione eseguita finora.")
                    .foregroundStyle(.secondary)
            }
            ForEach(env.history.reports) { report in
                NavigationLink {
                    ReportDetailView(report: report)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Format.dateTime(report.date))
                            .font(.subheadline.weight(.medium))
                        Text("\(report.deletedCount) eliminati · \(report.failedCount) non riusciti · iPhone \(Format.bytes(report.deviceBytesFreed))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Promemoria

    private var reminderSection: some View {
        Section {
            Picker("Promemoria", selection: reminderBinding) {
                ForEach(ReminderFrequency.allCases, id: \.self) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
        } footer: {
            Text("Un promemoria ti invita a una nuova pulizia. Non avvia mai eliminazioni automatiche.")
        }
    }

    private var reminderBinding: Binding<ReminderFrequency> {
        Binding(
            get: { env.preferences.values.reminderFrequency },
            set: { frequency in
                env.preferences.update { $0.reminderFrequency = frequency }
                Task {
                    let granted = await env.reminders.apply(frequency)
                    if !granted {
                        env.preferences.update { $0.reminderFrequency = .off }
                        toast = "Le notifiche non sono autorizzate: attivale dalle Impostazioni."
                    }
                }
            }
        )
    }
}

/// Dettaglio di una singola operazione.
struct ReportDetailView: View {
    let report: CleanupReport

    var body: some View {
        List {
            ReportSummarySections(report: report)
            Section("Elementi (\(report.outcomes.count))") {
                ForEach(report.outcomes) { outcome in
                    HStack {
                        Image(systemName: outcome.category.systemImage)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.title)
                                .lineLimit(1)
                            Text(outcome.state.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(max(outcome.deviceBytes, outcome.cloudBytes)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(Format.date(report.date))
        .navigationBarTitleDisplayMode(.inline)
    }
}
