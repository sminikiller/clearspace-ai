import SwiftUI

/// Gruppo pronto per essere mostrato, con i suoi membri e lo spazio potenziale.
private struct GroupEntry: Identifiable {
    let group: ItemGroup
    let members: [IndexedItem]
    /// Spazio degli elementi diversi da quello suggerito e ancora da decidere.
    let potentialBytes: Int64

    var id: UUID { group.id }
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

    private func reload() {
        let context = CollectionContext(now: Date(), largeVideoBytes: env.preferences.values.largeVideoBytes)
        let protection = env.safety.evaluator()
        var result: [GroupEntry] = []
        for group in env.store.groupsSnapshot() where group.kind.isDuplicateKind == collection.usesDuplicateGroups {
            let members = env.store.members(of: group)
            guard members.count >= 2, members.contains(where: { collection.contains($0, context: context) }) else {
                continue
            }
            let keepID = group.suggestedKeepID
            let potential = members.reduce(Int64(0)) { total, member in
                member.id != keepID && protection.isReviewable(member) ? total + member.bytes : total
            }
            result.append(GroupEntry(group: group, members: members, potentialBytes: potential))
        }
        entries = result.sorted { $0.potentialBytes > $1.potentialBytes }
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
            HStack(spacing: 6) {
                TagChip(text: entry.group.kind.title, tint: entry.group.kind == .exactDuplicate ? Theme.keep : Theme.info)
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
        .accessibilityElement(children: .combine)
    }
}
