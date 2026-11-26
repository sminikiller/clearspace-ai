import SwiftUI

/// Tutti i gruppi in una schermata: in ognuno resta la migliore (la stella o la consigliata) e le
/// altre si eliminano in un colpo solo, con una sola conferma di iOS.
///
/// Prima di eliminare si vede tutto: le foto di ogni gruppo, quella che resta con il segno verde e
/// quelle da eliminare con il cestino. Il cerchio a sinistra esclude un gruppo; un tocco sulle foto apre
/// la galleria del gruppo per cambiare le scelte. I gruppi senza stelle e senza consiglio non vengono
/// proposti: lì la scelta va fatta a mano.
struct GroupBatchView: View {
    let collection: SmartCollection

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var plans: [GroupBatch.Plan] = []
    @State private var excluded = Set<UUID>()
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var confirmsDeletion = false
    @State private var toast: String?
    @State private var outcome: DirectDeletionResult?
    @State private var deletionsDone = 0
    /// Eliminati dalle gallerie aperte da qui: dopo «Elimina» la galleria torna da sola a questa schermata.
    @State private var galleryDeletedCount = 0
    @State private var galleryDeletedBytes: Int64 = 0

    /// Oltre questo numero di elementi ClearSpace chiede conferma anche per le sole foto.
    private static var largeDeletion: Int { 100 }

    private var totals: GroupBatch.Totals {
        GroupBatch.totals(plans, excluding: excluded)
    }

    /// "foto", "video" o "elementi", secondo la categoria.
    private var noun: (one: String, many: String) {
        switch collection.section {
        case .photos: return ("foto", "foto")
        case .videos: return ("video", "video")
        case .documents, .audio: return ("elemento", "elementi")
        }
    }

    private func count(_ value: Int) -> String {
        "\(value) \(value == 1 ? noun.one : noun.many)"
    }

    var body: some View {
        Group {
            if let outcome {
                outcomeView(outcome)
            } else {
                content
            }
        }
        .background(Theme.background)
        .navigationTitle("Tutti i gruppi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            env.recordTutorial(.groupBatch)
            // Anche al ritorno da una galleria: i gruppi decisi là escono dall'elenco.
            reload()
        }
        .confirmationDialog(
            "Eliminare \(count(totals.items))?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Elimina \(count(totals.items))", role: .destructive) {
                performDeletion()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(deletionMessage)
        }
        .sensoryFeedback(.success, trigger: deletionsDone)
        .sensoryFeedback(.success, trigger: galleryDeletedCount)
        .toast($toast)
    }

    // MARK: - Elenco

