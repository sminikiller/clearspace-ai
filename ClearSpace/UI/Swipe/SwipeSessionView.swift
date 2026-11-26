import SwiftUI

/// Modalità swipe: si esamina un elemento alla volta e si decide con un gesto.
///
/// - destra: conserva
/// - sinistra: aggiunge alla lista da eliminare (non elimina nulla)
/// - alto: mostra i dettagli
/// - basso: rimanda la decisione
///
/// Ogni gesto ha un pulsante equivalente, quindi la schermata è utilizzabile anche con VoiceOver
/// o senza trascinamenti. Le scelte vengono salvate subito: la sessione si può riprendere in seguito.
struct SwipeSessionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGSize = .zero
    @State private var isCommitting = false
    @State private var detailItem: IndexedItem?
    @State private var previewItem: IndexedItem?
    @State private var comparison: ComparisonTarget?
    @State private var gallery: GalleryTarget?
    @State private var toast: String?
    @State private var feedbackTrigger = 0
    @State private var markTrigger = 0

    private var sessions: SessionManager { env.sessions }

    /// Confronto da aprire: il gruppo e la foto da cui si parte.
    private struct ComparisonTarget: Identifiable {
        let groupID: UUID
        let itemID: UUID

        var id: UUID { groupID }
    }

    /// Galleria del gruppo da aprire, con la selezione multipla.
    private struct GalleryTarget: Identifiable {
        let groupID: UUID

        var id: UUID { groupID }
    }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .navigationTitle(sessions.active?.title ?? "Pulizia")
                .navigationBarTitleDisplayMode(.inline)
                // Pulsanti con la sola icona: il titolo della sessione ha lo spazio per leggersi intero.
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            sessions.closePresentation()
                        } label: {
                            Label("Chiudi", systemImage: "xmark")
                        }
                        .accessibilityHint("Le scelte restano salvate: puoi riprendere la sessione dalla Home")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openReview()
                        } label: {
                            Label("Revisione", systemImage: "checklist")
                        }
                        .accessibilityHint("Apre la lista degli elementi da eliminare")
                    }
                }
        }
        .sheet(item: $detailItem) { item in
            ItemDetailView(itemID: item.id)
        }
        .fullScreenCover(item: $previewItem) { item in
            ItemPreviewScreen(itemID: item.id, showsActions: false)
        }
        .fullScreenCover(item: $comparison) { target in
            NavigationStack {
                GroupComparisonView(
                    groupID: target.groupID,
                    initialItemID: target.itemID,
                    closesAfterDecision: true
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") {
                            comparison = nil
                        }
                    }
                }
            }
        }
        .sheet(item: $gallery) { target in
            NavigationStack {
                // Nello swipe le scelte passano dalla Revisione, come il resto della sessione.
                GroupSelectionView(groupID: target.groupID, closesAfterDecision: true, deletesDirectly: false)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") {
                                gallery = nil
                            }
                        }
                    }
            }
        }
        .toast($toast)
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: markTrigger)
        .onChange(of: env.store.revision) { _, _ in
            // Se un elemento sparisce o viene deciso altrove (ad esempio dal confronto di un gruppo),
            // si passa al successivo.
            sessions.skipUnavailableItems()
        }
        .task(id: sessions.currentItem?.id) {
            preheatUpcoming()
        }
        .task(id: currentGroupID) {
            // Se la scansione non ha ancora confrontato gli scatti di questo gruppo lo si fa adesso,
            // così il consiglio mostrato nella striscia usa già tutti i criteri.
            if let currentGroupID {
                await env.refineSuggestion(forGroup: currentGroupID)
            }
        }
        .onDisappear {
            env.thumbnails.stopPreheating()
        }
    }

    private var currentGroupID: UUID? {
        guard let item = sessions.currentItem else { return nil }
        return env.group(containing: item)?.id
    }

    /// Prepara le immagini delle prossime carte, così compaiono subito.
    private func preheatUpcoming() {
        let upcoming = sessions.upcomingItems(limit: 3).filter { $0.isImage }
        env.thumbnails.preheat(upcoming, pixelSide: 2_048, allowNetwork: env.canDownloadForViewing)
    }

    @ViewBuilder
    private var content: some View {
        if let session = sessions.active {
            if let item = sessions.currentItem {
                let group = env.group(containing: item)
                VStack(spacing: 12) {
                    SessionHeaderView(session: session)
                    deck(current: item, group: group)
                    if let group {
                        SimilarStripView(
                            group: group,
                            members: env.store.members(of: group),
                            currentID: item.id,
                            onSelect: { memberID in select(memberID) },
                            onOpenGrid: {
                                gallery = GalleryTarget(groupID: group.id)
                            },
                            onCompare: {
                                comparison = ComparisonTarget(groupID: group.id, itemID: item.id)
                            },
                            onKeepBest: { keepBest(of: group) },
                            onKeepOnlyCurrent: { keepOnly(item, in: group) },
                            onDecide: { memberID, choice in decideMember(memberID, choice) },
                            onToggleBest: { memberID in toggleBest(memberID) }
                        )
                    }
                    SwipeActionBar(
                        canUndo: sessions.canUndo,
                        onDelete: { env.recordTutorial(.actionButton); commit(.delete) },
                        onPostpone: { env.recordTutorial(.actionButton); commit(.postpone) },
                        onUndo: { undo() },
                        onDetails: { env.recordTutorial(.actionButton); detailItem = item },
                        onKeep: { env.recordTutorial(.actionButton); commit(.keep) }
                    )
                }
                // La schermata dello swipe non scorre: carta, striscia e pulsanti devono starci sempre.
                // Con il testo molto ingrandito le scritte si fermano a una dimensione che entra.
                .compactControlText()
            } else {
                SessionSummaryView(
                    session: session,
                    canUndo: sessions.canUndo,
                    onUndo: { undo() },
                    onReviewPostponed: { sessions.reviewPostponed() },
                    onOpenReview: { openReview() },
                    onClose: { sessions.completeActive() }
                )
            }
        } else {
            ContentUnavailableView(
                "Nessuna sessione attiva",
                systemImage: "rectangle.stack",
                description: Text("Avvia una pulizia dalla Home.")
            )
        }
    }

    // MARK: - Mazzo di carte

    private func deck(current item: IndexedItem, group: ItemGroup?) -> some View {
        ZStack {
            if let next = sessions.upcomingItems(limit: 1).first {
                // La carta successiva è già pronta sotto quella corrente.
                SwipeCardView(item: next, isInteractive: false)
                    .scaleEffect(0.95)
                    .opacity(0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            SwipeCardView(
                item: item,
                isInteractive: true,
                group: group,
                // Un video scelto dalla striscia parte subito: è stato toccato proprio per guardarlo.
                autoplaysVideo: sessions.active?.focusedItemID == item.id,
                isSuspended: comparison != nil || gallery != nil || previewItem != nil || detailItem != nil,
                onExpand: { env.recordTutorial(.fullScreen); previewItem = item }
            )
                .overlay {
                    SwipeStampOverlay(offset: offset)
                }
                .offset(offset)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset.width) / 22))
                .gesture(dragGesture)
                .id(item.id)
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Conserva") { commit(.keep) }
                .accessibilityAction(named: "Aggiungi alla lista da eliminare") { commit(.delete) }
                .accessibilityAction(named: "Più tardi") { commit(.postpone) }
                .accessibilityAction(named: "Dettagli") { detailItem = item }
                .accessibilityAction(named: "Apri a tutto schermo") { previewItem = item }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isCommitting else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isCommitting else { return }
                resolveDrag(value.translation)
            }
    }

    private func resolveDrag(_ translation: CGSize) {
        let isHorizontal = abs(translation.width) > abs(translation.height)
        if isHorizontal && translation.width > 100 {
            env.recordTutorial(.swipeRight)
            commit(.keep)
        } else if isHorizontal && translation.width < -100 {
            env.recordTutorial(.swipeLeft)
            commit(.delete)
        } else if !isHorizontal && translation.height > 110 {
            env.recordTutorial(.swipeDown)
            commit(.postpone)
        } else if !isHorizontal && translation.height < -90 {
            env.recordTutorial(.swipeUp)
            resetCard()
            detailItem = sessions.currentItem
        } else {
            resetCard()
        }
    }

    private func resetCard() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            offset = .zero
        }
    }

    // MARK: - Decisioni

    /// Applica la scelta all'elemento corrente. Qui non viene eliminato nulla:
    /// "elimina" significa soltanto "aggiungi alla lista di revisione".
    private func commit(_ choice: SwipeChoice) {
        guard !isCommitting, let item = sessions.currentItem else { return }

        // Gli elementi protetti non possono essere proposti per l'eliminazione: la carta torna al suo posto.
        if choice == .delete, let reason = env.safety.blockReason(for: item) {
            resetCard()
            toast = reason.message + " Puoi sbloccarlo dai dettagli."
            return
        }

        isCommitting = true
        let target: CGSize
        switch choice {
        case .keep:
            target = CGSize(width: 700, height: 60)
        case .delete:
            target = CGSize(width: -700, height: 60)
        case .postpone:
            target = CGSize(width: 0, height: 900)
        }
        withAnimation(.easeIn(duration: reduceMotion ? 0 : 0.18)) {
            offset = target
        }

        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 190))
            // La scelta vale solo per la carta su cui è stato fatto il gesto.
            let result = sessions.decide(choice, expectedItemID: item.id)
            offset = .zero
            isCommitting = false
            guard result != nil else { return }
            if choice == .delete {
                markTrigger += 1
            } else {
                feedbackTrigger += 1
            }
            if result == .appliedWithCaution {
                toast = "Contenuto potenzialmente importante: sarà evidenziato nella revisione."
            }
        }
    }

    private func undo() {
        let undone = sessions.undo()
        guard undone > 0 else { return }
        env.recordTutorial(undone > 1 ? .undoGroup : .undo)
        feedbackTrigger += 1
        toast = undone == 1
            ? "Ultima scelta annullata."
            : "Scelta sul gruppo annullata: \(undone) elementi ripristinati."
    }

    /// Porta sulla carta un elemento del gruppo toccato nella striscia: lo si guarda e lo si decide
    /// come qualsiasi altro. Un video parte subito.
    private func select(_ memberID: UUID) {
        guard !isCommitting else { return }
        offset = .zero
        sessions.focus(on: memberID)
        env.recordTutorial(.stripSelect)
        feedbackTrigger += 1
    }

    /// Conserva le migliori del gruppo (quelle con la stella o, se non ce ne sono, quella consigliata)
    /// e propone le altre per l'eliminazione, in un solo gesto.
    /// Come ogni scelta, passa dalla revisione: nulla viene eliminato qui.
    private func keepBest(of group: ItemGroup) {
        env.recordTutorial(.keepBest)
        let members = env.store.members(of: group)
        let keepers = GroupChoice.preferredKeepers(members: members, suggestedID: group.suggestedKeepID)
        guard !keepers.isEmpty else { return }
        let usesStars = members.contains { $0.isStarred }
        let masculine = members.first?.usesMasculineWording ?? false
        let summary = usesStars
            ? (masculine ? "Tenuti i tuoi migliori" : "Tenute le tue migliori")
            : "Tenuto l'elemento consigliato"
        keepOnly(keepers, in: group, summary: summary)
    }

    /// Conserva l'elemento sulla carta e propone tutti gli altri del gruppo per l'eliminazione.
    private func keepOnly(_ item: IndexedItem, in group: ItemGroup) {
        env.recordTutorial(.keepOnlyCurrent)
        keepOnly([item.id], in: group, summary: "Tenuto quello sulla carta")
    }

    private func keepOnly(_ keepers: Set<UUID>, in group: ItemGroup, summary: String) {
        let choice = GroupChoice.keepOnly(keepers, among: group.memberIDs)
        let result = sessions.decideGroup(keep: choice.keep, delete: choice.delete)
        markTrigger += 1
        var message = "\(summary): \(Format.plural(result.applied, "altro aggiunto", "altri aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto saltato", "protetti saltati"))."
        }
        toast = message
    }

    /// Decide un singolo elemento del gruppo dal menu della striscia, senza portarlo sulla carta.
    private func decideMember(_ memberID: UUID, _ choice: SwipeChoice) {
        env.recordTutorial(.stripMenu)
        if choice == .delete {
            let result = sessions.decideGroup(keep: [], delete: [memberID])
            if result.blocked > 0 {
                toast = "Elemento protetto: non può essere proposto per l'eliminazione."
            } else {
                markTrigger += 1
            }
        } else {
            sessions.decideGroup(keep: [memberID], delete: [])
            feedbackTrigger += 1
        }
    }

    /// Mette o toglie la stella dei migliori dal menu della striscia. Con la stella l'elemento è conservato.
    private func toggleBest(_ memberID: UUID) {
        env.recordTutorial(.stripMenu)
        guard let member = env.store.item(memberID) else { return }
        if member.isStarred {
            sessions.removeBest([memberID])
            env.recordTutorial(.removeStar)
            toast = "Stella tolta."
        } else {
            sessions.markBest([memberID])
            env.recordTutorial(.starBest)
            toast = member.usesMasculineWording
                ? "Segnato come migliore: resta conservato."
                : "Segnata come migliore: resta conservata."
        }
        feedbackTrigger += 1
    }

    private func openReview() {
        sessions.closePresentation()
        env.router.selectedTab = .review
    }
}

