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

/// Elenco dei gruppi di duplicati o di contenuti simili di una categoria.
struct GroupListView: View {
    let collection: SmartCollection

    @Environment(AppEnvironment.self) private var env
    @State private var entries: [GroupEntry] = []
    @State private var isLoading = true
    @State private var confirmsMarkAll = false
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                explanation
                if !entries.isEmpty {
                    // Il modo più rapido: si aprono i gruppi da decidere uno dopo l'altro.
                    NavigationLink {
                        GroupSequenceView(collection: collection)
                    } label: {
                        sequenceLabel
                    }
                    .accessibilityIdentifier("groups.sequence")
                }
            }
            if entries.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Nessun gruppo trovato",
                    systemImage: "square.on.square",
                    description: Text("Completa l'analisi per cercare duplicati e contenuti simili.")
                )
            }
            ForEach(entries) { entry in
                // Si apre la galleria del gruppo: tutte le anteprime insieme, con la selezione multipla.
                // Da lì «Confronta» mostra le foto in grande una accanto all'altra.
                NavigationLink {
                    GroupSelectionView(groupID: entry.group.id)
                } label: {
                    GroupRow(entry: entry)
                }
            }
        }
        .navigationTitle(collection.title)
        .onAppear { env.recordTutorial(.openGroups) }
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
            reload()
        }
        .toast($toast)
    }

    @ViewBuilder
    private var explanation: some View {
        if collection.usesDuplicateGroups {
            InfoBanner(text: "I duplicati esatti hanno lo stesso contenuto, verificato sull'originale. I probabili duplicati sono stati confrontati solo tramite le anteprime.")
        } else {
            InfoBanner(text: "Contenuti simili, non identici: ClearSpace suggerisce quale conservare, ma la scelta è tua. Puoi anche tenerli tutti.")
        }
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

    private func reload() {
        entries = GroupCatalog.entries(for: collection, env: env)
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

private struct GroupRow: View {
    let entry: GroupEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(entry.members.prefix(4)) { member in
                    ItemThumbnailView(item: member, pointSide: 70)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                if entry.members.count > 4 {
                    Text("+\(entry.members.count - 4)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 64)
                }
            }
            // Su più righe se serve: con il testo grande nessuna etichetta esce dallo schermo.
            FlowLayout(spacing: 6, lineSpacing: 4) {
                TagChip(text: entry.group.kind.title, tint: entry.group.kind == .exactDuplicate ? Theme.keep : Theme.info)
                if entry.isDecided {
                    TagChip(text: "Deciso", systemImage: "checkmark", tint: Theme.keep)
                }
                Text("\(entry.members.count) elementi · \(Format.bytes(entry.potentialBytes)) potenziali")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.members.contains(where: { $0.isStarred }) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.best)
                        .accessibilityLabel("con le tue migliori")
                }
            }
            if let note = entry.group.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        // I gruppi già decisi restano consultabili, ma passano in secondo piano.
        .opacity(entry.isDecided ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }
}
