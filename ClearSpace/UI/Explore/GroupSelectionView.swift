import SwiftUI

/// Testi delle scelte rapide su un gruppo, uguali in tutte le schermate. Le foto sono femminili
/// ("la migliore"), video e file maschili ("il migliore").
enum GroupWording {

    /// Pulsante principale: tiene le stelle dell'utente o, se non ce ne sono, quella consigliata.
    static func keepBest(starredCount: Int, masculine: Bool) -> String {
        switch starredCount {
        case 0: return masculine ? "Tieni solo il migliore" : "Tieni solo la migliore"
        case 1: return masculine ? "Tieni solo il tuo migliore" : "Tieni solo la tua migliore"
        default: return masculine ? "Tieni solo i tuoi \(starredCount) migliori" : "Tieni solo le tue \(starredCount) migliori"
        }
    }

    /// Versione breve per la striscia sotto la carta.
    static func keepBestShort(starredCount: Int, masculine: Bool) -> String {
        switch starredCount {
        case 0: return masculine ? "Tieni il migliore" : "Tieni la migliore"
        case 1: return masculine ? "Tieni il tuo migliore" : "Tieni la tua migliore"
        default: return masculine ? "Tieni i tuoi migliori" : "Tieni le tue migliori"
        }
    }

    /// "La tua migliore" sulla carta e nelle anteprime.
    static func starred(masculine: Bool) -> String {
        masculine ? "Il tuo migliore" : "La tua migliore"
    }

    static func suggested(masculine: Bool) -> String {
        masculine ? "Consigliato" : "Consigliata"
    }
}

extension IndexedItem {
    /// Nome con l'articolo, per le frasi di consiglio: "la foto", "il video"…
    var definiteNoun: String {
        switch category {
        case .photo: return "la foto"
        case .video: return "il video"
        case .audio: return "la registrazione"
        case .pdf, .office, .archive, .otherDocument, .unknown: return "il file"
        }
    }

    /// Le foto sono femminili nei testi, tutto il resto maschile.
    var usesMasculineWording: Bool { !isImage }
}

/// Galleria di un gruppo di simili o duplicati, la schermata in cui si decide il gruppo.
///
/// - All'apertura la migliore (la stella dell'utente o la consigliata) è da tenere, le altre sono
///   da eliminare. Un tocco cambia la scelta di una foto; trascinando il dito in orizzontale si
///   cambiano tante foto insieme, come nella selezione dell'app Foto.
/// - «Elimina» elimina subito le foto scartate (`AppEnvironment.deleteDirectly`): per foto e video
///   basta la conferma di iOS, per file e contenuti importanti ClearSpace chiede prima la sua; poi le
///   foto restano 30 giorni in «Eliminati di recente». Aperta dallo swipe, invece, la galleria segue
///   le regole della sessione e le foto scartate passano alla Revisione.
/// - Le scelte fatte con i tocchi non vengono salvate finché non si conferma. Dal primo tocco la
///   proposta resta ferma, anche se il consiglio cambia mentre la galleria è aperta.
/// - Fino a quattro scatti le anteprime sono su due colonne, grandi abbastanza da giudicarle.
struct GroupSelectionView: View {
    let groupID: UUID
    /// Chiude la galleria dopo una scelta che decide tutto il gruppo (usato dalla modalità swipe).
    var closesAfterDecision = false
    /// Mostra il confronto grande. È spento quando la galleria è aperta dal confronto stesso.
    var opensComparison = true
    /// La galleria fa parte della revisione gruppo per gruppo: dopo una scelta su tutto il gruppo si
    /// passa al successivo invece di restare qui.
    var sequence: GroupSequenceControl?
    /// Elimina subito le foto scartate. Spento nello swipe, dove ogni scelta passa dalla Revisione.
    var deletesDirectly = true
    /// Dopo un'eliminazione riuscita torna indietro e passa l'esito a chi ha aperto la galleria (l'elenco
    /// dei gruppi), invece di mostrare la schermata «Fatto».
    var onDeleted: ((GroupDecision) -> Void)?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    /// Scelte fatte a mano rispetto alla proposta: `true` = elimina, `false` = tieni.
    @State private var overrides: [UUID: Bool] = [:]
    /// Proposta fissata alla prima scelta a mano: se nel frattempo il consiglio cambia (l'analisi del
    /// gruppo finisce mentre la galleria è aperta), le scelte già fatte non si spostano su altre foto.
    @State private var frozenProposal: Set<UUID>?
    /// Cresce a ogni eliminazione riuscita: fa vibrare leggermente il telefono.
    @State private var deletionsDone = 0
    @State private var order: Order = .shot
    @State private var comparison: ComparisonStart?
    /// Stato degli elementi quando si è aperto il confronto: al ritorno le scelte fatte là prevalgono.
    @State private var statusesBeforeComparison: [UUID: ReviewStatus] = [:]
    @State private var preview: PreviewStart?
    @State private var toast: String?
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var outcome: GroupDecision?