    @ViewBuilder
    private var content: some View {
        if plans.isEmpty {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    introduction
                    if galleryDeletedCount > 0 {
                        RecentlyDeletedCard(count: galleryDeletedCount, deviceBytes: galleryDeletedBytes)
                    }
                    ForEach(plans) { plan in
                        row(plan)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In ogni gruppo resta la migliore")
                .font(.headline)
            Text("Quella con la stella o, se non c'è, quella consigliata (segno verde). Le altre, con il cestino, si eliminano. Tocca il cerchio per escludere un gruppo, oppure le foto per cambiare le scelte.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func row(_ plan: GroupBatch.Plan) -> some View {
        let included = !excluded.contains(plan.groupID)
        let members = env.store.items(plan.keep + plan.delete)
        let ordered = orderedMembers(members, plan: plan)
        return HStack(alignment: .center, spacing: 12) {
            Button {
                toggle(plan.groupID)
            } label: {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(included ? Theme.remove : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(included ? "Gruppo incluso" : "Gruppo escluso")
            .accessibilityHint("Tocca per includerlo o escluderlo dall'eliminazione")
            .accessibilityIdentifier("batch.toggle")

            NavigationLink {
                // Dopo «Elimina» si torna qui da soli, con l'esito e come svuotare «Eliminati di recente».
                GroupSelectionView(groupID: plan.groupID, onDeleted: { decision in
                    galleryDeletedCount += decision.deletedCount
                    galleryDeletedBytes += decision.freedBytes
                    toast = decision.message
                })
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    thumbnails(ordered, plan: plan, included: included)
                    Text("\(count(plan.delete.count)) da eliminare · \(Format.bytes(plan.deleteBytes))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(included ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Apre la galleria del gruppo per cambiare le scelte")
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(included ? 1 : 0.6)
    }

    /// Prima quella che resta, poi le altre nell'ordine del gruppo.
    private func orderedMembers(_ members: [IndexedItem], plan: GroupBatch.Plan) -> [IndexedItem] {
        let keep = Set(plan.keep)
        return members.filter { keep.contains($0.id) } + members.filter { !keep.contains($0.id) }
    }

    /// Anteprime grandi su tutta la larghezza: prima quella che resta (segno verde), poi quelle da
    /// eliminare (cestino, spente).
    private func thumbnails(_ members: [IndexedItem], plan: GroupBatch.Plan, included: Bool) -> some View {
        let deleting = Set(plan.delete)
        return GroupStrip(
            members: members,
            dimmed: { included && deleting.contains($0.id) },
            accessibilityDescription: "\(members.count) \(noun.many): ne resta \(plan.keep.count), \(count(plan.delete.count)) da eliminare"
        ) { member in
            let deletes = included && deleting.contains(member.id)
            GroupStripBadge(systemImage: deletes ? "trash.fill" : "checkmark", tint: deletes ? Theme.remove : Theme.keep)
        }
    }

    private var emptyState: some View {
        CenteredScrollView {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.keep)
                    .accessibilityHidden(true)
                Text("Nessun gruppo da proporre")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("I gruppi sono già decisi, oppure non hanno né una stella né un consiglio: aprili dall'elenco e scegli a mano.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if galleryDeletedCount > 0 {
                    RecentlyDeletedCard(count: galleryDeletedCount, deviceBytes: galleryDeletedBytes)
                }
                if env.store.markedCount > 0 {
                    Button {
                        openReview()
                    } label: {
                        Text("Vai alla Revisione")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Button {
                    dismiss()
                } label: {
                    Text("Torna ai gruppi")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    // MARK: - Barra delle azioni

    private var actionBar: some View {
        let totals = self.totals
        return VStack(spacing: 8) {
            // Il conteggio a sinistra, lo spazio che si libera a destra: nessuna scritta tagliata.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totals.groups == 0
                     ? "Nessun gruppo incluso"
                     : "\(count(totals.items)) da eliminare in \(Format.plural(totals.groups, "gruppo", "gruppi"))")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("batch.summary")
                Spacer(minLength: 4)
                if totals.bytes > 0 {
                    Text(Format.bytes(totals.bytes))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.remove)
                        .accessibilityLabel("Liberi fino a \(Format.bytes(totals.bytes))")
                }
            }
            Button {
                startDeletion()
            } label: {
                Group {
                    if isDeleting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        // Lo spazio è già scritto sopra: qui basta il numero, che entra sempre.
                        ButtonTitle(totals.items == 0 ? "Elimina" : "Elimina \(totals.items)", systemImage: "trash")
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.remove)
            .controlSize(.large)
            .disabled(totals.items == 0 || isDeleting)
            .accessibilityIdentifier("batch.delete")
            Button {
                addToReview()
            } label: {
                Text("Aggiungi alla Revisione")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(totals.items == 0 || isDeleting)
            .accessibilityIdentifier("batch.review")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        // La barra resta compatta anche con il testo molto grande: l'elenco sopra deve restare visibile.
        .compactControlText()
    }

    // MARK: - Esito

    private func outcomeView(_ result: DirectDeletionResult) -> some View {
        CenteredScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.keep)
                    .accessibilityHidden(true)
                Text(result.summary(isImage: collection.section == .photos, isVideo: collection.section == .videos))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("batch.outcome")
                RecentlyDeletedCard(count: result.deletedCount, deviceBytes: result.freedBytes)
                Button {
                    dismiss()
                } label: {
                    Text("Torna ai gruppi")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    // MARK: - Azioni

    private func reload() {
        let evaluator = env.safety.evaluator()
        let candidates = GroupCatalog.entries(for: collection, env: env).map { entry in
            GroupBatch.Candidate(groupID: entry.group.id, members: entry.members, suggestedID: entry.group.suggestedKeepID)
        }
        let fresh = GroupBatch.plans(for: candidates) { evaluator.blockReason(for: $0) != nil }
        plans = StableOrder.merge(fresh, keeping: plans.map { $0.groupID }, id: { $0.groupID })
        excluded.formIntersection(Set(plans.map { $0.groupID }))
        isLoading = false
    }

    private func toggle(_ groupID: UUID) {
        if excluded.contains(groupID) {
            excluded.remove(groupID)
        } else {
            excluded.insert(groupID)
        }
    }

    private var includedPlans: [GroupBatch.Plan] {
        plans.filter { !excluded.contains($0.groupID) }
    }

    private func startDeletion() {
        let deleting = env.store.items(includedPlans.flatMap { $0.delete })
        guard !deleting.isEmpty, !isDeleting else { return }
        if env.needsInAppConfirmation(deleting) || deleting.count > Self.largeDeletion {
            confirmsDeletion = true
        } else {
            // Per foto e video basta la conferma di iOS, che mostra quante ne verranno eliminate.
            performDeletion()
        }
    }

    private func performDeletion() {
        let chosen = includedPlans
        let keep = chosen.flatMap { $0.keep }
        let delete = chosen.flatMap { $0.delete }
        guard !delete.isEmpty, !isDeleting else { return }
        isDeleting = true
        Task {
            let result = await env.deleteDirectly(keep: keep, delete: delete)
            isDeleting = false
            switch result.outcome {
            case .cancelled:
                toast = "Eliminazione annullata: non è stato eliminato nulla."
            case .nothing:
                toast = result.note ?? "Non è stato eliminato nulla."
                reload()
            case .deleted:
                deletionsDone += 1
                outcome = result
            }
        }
    }

    private func addToReview() {
        let chosen = includedPlans
        guard !chosen.isEmpty else { return }
        let result = env.sessions.decideGroup(keep: chosen.flatMap { $0.keep }, delete: chosen.flatMap { $0.delete })
        var message = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto saltato", "protetti saltati"))."
        }
        toast = message
        reload()
    }

    private var deletionMessage: String {
        let deleting = env.store.items(includedPlans.flatMap { $0.delete })
        var parts = ["In ogni gruppo resta la migliore. Liberi fino a \(Format.bytes(totals.bytes))."]
        if deleting.contains(where: { $0.source == .photoLibrary }) {
            parts.append("Restano 30 giorni in «Eliminati di recente» dell'app Foto e, con Foto di iCloud, spariscono anche dagli altri dispositivi.")
        }
        if deleting.contains(where: { $0.source != .photoLibrary }) {
            parts.append("I file vanno nel cestino dell'app File, se il servizio lo consente.")
        }
        let evaluator = env.safety.evaluator()
        let cautious = deleting.filter { evaluator.needsCaution($0) }.count
        if cautious > 0 {
            parts.append(cautious == 1
                         ? "Attenzione: uno potrebbe contenere qualcosa di importante."
                         : "Attenzione: \(cautious) potrebbero contenere qualcosa di importante.")
        }
        if deleting.contains(where: { $0.source == .photoLibrary }) {
            parts.append("iOS ti chiederà ancora una conferma.")
        }
        return parts.joined(separator: " ")
    }

    private func openReview() {
        let router = env.router
        dismiss()
        router.selectedTab = .review
    }
}
