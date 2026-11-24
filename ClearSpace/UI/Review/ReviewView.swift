import SwiftUI

/// Revisione: l'elenco completo di ciò che è stato proposto per l'eliminazione.
/// Da qui si può ripristinare un singolo elemento, un intero gruppo o annullare tutto.
/// L'eliminazione parte soltanto dopo la schermata di conferma.
struct ReviewView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var items: [IndexedItem] = []
    @State private var plan: DeletionPlan?
    @State private var isPreparing = false
    @State private var confirmsRestoreAll = false
    @State private var showsArchiveWizard = false
    @State private var previewItem: IndexedItem?
    @State private var toast: String?

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 3)]

    private struct ReviewSection: Identifiable {
        let id: String
        let title: String
        let items: [IndexedItem]

        var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("Revisione")
            .toolbar {
                if !items.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Annulla tutto") {
                            confirmsRestoreAll = true
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !items.isEmpty {
                    bottomBar
                }
            }
            .task(id: env.listRevision) {
                items = env.store.markedItems()
            }
            .sheet(item: $plan) { prepared in
                DeletionConfirmationView(plan: prepared)
            }
            .sheet(isPresented: $showsArchiveWizard) {
                ArchiveWizardView(itemIDs: items.map { $0.id })
            }
            .fullScreenCover(item: $previewItem) { item in
                ItemPreviewScreen(
                    itemID: item.id,
                    itemIDs: ItemPreviewScreen.window(items.map { $0.id }, around: item.id),
                    showsActions: false
                )
            }
            .confirmationDialog(
                "Annullare tutte le selezioni?",
                isPresented: $confirmsRestoreAll,
                titleVisibility: .visible
            ) {
                Button("Ripristina tutti gli elementi") {
                    env.safety.restoreAll()
                    toast = "Tutte le selezioni sono state annullate."
                }
                Button("Indietro", role: .cancel) {}
            } message: {
                Text("Gli elementi torneranno tra quelli da rivedere. Nessun file viene modificato.")
            }
            .toast($toast)
        }
    }

    // MARK: - Contenuto

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "Nessun elemento da eliminare",
                    systemImage: "checklist",
                    description: Text("Gli elementi che proponi per l'eliminazione compaiono qui. Nulla viene cancellato finché non confermi.")
                )
                .padding(.top, 40)
                lastReportBanner
                    .padding(.horizontal, 16)
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Prima ciò che sta per essere eliminato: con il testo grande le spiegazioni sopra
                // spingevano l'elenco sotto le barre.
                ForEach(sections) { section in
                    sectionView(section)
                }
                InfoBanner(text: "Tocca la freccia blu per tenere un elemento. Si elimina solo dopo la conferma finale.")
                lastReportBanner
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private var sections: [ReviewSection] {
        var photos: [IndexedItem] = []
        var videos: [IndexedItem] = []
        var files: [IndexedItem] = []
        var audio: [IndexedItem] = []
        var imports: [IndexedItem] = []
        for item in items {
            if item.source == .appImports {
                imports.append(item)
            } else if item.category == .audio {
                audio.append(item)
            } else if item.source == .photoLibrary {
                if item.category == .video {
                    videos.append(item)
                } else {
                    photos.append(item)
                }
            } else {
                files.append(item)
            }
        }
        let all = [
            ReviewSection(id: "photos", title: "Foto", items: photos),
            ReviewSection(id: "videos", title: "Video", items: videos),
            ReviewSection(id: "files", title: "File e documenti", items: files),
            ReviewSection(id: "audio", title: "Audio", items: audio),
            ReviewSection(id: "imports", title: "Copie importate in ClearSpace", items: imports)
        ]
        return all.filter { !$0.items.isEmpty }
    }

    private func sectionView(_ section: ReviewSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                    Text("\(Format.plural(section.items.count, "elemento", "elementi")) · \(Format.bytes(section.bytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Ripristina gruppo") {
                    env.recordTutorial(.restoreGroup)
                    env.safety.restore(section.items.map { $0.id })
                }
                .font(.subheadline)
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(section.items) { item in
                    ItemTile(item: item)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                env.recordTutorial(.restoreItem)
                                env.safety.restore([item.id])
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .padding(4)
                            }
                            .accessibilityLabel("Ripristina")
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if item.isSensitive {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Theme.later, in: Circle())
                                    .padding(4)
                                    .accessibilityLabel("Contenuto potenzialmente importante")
                            }
                        }
                        .onTapGesture {
                            previewItem = item
                        }
                }
            }
        }
    }

    /// Esito dell'ultima operazione, con i tre stati: eliminato, non riuscito, in attesa.
    @ViewBuilder
    private var lastReportBanner: some View {
        if let report = env.history.lastReport, Date().timeIntervalSince(report.date) < 86_400 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ultima operazione · \(Format.dateTime(report.date))")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 14) {
                    Label("\(report.deletedCount)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.keep)
                        .accessibilityLabel("Eliminati correttamente: \(report.deletedCount)")
                    Label("\(report.failedCount)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(Theme.remove)
                        .accessibilityLabel("Operazioni non riuscite: \(report.failedCount)")
                    Label("\(report.pendingCount)", systemImage: "clock.fill")
                        .foregroundStyle(Theme.later)
                        .accessibilityLabel("In attesa: \(report.pendingCount)")
                }
                .font(.subheadline.weight(.medium))
                if report.failedCount > 0 {
                    Text("Gli elementi non riusciti sono rimasti in elenco: puoi riprovare o ripristinarli.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Vedi il resoconto") {
                    env.router.selectedTab = .results
                }
                .font(.footnote)
            }
            .card()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Conteggio e «Archivia prima» su una riga se ci stanno: la barra resta bassa.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    summary
                    Spacer(minLength: 8)
                    archiveButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    summary
                    archiveButton
                }
            }
            Button {
                preparePlan()
            } label: {
                if isPreparing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Controlla ed elimina", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.remove)
            .controlSize(.large)
            .disabled(isPreparing)
        }
        .padding(12)
        .background(.bar)
        .compactControlText()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Format.plural(items.count, "elemento", "elementi")) da eliminare")
                .font(.subheadline.weight(.semibold))
            Text("Sull'iPhone: \(Format.bytes(deviceBytes)) · Dimensione totale: \(Format.bytes(totalBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var archiveButton: some View {
        Button {
            env.recordTutorial(.archiveWizard)
            showsArchiveWizard = true
        } label: {
            Label("Archivia prima", systemImage: "archivebox")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var deviceBytes: Int64 { items.reduce(0) { $0 + $1.deviceBytes } }
    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    private func preparePlan() {
        isPreparing = true
        Task {
            let prepared = await env.safety.makePlan()
            isPreparing = false
            if prepared.isEmpty {
                toast = "Nessun elemento può essere eliminato: controlla protezioni e permessi."
            } else {
                plan = prepared
            }
        }
    }
}
