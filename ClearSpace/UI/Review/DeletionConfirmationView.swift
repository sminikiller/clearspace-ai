import SwiftUI

/// Conferma finale: mostra con precisione cosa verrà eliminato e quali sono gli effetti
/// su iPhone e su iCloud. Solo da qui può partire un'eliminazione.
struct DeletionConfirmationView: View {
    let plan: DeletionPlan

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgedICloud = false
    @State private var acknowledgedSensitive = false
    @State private var allowPermanent = false
    @State private var isExecuting = false
    @State private var progress: ExecutionProgress?
    @State private var report: CleanupReport?

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    resultView(report)
                } else if isExecuting {
                    executingView
                } else {
                    form
                }
            }
            .navigationTitle(report == nil ? "Conferma eliminazione" : "Esito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if report == nil && !isExecuting {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(isExecuting)
        }
    }

    // MARK: - Riepilogo prima della conferma

    private var canConfirm: Bool {
        if plan.affectsICloud && !acknowledgedICloud { return false }
        if plan.sensitiveCount > 0 && !acknowledgedSensitive { return false }
        return !plan.isEmpty
    }

    private var form: some View {
        List {
            Section("Cosa verrà eliminato") {
                if plan.libraryCount > 0 {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.plural(plan.libraryCount, "foto o video", "foto e video"))
                            Text("Verranno spostati in Eliminati di recente e resteranno recuperabili per 30 giorni.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                if plan.fileCount > 0 {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.plural(plan.fileCount, "file", "file"))
                            Text("Verranno spostati nel cestino dell'app File, quando la posizione lo supporta.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc")
                    }
                }
                if plan.importCount > 0 {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.plural(plan.importCount, "copia importata", "copie importate"))
                            Text("Viene rimossa solo la copia dentro ClearSpace: l'originale nell'app di origine non viene toccato.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }

            Section {
                DetailRow(label: "Sull'iPhone", value: Format.bytes(plan.deviceBytes))
                if plan.cloudBytes > 0 {
                    DetailRow(label: "Su iCloud", value: Format.bytes(plan.cloudBytes))
                }
                if plan.conditionalCloudBytes > 0 {
                    DetailRow(label: "Su iCloud, se Foto di iCloud è attivo", value: "fino a \(Format.bytes(plan.conditionalCloudBytes))")
                }
            } header: {
                Text("Spazio che si libererà")
            } footer: {
                Text("I due valori riguardano gli stessi contenuti visti da due posizioni: non vanno sommati. Per le foto lo spazio si libera davvero quando Eliminati di recente viene svuotato.")
            }

            if plan.affectsICloud {
                Section {
                    InfoBanner(
                        text: "Con Foto di iCloud o iCloud Drive, l'eliminazione vale anche per iCloud e per tutti gli altri dispositivi collegati al tuo account.",
                        systemImage: "icloud.fill",
                        tint: Theme.later
                    )
                    Toggle("Ho capito gli effetti su iCloud", isOn: $acknowledgedICloud)
                }
            }

            if plan.sensitiveCount > 0 {
                Section {
                    InfoBanner(
                        text: "\(Format.plural(plan.sensitiveCount, "elemento potrebbe essere importante", "elementi potrebbero essere importanti")): documenti, ricevute, codici o testi sensibili.",
                        systemImage: "exclamationmark.shield.fill",
                        tint: Theme.later
                    )
                    Toggle("Li ho controllati", isOn: $acknowledgedSensitive)
                }
            }

            if plan.fileCount > 0 {
                Section {
                    Toggle("Elimina definitivamente se il cestino non è disponibile", isOn: $allowPermanent)
                } footer: {
                    Text("Se resta disattivato, i file che non possono andare nel cestino non verranno eliminati e resteranno in elenco.")
                }
            }

            if !plan.exclusions.isEmpty {
                Section("Esclusi dall'operazione") {
                    ForEach(plan.exclusions) { exclusion in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exclusion.title)
                            Text(exclusion.reason.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                DisclosureGroup("Elenco completo (\(plan.entries.count))") {
                    ForEach(plan.entries) { entry in
                        HStack {
                            Image(systemName: entry.category.systemImage)
                                .foregroundStyle(.secondary)
                            Text(entry.title)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.bytes(max(entry.deviceBytes, entry.cloudBytes)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    execute()
                } label: {
                    Text("Elimina \(Format.plural(plan.entries.count, "elemento", "elementi"))")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canConfirm)
            } footer: {
                if plan.libraryCount > 0 {
                    Text("Per foto e video iOS mostrerà un'ulteriore richiesta di conferma.")
                }
            }
        }
    }

    // MARK: - Esecuzione

    private var executingView: some View {
        VStack(spacing: 16) {
            if let progress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .padding(.horizontal, 40)
                Text(progress.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
            Text("Non chiudere l'app fino al termine.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func execute() {
        isExecuting = true
        let confirmation = DeletionConfirmation(
            planID: plan.id,
            confirmedAt: Date(),
            acknowledgedICloudEffects: acknowledgedICloud,
            acknowledgedSensitiveItems: acknowledgedSensitive,
            allowPermanentFileDeletion: allowPermanent
        )
        Task {
            // Un'analisi in corso potrebbe reinserire nell'indice elementi appena eliminati: prima la si ferma.
            if env.scan.isRunning {
                env.scan.cancel()
                for _ in 0..<30 where env.scan.isRunning {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let result = await env.safety.execute(plan, confirmation: confirmation) { update in
                progress = update
            }
            report = result
            isExecuting = false
            // Una scansione leggera riallinea l'indice a ciò che è realmente rimasto.
            if result.deletedCount > 0 && !env.scan.isRunning {
                env.scan.start(deep: false)
            }
        }
    }

    private func resultView(_ report: CleanupReport) -> some View {
        List {
            ReportSummarySections(report: report)
            Section {
                Button("Fine") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Sezioni che descrivono l'esito di un'operazione: i tre stati, lo spazio e gli eventuali errori.
struct ReportSummarySections: View {
    let report: CleanupReport

    var body: some View {
        Section("Esito") {
            stateRow("Eliminati correttamente", report.deletedCount, "checkmark.circle.fill", Theme.keep)
            stateRow("Operazioni non riuscite", report.failedCount, "xmark.circle.fill", Theme.remove)
            stateRow("In attesa", report.pendingCount, "clock.fill", Theme.later)
            if report.skippedCount > 0 {
                stateRow("Esclusi", report.skippedCount, "minus.circle.fill", .gray)
            }
            if let note = report.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            DetailRow(label: "Sull'iPhone", value: Format.bytes(report.deviceBytesFreed))
            DetailRow(label: "Su iCloud", value: Format.bytes(report.cloudBytesFreed))
            if report.conditionalCloudBytes > 0 {
                DetailRow(label: "Su iCloud, se Foto di iCloud è attivo", value: "fino a \(Format.bytes(report.conditionalCloudBytes))")
            }
            if let delta = report.measuredDeviceDelta {
                DetailRow(label: "Variazione misurata dello spazio libero", value: signedBytes(delta))
            }
        } header: {
            Text("Spazio recuperato")
        } footer: {
            Text("Sono conteggiati solo gli elementi realmente eliminati. iPhone e iCloud sono riportati separatamente perché riguardano gli stessi contenuti.")
        }

        let problems = report.outcomes.filter { $0.state == .failed || $0.state == .skipped }
        if !problems.isEmpty {
            Section("Dettagli") {
                ForEach(problems) { outcome in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome.title)
                            .lineLimit(1)
                        Text("\(outcome.state.title) · \(outcome.message ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func stateRow(_ title: String, _ count: Int, _ systemImage: String, _ tint: Color) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(count > 0 ? tint : .secondary)
            Spacer()
            Text(Format.count(count))
                .font(.body.weight(.semibold))
        }
    }

    private func signedBytes(_ value: Int64) -> String {
        if value == 0 { return "0 KB" }
        return (value > 0 ? "+" : "−") + Format.bytes(abs(value))
    }
}
