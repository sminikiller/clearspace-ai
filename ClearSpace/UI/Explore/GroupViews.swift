import SwiftUI

/// Gruppo pronto per essere mostrato, con i suoi membri e quanto resta da decidere.
struct GroupEntry: Identifiable {
    let group: ItemGroup
    let members: [IndexedItem]
    /// Elementi da decidere e spazio che si libererebbe tenendo solo le migliori.
    let review: GroupReviewSummary

    var id: UUID { group.id }
    var potentialBytes: Int64 { review.potentialBytes }
    var isDecided: Bool { review.isDecided }
}

/// I gruppi di duplicati o di simili di una categoria, letti dall'indice.
@MainActor
enum GroupCatalog {

    /// Gruppi della categoria: prima quelli da decidere, da quello che libera più spazio.
    static func entries(for collection: SmartCollection, env: AppEnvironment) -> [GroupEntry] {
        let context = CollectionContext(now: Date(), largeVideoBytes: env.preferences.values.largeVideoBytes)
        let protection = env.safety.evaluator()
        var result: [GroupEntry] = []
        for group in env.store.groupsSnapshot() where group.kind.isDuplicateKind == collection.usesDuplicateGroups {
            let members = env.store.members(of: group)
            guard members.count >= 2, members.contains(where: { collection.contains($0, context: context) }) else {
                continue
            }
            let review = GroupReview.summary(members: members, suggestedID: group.suggestedKeepID, evaluator: protection)
            result.append(GroupEntry(group: group, members: members, review: review))
        }
        return GroupReview.ordered(result) { $0.review }
    }

    /// Gruppi da proporre uno dopo l'altro: quelli da decidere o, se sono tutti decisi, tutti.
    static func sequence(for collection: SmartCollection, env: AppEnvironment) -> [UUID] {
        GroupReview.sequence(entries(for: collection, env: env)) { $0.review }.map { $0.group.id }
    }
}

/// Elementi eliminati e spazio che occupano ancora finché resta pieno «Eliminati di recente».
private struct DeletionTally {
    var count = 0
    var bytes: Int64 = 0
}

/// Elenco dei gruppi di duplicati o di contenuti simili di una categoria.
struct GroupListView: View {
    let collection: SmartCollection

    @Environment(AppEnvironment.self) private var env
    @State private var entries: [GroupEntry] = []
    @State private var isLoading = true
    @State private var confirmsMarkAll = false
    @State private var toast: String?
    @State private var lastReload: Date?
    /// Eliminazioni fatte dalle gallerie da quando l'elenco è aperto: l'avviso in cima spiega come
    /// liberare davvero lo spazio.
    @State private var deletedHere = DeletionTally()

