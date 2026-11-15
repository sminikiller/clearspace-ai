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
                NavigationLink {
                    GroupComparisonView(groupID: entry.group.id)
                } label: {
                    GroupRow(entry: entry)
                }
            }
        }
        .navigationTitle(collection.title)
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

/// Confronto affiancato dei membri di un gruppo, con il candidato suggerito e la spiegazione.
struct GroupComparisonView: View {
    let groupID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var previewItem: IndexedItem?
    @State private var toast: String?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let _ = env.store.revision
        ScrollView {
            if let group = env.store.group(groupID) {
                let members = env.store.members(of: group)
                VStack(alignment: .leading, spacing: 14) {
                    suggestionCard(group: group, members: members)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            memberCard(member, position: index + 1, isSuggested: member.id == group.suggestedKeepID)
                        }
                    }
                    actions(group: group, members: members)
                }
                .padding(16)
            } else {
                ContentUnavailableView(
                    "Gruppo non più disponibile",
                    systemImage: "square.on.square",
                    description: Text("Gli elementi sono cambiati dall'ultima analisi.")
                )
                .padding(.top, 60)
            }
        }
        .background(Theme.background)
        .navigationTitle("Confronto")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewItem) { item in
            ItemPreviewScreen(itemID: item.id)
        }
        .toast($toast)
    }

    private func suggestionCard(group: ItemGroup, members: [IndexedItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TagChip(
                text: group.kind.title,
                systemImage: group.kind == .exactDuplicate ? "checkmark.seal.fill" : "square.stack.3d.down.right",
                tint: group.kind == .exactDuplicate ? Theme.keep : Theme.info
            )
            Text(group.certainty.explanation)
                .font(.subheadline)
            if let keepID = group.suggestedKeepID,
               let position = members.firstIndex(where: { $0.id == keepID }),
               let reason = group.suggestionReason {
                Text(QualityRanker.sentence(position: position + 1, noun: noun(for: members[position]), reason: reason))
                    .font(.subheadline.weight(.semibold))
            }
            if let note = group.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func memberCard(_ member: IndexedItem, position: Int, isSuggested: Bool) -> some View {
        let blockReason = env.safety.blockReason(for: member)
        return VStack(alignment: .leading, spacing: 6) {
            ItemThumbnailView(item: member, pointSide: 220)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("\(position)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(6)
                }
                .onTapGesture {
                    previewItem = member
                }

            if isSuggested {
                TagChip(text: "Suggerita", systemImage: "star.fill", tint: Theme.keep)
            }
            Text(Format.bytesOrUnknown(member.estimatedBytes))
                .font(.caption.weight(.semibold))
            if member.pixelWidth > 0 {
                Text("\(member.pixelWidth) × \(member.pixelHeight)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let sharpness = member.sharpness, member.isImage {
                Text("Nitidezza \(Format.percent(sharpness))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(Format.date(member.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let blockReason {
                Label("Protetto", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHint(blockReason.message)
            } else {
                Picker("Decisione", selection: decisionBinding(for: member)) {
                    Text("Tieni").tag(false)
                    Text("Elimina").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isSuggested {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.keep, lineWidth: 2)
            }
        }
    }

    private func actions(group: ItemGroup, members: [IndexedItem]) -> some View {
        VStack(spacing: 10) {
            if group.suggestedKeepID != nil {
                Button {
                    keepOnlySuggested(group)
                } label: {
                    Text("Conserva solo la suggerita")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Button {
                env.safety.keep(members.map { $0.id })
                toast = "Tutti gli elementi del gruppo sono stati conservati."
            } label: {
                Text("Conserva tutte")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Gli elementi contrassegnati passano alla scheda Revisione: l'eliminazione avviene solo dopo la conferma finale.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// `true` = proposto per l'eliminazione, `false` = conservato.
    private func decisionBinding(for member: IndexedItem) -> Binding<Bool> {
        Binding(
            get: { env.store.item(member.id)?.reviewStatus.isQueuedForDeletion ?? false },
            set: { shouldDelete in
                env.safety.apply(shouldDelete ? .delete : .keep, to: member.id)
            }
        )
    }

    private func keepOnlySuggested(_ group: ItemGroup) {
        guard let keepID = group.suggestedKeepID else { return }
        env.safety.keep([keepID])
        let result = env.safety.markForDeletion(group.extraIDs)
        var message = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto saltato", "protetti saltati"))."
        }
        toast = message
    }

    private func noun(for item: IndexedItem) -> String {
        switch item.category {
        case .photo: return "la foto"
        case .video: return "il video"
        case .audio: return "la registrazione"
        case .pdf, .office, .archive, .otherDocument, .unknown: return "il file"
        }
    }
}