// MARK: - Intestazione

private struct SessionHeaderView: View {
    let session: CleanupSession

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Elemento \(min(session.cursor + 1, session.queue.count)) di \(session.queue.count)")
                Spacer(minLength: 8)
                Text("Da rivedere: \(session.remainingCount)")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            ProgressView(value: session.progress)

            HStack {
                Label("Conservati: \(session.keptCount)", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.keep)
                Spacer(minLength: 8)
                Label(
                    "Da eliminare: \(session.markedCount) · \(Format.bytes(session.markedBytes))",
                    systemImage: "trash.circle"
                )
                .foregroundStyle(Theme.remove)
            }
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if let goal = session.goalBytes, let goalProgress = session.goalProgress {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.goalReached
                         ? "Obiettivo raggiunto: \(Format.bytes(session.markedBytes)) di spazio potenziale"
                         : "Obiettivo: \(Format.bytes(session.markedBytes)) di \(Format.bytes(goal))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: goalProgress)
                        .tint(Theme.keep)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Indicazioni durante il trascinamento

private struct SwipeStampOverlay: View {
    let offset: CGSize

    var body: some View {
        let isHorizontal = abs(offset.width) > abs(offset.height)
        ZStack {
            if isHorizontal && offset.width > 20 {
                stamp("CONSERVA", tint: Theme.keep, strength: offset.width / 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if isHorizontal && offset.width < -20 {
                stamp("DA ELIMINARE", tint: Theme.remove, strength: -offset.width / 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            } else if !isHorizontal && offset.height > 20 {
                stamp("PIÙ TARDI", tint: Theme.later, strength: offset.height / 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if !isHorizontal && offset.height < -20 {
                stamp("DETTAGLI", tint: Theme.info, strength: -offset.height / 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stamp(_ text: String, tint: Color, strength: CGFloat) -> some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint, lineWidth: 3)
            }
            .opacity(Double(min(max(strength, 0), 1)))
    }
}

// MARK: - Pulsanti equivalenti ai gesti

private struct SwipeActionBar: View {
    let canUndo: Bool
    let onDelete: () -> Void
    let onPostpone: () -> Void
    let onUndo: () -> Void
    let onDetails: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            actionButton("Elimina", "trash.fill", Theme.remove, isProminent: true, action: onDelete)
                .accessibilityHint("Aggiunge l'elemento alla lista di revisione. Non lo elimina.")
            actionButton("Più tardi", "clock.fill", Theme.later, isProminent: false, action: onPostpone)
            actionButton("Annulla", "arrow.uturn.backward", .gray, isProminent: false, action: onUndo)
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.4)
            actionButton("Dettagli", "info", Theme.info, isProminent: false, action: onDetails)
            actionButton("Conserva", "checkmark", Theme.keep, isProminent: true, action: onKeep)
        }
    }

    private func actionButton(
        _ title: String,
        _ systemImage: String,
        _ tint: Color,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(isProminent ? .title2.weight(.bold) : .body.weight(.semibold))
                    .foregroundStyle(isProminent ? Color.white : tint)
                    .frame(width: isProminent ? 60 : 46, height: isProminent ? 60 : 46)
                    .background(isProminent ? tint : tint.opacity(0.16), in: Circle())
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Riepilogo di fine sessione

private struct SessionSummaryView: View {
    let session: CleanupSession
    let canUndo: Bool
    let onUndo: () -> Void
    let onReviewPostponed: () -> Void
    let onOpenReview: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.keep)
                    .padding(.top, 32)
                    .accessibilityHidden(true)
                Text("Sessione completata")
                    .font(.title2.bold())
                Text("Hai esaminato \(Format.plural(session.examinedCount, "elemento", "elementi")). Nulla è stato eliminato: controlla la lista nella scheda Revisione e conferma quando vuoi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                AdaptiveStack(horizontalAlignment: .center, spacing: 10) {
                    StatTile(title: "Conservati", value: Format.count(session.keptCount), systemImage: "checkmark", tint: Theme.keep)
                    StatTile(title: "Da eliminare", value: Format.count(session.markedCount), systemImage: "trash", tint: Theme.remove)
                    StatTile(title: "Rimandati", value: Format.count(session.postponedCount), systemImage: "clock", tint: Theme.later)
                }

                if session.markedCount > 0 {
                    InfoBanner(text: "Spazio potenziale degli elementi proposti: \(Format.bytes(session.markedBytes)). Il recupero effettivo dipende dalla conferma e, per le foto, dallo svuotamento di Eliminati di recente.")
                }

                VStack(spacing: 10) {
                    if session.markedCount > 0 {
                        Button(action: onOpenReview) {
                            Text("Vai alla revisione")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if session.postponedCount > 0 {
                        Button(action: onReviewPostponed) {
                            Text("Rivedi i \(session.postponedCount) rimandati")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    if canUndo {
                        Button("Annulla l'ultima scelta", action: onUndo)
                            .font(.subheadline)
                    }
                    Button("Chiudi", action: onClose)
                        .font(.subheadline)
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, 24)
        }
    }
}
