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
            .onAppear { env.recordTutorial(.openConfirmation) }
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
            if report.recentlyDeletedCount > 0 {
                RecentlyDeletedSection(count: report.recentlyDeletedCount, deviceBytes: report.recentlyDeletedDeviceBytes)
            }
            Section {
                Button("Fine") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Le foto eliminate restano 30 giorni in Eliminati di recente e lo spazio si libera solo quando
/// quell'album viene svuotato. iOS non permette alle app di svuotarlo: la sezione spiega come fare e
/// apre l'app Foto.
struct RecentlyDeletedSection: View {
    let count: Int
    let deviceBytes: Int64
    /// Se presente compare «L'ho già svuotato», che nasconde l'avviso.
    var onDismiss: (() -> Void)?

    @Environment(\.openURL) private var openURL
    @State private var openFailed = false

    /// Apre l'app Foto. Non è un indirizzo documentato da Apple: se non funziona lo si dice.
    static let photosURL = URL(string: "photos-redirect://")

    static let howTo = "In Foto apri «Eliminati di recente» (nella sezione Utility, in fondo), tocca Seleziona e poi Elimina tutto. iOS chiede il codice o Face ID: è normale."

    /// "3 elementi sono in Eliminati di recente e occupano ancora 24 MB sull'iPhone…".
    static func explanation(count: Int, deviceBytes: Int64) -> String {
        let subject = Format.plural(count, "elemento è", "elementi sono")
        if deviceBytes > 0 {
            let verb = count == 1 ? "occupa" : "occupano"
            return "\(subject) in Eliminati di recente e \(verb) ancora \(Format.bytes(deviceBytes)) sull'iPhone. Per liberare subito lo spazio svuota quell'album; altrimenti iOS lo fa da solo dopo 30 giorni."
        }
        let stays = count == 1 ? "resta recuperabile" : "restano recuperabili"
        return "\(subject) in Eliminati di recente, dove \(stays) per 30 giorni. Svuotando quell'album lo spazio si libera subito."
    }

    private var explanation: String {
        Self.explanation(count: count, deviceBytes: deviceBytes)
    }

    var body: some View {
        Section {
            Text(explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Come fare")
                    .font(.subheadline.weight(.semibold))
                Text(Self.howTo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard let url = Self.photosURL else { return }
                openURL(url) { accepted in
                    openFailed = !accepted
                }
            } label: {
                Label("Apri l'app Foto", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("recentlyDeleted.openPhotos")
            if openFailed {
                Text("Non è stato possibile aprire Foto da qui: aprila dalla schermata Home.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let onDismiss {
                Button("L'ho già svuotato", action: onDismiss)
                    .font(.subheadline)
            }
        } header: {
            Text("Libera davvero lo spazio")
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
            // Con il solo valore condizionato, una riga "Su iCloud: 0 KB" sembrerebbe contraddirlo.
            if report.cloudBytesFreed > 0 || report.conditionalCloudBytes == 0 {
                DetailRow(label: "Su iCloud", value: Format.bytes(report.cloudBytesFreed))
            }
            if report.conditionalCloudBytes > 0 {
                DetailRow(label: "Su iCloud, se Foto di iCloud è attivo", value: "fino a \(Format.bytes(report.conditionalCloudBytes))")
            }
            // Subito dopo l'eliminazione lo spazio libero può non essere ancora aumentato, o persino
            // essere sceso per l'attività del sistema: si riporta solo un aumento realmente misurato.
            // I valori prima/dopo restano consultabili nella scheda Risultati.
            if let delta = report.measuredDeviceDelta, delta > 0 {
                DetailRow(label: "Aumento misurato dello spazio libero", value: "+\(Format.bytes(delta))")
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
}

/// Come liberare davvero lo spazio dopo un'eliminazione, in una scheda da usare fuori da un elenco.
struct RecentlyDeletedCard: View {
    let count: Int
    let deviceBytes: Int64

    @Environment(\.openURL) private var openURL
    @State private var openFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Libera davvero lo spazio")
                .font(.headline)
            Text(RecentlyDeletedSection.explanation(count: count, deviceBytes: deviceBytes))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(RecentlyDeletedSection.howTo)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard let url = RecentlyDeletedSection.photosURL else { return }
                openURL(url) { accepted in
                    openFailed = !accepted
                }
            } label: {
                Label("Apri l'app Foto", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("recentlyDeleted.openPhotos")
            if openFailed {
                Text("Non è stato possibile aprire Foto da qui: aprila dalla schermata Home.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