    var body: some View {
        ReadableList {
            if deletedHere.count > 0 {
                RecentlyDeletedSection(count: deletedHere.count, deviceBytes: deletedHere.bytes, onDismiss: {
                    deletedHere = DeletionTally()
                })
            }
            Section {
                explanation
                if entries.contains(where: { !$0.isDecided }) {
                    // Il modo più rapido: tutti i gruppi in una schermata, in ognuno resta la migliore.
                    NavigationLink {
                        GroupBatchView(collection: collection)
                    } label: {
                        batchLabel
                    }
                    .accessibilityIdentifier("groups.batch")
                }
                if !entries.isEmpty {
                    // Oppure un gruppo alla volta, guardandoli uno per uno.
                    NavigationLink {
                        GroupSequenceView(collection: collection)
                    } label: {
                        sequenceLabel
                    }
                    .accessibilityIdentifier("groups.sequence")
                }
            }
            if entries.isEmpty && !isLoading {
                if env.scan.isRunning {
                    // Durante l'analisi i gruppi arrivano man mano: meglio dirlo che mostrare «nessun gruppo».
                    ContentUnavailableView {
                        Label("Sto cercando i gruppi…", systemImage: "magnifyingglass")
                    } description: {
                        Text("L'analisi è in corso: i gruppi compaiono qui man mano che li trovo.")
                    } actions: {
                        ProgressView()
                    }
                } else {
                    ContentUnavailableView {
                        Label("Nessun gruppo trovato", systemImage: "square.on.square")
                    } description: {
                        Text("Completa l'analisi per cercare duplicati e contenuti simili.")
                    } actions: {
                        Button("Analizza ora") {
                            env.scan.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            ForEach(entries) { entry in
                // Si apre la galleria del gruppo: tutte le anteprime insieme, con la selezione multipla.
                // Da lì «Confronta» mostra le foto in grande una accanto all'altra.
                NavigationLink {
                    // Dopo «Elimina» si torna qui da soli: niente schermata intermedia da chiudere.
                    GroupSelectionView(groupID: entry.group.id, onDeleted: { decision in
                        deletedHere.count += decision.deletedCount
                        deletedHere.bytes += decision.freedBytes
                        toast = decision.message
                    })
                } label: {
                    GroupRow(entry: entry)
                }
                .accessibilityIdentifier("groups.row")
            }
        }
        .navigationTitle(collection.title)
        .onAppear {
            env.recordTutorial(.openGroups)
            // Al ritorno da una galleria la scelta fatta là si vede subito, anche durante un'analisi.
            if !entries.isEmpty {
                reload()
            }
        }
        .toolbar {
            if collection.usesDuplicateGroups && !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Proponi le copie in più") {
                        confirmsMarkAll = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Proporre per l'eliminazione le copie in più?",
            isPresented: $confirmsMarkAll,
            titleVisibility: .visible
        ) {
            Button("Aggiungi alla revisione") {
                markAllExtras()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Per ogni gruppo di duplicati verificati resta l'elemento suggerito; gli altri vengono aggiunti alla lista di revisione. Nulla viene eliminato finché non confermi.")
        }
        .task(id: env.listRevision) {
            // Durante un'analisi l'elenco già mostrato si aggiorna al massimo ogni pochi secondi.
            if !entries.isEmpty, env.scan.isRunning, let lastReload {
                let wait = ScanThrottle.wait(since: lastReload, now: Date())
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled else { return }
                }
            }
            reload()
        }
        .toast($toast)
        .sensoryFeedback(.success, trigger: deletedHere.count)
    }

    @ViewBuilder
    private var explanation: some View {
        if collection.usesDuplicateGroups {
            InfoBanner(text: "Copie dello stesso contenuto. «Esatti» sono verificati sull'originale, «probabili» solo sulle anteprime.")
        } else {
            InfoBanner(text: "Scatti simili, non identici: ClearSpace consiglia quale tenere, ma decidi tu.")
        }
    }

    /// "Tieni la migliore in tutti i gruppi · 12 gruppi · fino a 340 MB".
    private var batchLabel: some View {
        let pending = entries.filter { !$0.isDecided }
        let freeable = pending.reduce(Int64(0)) { $0 + $1.potentialBytes }
        return HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundStyle(Theme.keep)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tieni la migliore in tutti i gruppi")
                    .font(.headline)
                Text("Controlli tutto in una schermata ed elimini in un colpo solo · fino a \(Format.bytes(freeable))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Decidi un gruppo dopo l'altro · 12 da decidere · fino a 340 MB da liberare".
    private var sequenceLabel: some View {
        let pending = entries.filter { !$0.isDecided }
        let freeable = pending.reduce(Int64(0)) { $0 + $1.potentialBytes }
        return HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(pending.isEmpty ? "Rivedi i gruppi uno dopo l'altro" : "Decidi un gruppo dopo l'altro")
                    .font(.headline)
                Text(pending.isEmpty
                     ? "Sono tutti decisi: puoi ricontrollarli in sequenza."
                     : "\(Format.plural(pending.count, "gruppo da decidere", "gruppi da decidere")) · fino a \(Format.bytes(freeable)) da liberare")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Mentre si guarda l'elenco i gruppi già mostrati restano al loro posto, anche se l'analisi cambia
    /// lo spazio che liberano: i nuovi arrivano in fondo. L'ordine completo si rifà alla riapertura.
    private func reload() {
        lastReload = Date()
        let fresh = GroupCatalog.entries(for: collection, env: env)
        entries = StableOrder.merge(fresh, keeping: entries.map { $0.id }, id: { $0.id })
        isLoading = false
    }

    /// Solo per i duplicati verificati sul contenuto: le somiglianze richiedono sempre una scelta manuale.
    private func markAllExtras() {
        var ids: [UUID] = []
        for entry in entries where entry.group.kind == .exactDuplicate {
            ids.append(contentsOf: entry.group.extraIDs)
        }
        let result = env.safety.markForDeletion(ids)
        if result.applied == 0 {
            toast = "Nessun duplicato verificato da aggiungere."
        } else {
            toast = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        }
    }
}

/// Riga di un gruppo: le anteprime grandi su tutta la larghezza, poi quanti sono e cosa si può liberare
/// in parole semplici. Le scritte vanno a capo invece di tagliarsi.
private struct GroupRow: View {
    let entry: GroupEntry

    /// "3 foto", "2 video", "4 elementi".
    private var countText: String {
        let count = entry.members.count
        if entry.members.allSatisfy({ $0.isImage }) { return "\(count) foto" }
        if entry.members.allSatisfy({ $0.isVideo }) { return "\(count) video" }
        return Format.plural(count, "elemento", "elementi")
    }

    /// Cosa resta da fare nel gruppo, detto in una frase.
    private var statusText: String {
        if entry.isDecided {
            return "Deciso"
        }
        if entry.potentialBytes > 0 {
            return "Libera fino a \(Format.bytes(entry.potentialBytes))"
        }
        return "Scegli tu quale tenere"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupStrip(members: entry.members) { member in
                badge(for: member)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(countText)
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline.weight(entry.isDecided ? .regular : .semibold))
                        .foregroundStyle(entry.isDecided ? Theme.keep : Color.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // Su più righe se serve: con il testo grande nessuna etichetta esce dallo schermo.
            FlowLayout(spacing: 6, lineSpacing: 4) {
                TagChip(text: entry.group.kind.title, tint: entry.group.kind == .exactDuplicate ? Theme.keep : Theme.info)
                if entry.members.contains(where: { $0.isStarred }) {
                    TagChip(text: "Con la tua migliore", systemImage: "star.fill", tint: Theme.later)
                }
            }
            if let note = entry.group.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        // I gruppi già decisi restano consultabili, ma passano in secondo piano.
        .opacity(entry.isDecided ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Un solo segno per anteprima: cestino se è già proposta, stella se è tra le tue migliori,
    /// scintille se è quella consigliata.
    @ViewBuilder
    private func badge(for member: IndexedItem) -> some View {
        if member.reviewStatus.isQueuedForDeletion {
            GroupStripBadge(systemImage: "trash.fill", tint: Theme.remove)
        } else if member.isStarred {
            GroupStripBadge(systemImage: "star.fill", tint: .black.opacity(0.6), symbolColor: Theme.best)
        } else if member.id == entry.group.suggestedKeepID {
            GroupStripBadge(systemImage: "sparkles", tint: Theme.keep)
        }
    }
}