    enum Order: String, CaseIterable, Identifiable {
        case shot
        case quality

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shot: return "Ordine di scatto"
            case .quality: return "Prima le migliori"
            }
        }
    }

    /// Elemento da cui aprire il confronto grande.
    struct ComparisonStart: Identifiable, Hashable {
        let itemID: UUID

        var id: UUID { itemID }
    }

    /// Foto da aprire a tutto schermo e quelle tra cui scorrere.
    struct PreviewStart: Identifiable {
        let itemID: UUID
        let itemIDs: [UUID]

        var id: UUID { itemID }
    }

    /// Scelta in corso: cosa eliminare, cosa non si può eliminare e la proposta di partenza.
    private struct Choice {
        let proposal: Set<UUID>
        let locked: Set<UUID>
        let deletion: Set<UUID>
    }

    private var group: ItemGroup? {
        env.store.group(groupID)
    }

    private var members: [IndexedItem] {
        group.map { env.store.members(of: $0) } ?? []
    }

    private var isMasculine: Bool {
        members.first?.usesMasculineWording ?? false
    }

    /// "Gruppo 3 di 12" nella revisione gruppo per gruppo, altrimenti "Scegli le migliori".
    private var title: String {
        if let sequence {
            return "Gruppo \(sequence.position) di \(sequence.total)"
        }
        return isMasculine ? "Scegli i migliori" : "Scegli le migliori"
    }

    /// Non resta nulla da decidere nel gruppo: ogni elemento è conservato, proposto o protetto.
    private var isGroupDecided: Bool {
        guard let group else { return true }
        return GroupReview.summary(
            members: members,
            suggestedID: group.suggestedKeepID,
            evaluator: env.safety.evaluator()
        ).isDecided
    }

    private func choice(group: ItemGroup, members: [IndexedItem]) -> Choice {
        let evaluator = env.safety.evaluator()
        let locked = Set(members.filter { evaluator.blockReason(for: $0) != nil }.map { $0.id })
        let proposal = frozenProposal ?? GroupProposal.initialDeletion(
            members: members,
            suggestedID: group.suggestedKeepID,
            isLocked: { locked.contains($0.id) }
        )
        let deletion = GroupProposal.deletion(proposal: proposal, overrides: overrides, locked: locked)
        return Choice(proposal: proposal, locked: locked, deletion: deletion)
    }

    /// Le scelte a mano partono da qui: da adesso la proposta non cambia più da sola.
    private func freeze(_ current: Choice) {
        if frozenProposal == nil {
            frozenProposal = current.proposal
        }
    }

    /// Torna alla proposta dell'app, ricalcolata con il consiglio attuale.
    private func resetChoices() {
        overrides.removeAll()
        frozenProposal = nil
    }

    /// «Salta» lascia il gruppo da decidere; quando è già deciso diventa «Avanti».
    private func nextButton(_ sequence: GroupSequenceControl) -> some View {
        let decided = isGroupDecided
        return Button(decided ? "Avanti" : "Salta") {
            resetChoices()
            sequence.onNext()
        }
        .fontWeight(decided ? .semibold : .regular)
        .accessibilityLabel(decided ? "Passa al gruppo successivo" : "Salta il gruppo")
        .accessibilityIdentifier("sequence.next")
    }

    var body: some View {
        let _ = env.store.revision
        Group {
            if let outcome {
                outcomeView(outcome)
            } else if let group, members.count >= 2 {
                gallery(group: group, members: members)
            } else if isDeleting {
                // Durante l'eliminazione le foto spariscono dall'indice prima che arrivi l'esito: senza
                // questo per un attimo comparirebbe «Gruppo non più disponibile».
                ProgressView("Elimino…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Gruppo non più disponibile",
                    systemImage: "square.on.square",
                    description: Text("Gli elementi sono cambiati dall'ultima analisi.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        // Schermata di lavoro fitta: con il testo molto grande intestazione e barra si fermano a una
        // dimensione che lascia vedere la griglia.
        .compactControlText()
        .navigationTitle(outcome == nil ? title : "Fatto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if outcome == nil {
                if let sequence {
                    ToolbarItem(placement: .primaryAction) {
                        nextButton(sequence)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    moreMenu
                }
            }
        }
        .navigationDestination(item: $comparison) { start in
            // Una scelta sull'intero gruppo riporta qui: si vede subito cosa resta e cosa si elimina,
            // e «Elimina» è a portata di dito.
            GroupComparisonView(
                groupID: groupID,
                initialItemID: start.itemID,
                closesAfterDecision: true,
                showsGalleryButton: false
            )
        }
        .onChange(of: comparison) { _, current in
            guard current == nil else { return }
            // Le scelte fatte nel confronto sono salvate: prevalgono su quelle fatte qui prima.
            var changed = false
            for member in members where statusesBeforeComparison[member.id] != member.reviewStatus {
                overrides.removeValue(forKey: member.id)
                changed = true
            }
            if changed {
                frozenProposal = nil
                let queued = members.contains { $0.reviewStatus.isQueuedForDeletion }
                toast = deletesDirectly && queued
                    ? "Scelta applicata: premi «Elimina» per liberare lo spazio."
                    : "Scelta applicata."
            }
        }
        .onChange(of: order) { _, newOrder in
            if newOrder == .quality {
                env.recordTutorial(.galleryOrder)
            }
        }
        .fullScreenCover(item: $preview) { start in
            ItemPreviewScreen(itemID: start.itemID, itemIDs: start.itemIDs, showsActions: false)
        }
        .sensoryFeedback(.success, trigger: deletionsDone)
        .toast($toast)
        .task(id: groupID) {
            env.recordTutorial(.openGallery)
            // Se la scansione non ha ancora confrontato questi scatti lo si fa adesso, così voti e
            // consiglio usano già tutti i criteri.
            await env.refineSuggestion(forGroup: groupID)
        }
    }

    // MARK: - Galleria

    private func gallery(group: ItemGroup, members: [IndexedItem]) -> some View {
        let ratings = QualityRanker.breakdowns(among: members)
        let positions = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($0.element.id, $0.offset + 1) })
        let current = choice(group: group, members: members)
        let shown = ordered(members, ratings: ratings)
        // Pochi scatti si giudicano meglio grandi: due colonne invece di tre.
        let isSmallGroup = members.count <= 4
        return SelectableGrid(
            items: shown,
            selection: deletionBinding(current, memberIDs: members.map { $0.id }),
            isSelecting: true,
            minimumCellSide: 105,
            columns: isSmallGroup ? 2 : nil,
            spacing: isSmallGroup ? 6 : 3,
            onOpen: { item in openPreview(item, among: shown) },
            onExpand: { item in openPreview(item, among: shown) },
            header: {
                header(group: group, members: members)
            },
            footer: {
                EmptyView()
            },
            cell: { item, deletes in
                GroupGridCell(
                    item: item,
                    position: positions[item.id] ?? 0,
                    deletes: deletes,
                    isLocked: current.locked.contains(item.id),
                    isSuggested: item.id == group.suggestedKeepID,
                    grade: item.isImage ? ratings[item.id]?.grade : nil,
                    warning: item.isImage ? ratings[item.id].flatMap { QualityRanker.mainWarning(for: item, rating: $0) } : nil,
                    pointSide: isSmallGroup ? 240 : 170,
                    onExpand: { openPreview(item, among: shown) }
                )
                .contextMenu {
                    contextActions(for: item, deletes: deletes, isLocked: current.locked.contains(item.id))
                } preview: {
                    contextPreview(for: item)
                }
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar(group: group, members: members, choice: current)
        }
        .confirmationDialog(
            deletionTitle(members: members, choice: current),
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button(deletionButtonTitle(members: members, choice: current), role: .destructive) {
                performDeletion(members: members, deletion: current.deletion)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(deletionMessage(members: members, choice: current))
        }
    }

    /// Selezione della griglia = elementi da eliminare. Toccare un elemento protetto non lo cambia.
    private func deletionBinding(_ current: Choice, memberIDs: [UUID]) -> Binding<Set<UUID>> {
        Binding(
            get: { current.deletion },
            set: { newValue in
                if !newValue.intersection(current.locked).isEmpty {
                    toast = "Gli elementi protetti non si possono eliminare."
                }
                freeze(current)
                overrides = GroupProposal.overrides(
                    for: newValue.subtracting(current.locked),
                    proposal: current.proposal,
                    memberIDs: memberIDs,
                    locked: current.locked
                )
                env.recordTutorial(.galleryToggle)
            }
        )
    }

    private func ordered(_ members: [IndexedItem], ratings: [UUID: QualityRanker.Breakdown]) -> [IndexedItem] {
        switch order {
        case .shot:
            return members
        case .quality:
            let positions = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($0.element.id, $0.offset) })
            return members.sorted { first, second in
                let firstScore: Double = (first.isStarred ? 10.0 : 0.0) + (ratings[first.id]?.score ?? 0.0)
                let secondScore: Double = (second.isStarred ? 10.0 : 0.0) + (ratings[second.id]?.score ?? 0.0)
                if firstScore != secondScore { return firstScore > secondScore }
                return (positions[first.id] ?? 0) < (positions[second.id] ?? 0)
            }
        }
    }

    private func openPreview(_ item: IndexedItem, among shown: [IndexedItem]) {
        env.recordTutorial(.preview)
        preview = PreviewStart(itemID: item.id, itemIDs: shown.map { $0.id })
    }

    // MARK: - Intestazione

    private func header(group: ItemGroup, members: [IndexedItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sequence {
                ProgressView(value: Double(sequence.position - 1), total: Double(max(sequence.total, 1)))
                    .tint(Theme.keep)
                    .accessibilityLabel("Gruppo \(sequence.position) di \(sequence.total)")
            }
            recommendation(group: group, members: members)
            // Su una riga se ci sta, altrimenti il pulsante va sotto la spiegazione.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    legend
                    Spacer(minLength: 4)
                    compareButton(group: group, members: members)
                }
                VStack(alignment: .leading, spacing: 8) {
                    legend
                    compareButton(group: group, members: members)
                }
            }
        }
        .padding(.top, 8)
    }

    /// Il consiglio in una riga: quale tenere e perché.
    @ViewBuilder
    private func recommendation(group: ItemGroup, members: [IndexedItem]) -> some View {
        if let keepID = group.suggestedKeepID,
           let index = members.firstIndex(where: { $0.id == keepID }),
           let reason = group.suggestionReason {
            Label {
                Text(QualityRanker.sentence(position: index + 1, noun: members[index].definiteNoun, reason: reason))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.keep)
            }
            .font(.subheadline.weight(.semibold))
        } else {
            Text("\(group.kind.title). \(group.certainty.explanation)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Cosa significano i due segni sulle anteprime.
    private var legend: some View {
        Text("\(Text(Image(systemName: "checkmark.circle.fill")).foregroundStyle(Theme.keep)) resta · \(Text(Image(systemName: "trash.circle.fill")).foregroundStyle(Theme.remove)) si elimina · tocca per cambiare")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Segno verde: resta. Cestino: si elimina. Tocca una foto per cambiare.")
    }

    @ViewBuilder
    private func compareButton(group: ItemGroup, members: [IndexedItem]) -> some View {
        if opensComparison {
            Button {
                statusesBeforeComparison = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.reviewStatus) })
                comparison = ComparisonStart(itemID: group.suggestedKeepID ?? members[0].id)
            } label: {
                Label("Confronta", systemImage: "rectangle.split.2x1")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Barra delle azioni

    private func actionBar(group: ItemGroup, members: [IndexedItem], choice: Choice) -> some View {
        let deleting = members.filter { choice.deletion.contains($0.id) }
        let keepCount = members.count - deleting.count
        let bytes = deleting.reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(spacing: 8) {
            // Il conteggio a sinistra, lo spazio che si libera a destra: nessuna scritta tagliata.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(deleting.count) da eliminare · \(keepCount) da tenere")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("grid.selectionCount")
                Spacer(minLength: 4)
                if bytes > 0 {
                    Text(Format.bytes(bytes))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.remove)
                        .accessibilityLabel("Liberi fino a \(Format.bytes(bytes))")
                }
            }
            // Sempre affiancati e con scritte brevi: la barra non cambia forma a ogni tocco e le scritte
            // si leggono intere anche con il testo grande.
            HStack(spacing: 8) {
                keepAllButton(members: members)
                primaryButton(deleting: deleting)
            }
            if !deletesDirectly {
                Text("Le foto scartate passano alla Revisione, come le altre scelte della pulizia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        // La barra resta compatta anche con il testo molto grande: la griglia sopra deve restare visibile.
        .compactControlText()
    }

    private func primaryButton(deleting: [IndexedItem]) -> some View {
        // Lo spazio è già scritto sopra, nel conteggio: qui basta il numero, che entra sempre.
        let verb = deletesDirectly ? "Elimina" : "Scarta"
        let title = deleting.isEmpty ? verb : "\(verb) \(deleting.count)"
        // Eliminare tutto il gruppo non lascia nessuna copia: ClearSpace lo fa notare prima di iOS.
        let emptiesGroup = !deleting.isEmpty && deleting.count == members.count
        return Button {
            if !deletesDirectly {
                proposeForReview(deletion: Set(deleting.map { $0.id }))
            } else if env.needsInAppConfirmation(deleting) || emptiesGroup {
                confirmsDeletion = true
            } else {
                // Per foto e video basta la conferma di iOS, che mostra quante ne verranno eliminate.
                performDeletion(members: members, deletion: Set(deleting.map { $0.id }))
            }
        } label: {
            Group {
                if isDeleting {
                    ProgressView()
                        .tint(.white)
                } else {
                    ButtonTitle(title, systemImage: "trash")
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.remove)
        .controlSize(.large)
        .disabled(deleting.isEmpty || isDeleting)
        .accessibilityLabel(deleting.isEmpty ? "Nessuna foto da eliminare" : title)
        .accessibilityIdentifier("group.delete")
    }

    private func keepAllButton(members: [IndexedItem]) -> some View {
        Button {
            keepAll(members)
        } label: {
            Text(isMasculine ? "Tieni tutti" : "Tieni tutte")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.keep)
        .controlSize(.large)
        .disabled(isDeleting)
        .accessibilityIdentifier("group.keepAll")
    }

    // MARK: - Conferma

    private var noun: (one: String, many: String) {
        if members.first?.isImage ?? false { return ("foto", "foto") }
        if members.first?.isVideo ?? false { return ("video", "video") }
        return ("elemento", "elementi")
    }

    private func deletionTitle(members: [IndexedItem], choice: Choice) -> String {
        let count = choice.deletion.count
        return "Eliminare \(count) \(count == 1 ? noun.one : noun.many)?"
    }

    private func deletionButtonTitle(members: [IndexedItem], choice: Choice) -> String {
        let count = choice.deletion.count
        return "Elimina \(count) \(count == 1 ? noun.one : noun.many)"
    }

    private func deletionMessage(members: [IndexedItem], choice: Choice) -> String {
        let deleting = members.filter { choice.deletion.contains($0.id) }
        let bytes = deleting.reduce(Int64(0)) { $0 + $1.bytes }
        var parts: [String] = []
        if !deleting.isEmpty && deleting.count == members.count {
            parts.append(isMasculine
                         ? "Elimini tutto il gruppo: non ne resterà nessuno."
                         : "Elimini tutto il gruppo: non ne resterà nessuna.")
        }
        if deleting.allSatisfy({ $0.source == .photoLibrary }) {
            parts.append("Liberi fino a \(Format.bytes(bytes)). Restano 30 giorni in «Eliminati di recente» dell'app Foto e con Foto di iCloud spariscono anche dagli altri dispositivi.")
        } else {
            parts.append("Liberi fino a \(Format.bytes(bytes)). I file vanno nel cestino dell'app File, se il servizio lo consente.")
        }
        let evaluator = env.safety.evaluator()
        let cautious = deleting.filter { evaluator.needsCaution($0) }.count
        if cautious > 0 {
            parts.append(cautious == 1
                         ? "Attenzione: uno potrebbe contenere qualcosa di importante."
                         : "Attenzione: \(cautious) potrebbero contenere qualcosa di importante.")
        }
        parts.append("iOS ti chiederà ancora una conferma.")
        return parts.joined(separator: " ")
    }

    // MARK: - Menu

    private var moreMenu: some View {
        let current = members
        let hasStars = current.contains { $0.isStarred }
        return Menu {
            if deletesDirectly {
                Button {
                    addToReview()
                } label: {
                    Label("Aggiungi alla Revisione", systemImage: "tray.and.arrow.down")
                }
            }
            Section {
                Button {
                    env.recordTutorial(.quickSelect)
                    markAll(current)
                } label: {
                    Label(isMasculine ? "Segna tutti da eliminare" : "Segna tutte da eliminare", systemImage: "trash")
                }
                Button {
                    env.recordTutorial(.quickSelect)
                    resetChoices()
                } label: {
                    Label("Ripristina la proposta", systemImage: "arrow.counterclockwise")
                }
            }
            Picker("Ordine", selection: $order) {
                ForEach(Order.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            if hasStars {
                Button {
                    removeStars(current.filter { $0.isStarred })
                } label: {
                    Label("Togli tutte le stelle", systemImage: "star.slash")
                }
            }
        } label: {
            Label("Altre azioni", systemImage: "ellipsis.circle")
        }
        .disabled(current.count < 2 || isDeleting)
    }

    @ViewBuilder
    private func contextActions(for item: IndexedItem, deletes: Bool, isLocked: Bool) -> some View {
        Button {
            env.recordTutorial(.galleryMenu)
            openPreview(item, among: members)
        } label: {
            Label(item.isVideo ? "Guarda" : "Vedi a tutto schermo", systemImage: item.isVideo ? "play" : "arrow.up.left.and.arrow.down.right")
        }
        if opensComparison {
            Button {
                env.recordTutorial(.galleryMenu)
                statusesBeforeComparison = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.reviewStatus) })
                comparison = ComparisonStart(itemID: item.id)
            } label: {
                Label("Confronta da qui", systemImage: "rectangle.split.2x1")
            }
        }
        if item.isStarred {
            Button {
                removeStars([item])
            } label: {
                Label("Togli la stella", systemImage: "star.slash")
            }
        } else {
            Button {
                markBest([item])
            } label: {
                Label("Segna come migliore", systemImage: "star")
            }
        }
        if !isLocked {
            if deletes {
                Button {
                    env.recordTutorial(.galleryMenu)
                    setDeletion(false, for: item)
                } label: {
                    Label("Tieni", systemImage: "checkmark")
                }
            } else {
                Button(role: .destructive) {
                    env.recordTutorial(.galleryMenu)
                    setDeletion(true, for: item)
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
        }
    }

    /// Anteprima grande mostrata tenendo premuto, come nell'app Foto. Per le foto prova a caricare
    /// la versione nitida: è proprio il momento in cui si vuole giudicarla.
    private func contextPreview(for item: IndexedItem) -> some View {
        let size = previewSize(for: item)
        return Group {
            if item.isImage {
                ItemImageView(item: item, pixelSide: 1_600, showsStatus: false, inspecting: true)
            } else {
                ItemThumbnailView(item: item, pointSide: 360, fill: false, allowsNetwork: true)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .environment(env)
    }

    private func previewSize(for item: IndexedItem) -> CGSize {
        let width: CGFloat = 320
        guard item.pixelWidth > 0, item.pixelHeight > 0 else { return CGSize(width: width, height: width) }
        let ratio = CGFloat(item.pixelHeight) / CGFloat(item.pixelWidth)
        return CGSize(width: width, height: min(max(width * ratio, 180), 460))
    }

    // MARK: - Esito

    /// Dopo un'eliminazione fuori dalla revisione gruppo per gruppo: cosa è successo e come liberare
    /// davvero lo spazio.
    private func outcomeView(_ decision: GroupDecision) -> some View {
        ReadableList {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.keep)
                        .accessibilityHidden(true)
                    Text(decision.message)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            if decision.deletedCount > 0 {
                RecentlyDeletedSection(count: decision.deletedCount, deviceBytes: decision.freedBytes)
            }
            Section {
                Button {
                    dismiss()
                } label: {
                    Text("Torna ai gruppi")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("group.done")
            }
        }
    }

    // MARK: - Azioni

    private func setDeletion(_ deletes: Bool, for item: IndexedItem) {
        guard let group else { return }
        let current = choice(group: group, members: members)
        freeze(current)
        var next = current.deletion
        if deletes {
            next.insert(item.id)
        } else {
            next.remove(item.id)
        }
        overrides = GroupProposal.overrides(
            for: next,
            proposal: current.proposal,
            memberIDs: members.map { $0.id },
            locked: current.locked
        )
    }

    private func markAll(_ items: [IndexedItem]) {
        guard let group else { return }
        let current = choice(group: group, members: items)
        freeze(current)
        overrides = GroupProposal.overrides(
            for: Set(items.map { $0.id }),
            proposal: current.proposal,
            memberIDs: items.map { $0.id },
            locked: current.locked
        )
    }

    private func markBest(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        env.sessions.markBest(items.map { $0.id })
        env.recordTutorial(.starBest)
        for item in items {
            overrides.removeValue(forKey: item.id)
        }
        toast = isMasculine ? "Segnato come migliore: resta conservato." : "Segnata come migliore: resta conservata."
    }

    private func removeStars(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        env.sessions.removeBest(items.map { $0.id })
        env.recordTutorial(.removeStar)
        toast = items.count == 1 ? "Stella tolta." : "Stelle tolte."
    }

    private func keepAll(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        env.sessions.decideGroup(keep: items.map { $0.id }, delete: [])
        resetChoices()
        finish(GroupDecision(message: "Tutti gli elementi del gruppo sono stati conservati."))
    }

    /// Salva la scelta senza eliminare: le foto scartate passano alla Revisione.
    private func addToReview() {
        guard let group else { return }
        let current = choice(group: group, members: members)
        guard !current.deletion.isEmpty else {
            toast = "Tocca prima le foto da eliminare."
            return
        }
        proposeForReview(deletion: current.deletion)
    }

    private func proposeForReview(deletion: Set<UUID>) {
        let split = GroupProposal.split(memberIDs: members.map { $0.id }, deletion: deletion)
        let result = env.sessions.decideGroup(keep: split.keep, delete: split.delete)
        resetChoices()
        var message = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto saltato", "protetti saltati"))."
        }
        finish(GroupDecision(message: message))
    }

    /// Tiene le foto con il segno verde ed elimina subito le altre. Se si annulla la conferma di iOS
    /// tutto torna com'era.
    private func performDeletion(members: [IndexedItem], deletion: Set<UUID>) {
        let split = GroupProposal.split(memberIDs: members.map { $0.id }, deletion: deletion)
        guard !split.delete.isEmpty, !isDeleting else { return }
        isDeleting = true
        let isImageGroup = members.first?.isImage ?? false
        let isVideoGroup = members.first?.isVideo ?? false
        Task {
            let result = await env.deleteDirectly(keep: split.keep, delete: split.delete)
            isDeleting = false
            switch result.outcome {
            case .cancelled:
                toast = "Eliminazione annullata: non è stato eliminato nulla."
            case .nothing:
                toast = result.note ?? "Non è stato eliminato nulla."
            case .deleted:
                deletionsDone += 1
                resetChoices()
                finish(GroupDecision(
                    message: result.summary(isImage: isImageGroup, isVideo: isVideoGroup),
                    deletedCount: result.deletedCount,
                    freedBytes: result.freedBytes
                ))
            }
        }
    }

    private func finish(_ decision: GroupDecision) {
        if let sequence {
            // Revisione gruppo per gruppo: il messaggio lo mostra la sequenza, che passa al successivo.
            sequence.onDecided(decision)
        } else if closesAfterDecision {
            dismiss()
        } else if decision.deletedCount > 0, let onDeleted {
            // Si torna all'elenco, che mostra l'esito e come liberare davvero lo spazio.
            onDeleted(decision)
            dismiss()
        } else if decision.deletedCount > 0 {
            outcome = decision
        } else {
            toast = decision.message
        }
    }
}

/// Cella della galleria: anteprima, scelta (resta o si elimina), stella o consiglio, voto e
/// pulsante per vederla a tutto schermo.
private struct GroupGridCell: View {
    let item: IndexedItem
    let position: Int
    let deletes: Bool
    let isLocked: Bool
    let isSuggested: Bool
    let grade: Int?
    /// Difetto evidente da segnalare al posto del voto, ad esempio «Occhi chiusi».
    let warning: String?
    /// Lato dell'anteprima da preparare: più grande quando le colonne sono due.
    let pointSide: CGFloat
    let onExpand: () -> Void

    var body: some View {
        ItemThumbnailView(item: item, pointSide: pointSide)
            .overlay {
                // Ciò che verrà eliminato appare spento.
                if deletes {
                    Color.black.opacity(0.45)
                }
            }
            .overlay(alignment: .topLeading) {
                bestBadge
                    .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                // A destra resta il posto per il segno della scelta.
                cornerNote
                    .padding(5)
                    .padding(.trailing, 30)
            }
            .overlay(alignment: .bottomTrailing) {
                choiceBadge
                    .padding(5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(deletes ? Theme.remove : Color.clear, lineWidth: 3)
            }
            .thumbnailBadgeText()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenDescription)
            .accessibilityAddTraits(deletes ? [.isSelected] : [])
    }

    /// Un solo segno dice cosa succede alla foto: verde resta, cestino si elimina, lucchetto protetta.
    @ViewBuilder
    private var choiceBadge: some View {
        if isLocked {
            badge("lock.fill", tint: .gray)
        } else if deletes {
            badge("trash.fill", tint: Theme.remove)
        } else {
            badge("checkmark", tint: Theme.keep)
        }
    }

    @ViewBuilder
    private var bestBadge: some View {
        if item.isStarred {
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.best)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.6), in: Circle())
        } else if isSuggested {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.keep.opacity(0.85), in: Circle())
        }
    }

    @ViewBuilder
    private var cornerNote: some View {
        if item.isVideo && item.duration > 0 {
            Label(Format.duration(item.duration), systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6), in: Capsule())
        } else if let warning {
            // Scritta intera se ci sta, altrimenti solo il segno di avviso (la scritta resta per VoiceOver).
            ViewThatFits(in: .horizontal) {
                note(Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(warning)"), tint: Theme.later)
                note(Text(Image(systemName: "exclamationmark.triangle.fill")), tint: Theme.later)
            }
        } else if let grade {
            note(Text("Voto \(grade)"), tint: .black.opacity(0.6))
        }
    }

    private func note(_ text: Text, tint: Color) -> some View {
        text
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
    }

    private func badge(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
            }
    }

    /// "Foto 2, da eliminare, la tua migliore, consigliata, voto 62 su 100".
    private var spokenDescription: String {
        let masculine = item.usesMasculineWording
        var parts = ["\(item.isVideo ? "Video" : item.isImage ? "Foto" : "Elemento") \(position)"]
        if isLocked {
            parts.append(masculine ? "protetto" : "protetta")
        } else {
            parts.append(deletes ? "da eliminare" : "da tenere")
        }
        if item.isStarred { parts.append(GroupWording.starred(masculine: masculine).lowercased()) }
        if isSuggested { parts.append(GroupWording.suggested(masculine: masculine).lowercased()) }
        if let warning { parts.append(warning.lowercased()) }
        if let grade { parts.append("voto \(grade) su 100") }
        if item.duration > 0 { parts.append(Format.duration(item.duration)) }
        return parts.joined(separator: ", ")
    }
}
