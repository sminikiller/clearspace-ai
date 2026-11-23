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

/// Galleria di un gruppo di simili o duplicati: tutte le anteprime in griglia, con selezione multipla
/// a tocchi o trascinando il dito come nell'app Foto. Le migliori si segnano con una stella: restano
/// conservate e si riconoscono ovunque nell'app. Ogni scelta passa dalla revisione: da qui non si
/// elimina nulla.
struct GroupSelectionView: View {
    let groupID: UUID
    /// Chiude la galleria dopo una scelta che decide tutto il gruppo (usato dalla modalità swipe).
    var closesAfterDecision = false
    /// Mostra il confronto grande. È spento quando la galleria è aperta dal confronto stesso.
    var opensComparison = true
    /// La galleria fa parte della revisione gruppo per gruppo: dopo una scelta su tutto il gruppo si
    /// passa al successivo invece di restare qui.
    var sequence: GroupSequenceControl?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()
    @State private var order: Order = .shot
    @State private var comparison: ComparisonStart?
    @State private var previewItem: IndexedItem?
    @State private var toast: String?

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

    /// «Salta» lascia il gruppo da decidere; quando è già deciso diventa «Avanti».
    private func nextButton(_ sequence: GroupSequenceControl) -> some View {
        let decided = isGroupDecided
        return Button(decided ? "Avanti" : "Salta") {
            selection.removeAll()
            sequence.onNext()
        }
        .fontWeight(decided ? .semibold : .regular)
        .accessibilityLabel(decided ? "Passa al gruppo successivo" : "Salta il gruppo")
        .accessibilityIdentifier("sequence.next")
    }

    var body: some View {
        let _ = env.store.revision
        Group {
            if let group, members.count >= 2 {
                gallery(group: group, members: members)
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let sequence {
                ToolbarItem(placement: .primaryAction) {
                    nextButton(sequence)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }
        }
        .navigationDestination(item: $comparison) { start in
            GroupComparisonView(groupID: groupID, initialItemID: start.itemID, showsGalleryButton: false)
        }
        .fullScreenCover(item: $previewItem) { item in
            ItemPreviewScreen(itemID: item.id, showsActions: false)
        }
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
        return SelectableGrid(
            items: ordered(members, ratings: ratings),
            selection: $selection,
            isSelecting: true,
            minimumCellSide: 105,
            onOpen: { item in previewItem = item },
            header: {
                header(group: group, members: members)
            },
            footer: {
                EmptyView()
            },
            cell: { item, isSelected in
                GroupGridCell(
                    item: item,
                    position: positions[item.id] ?? 0,
                    isSelected: isSelected,
                    isSuggested: item.id == group.suggestedKeepID,
                    grade: item.isImage ? ratings[item.id]?.grade : nil
                )
                .contextMenu {
                    contextActions(for: item)
                } preview: {
                    contextPreview(for: item)
                }
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar(group: group, members: members)
        }
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

    // MARK: - Intestazione

    private func header(group: ItemGroup, members: [IndexedItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sequence {
                sequenceProgress(sequence)
            }
            recommendation(group: group, members: members)
            Text(isMasculine
                 ? "Tocca o trascina il dito sulle anteprime per selezionarne tanti insieme. Tieni premuto per vederne uno in grande."
                 : "Tocca o trascina il dito sulle anteprime per selezionarne tante insieme. Tieni premuto per vederne una in grande.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Ordine", selection: $order) {
                ForEach(Order.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .adaptiveSegmentedStyle()
            .onChange(of: order) { _, newOrder in
                if newOrder == .quality {
                    env.recordTutorial(.galleryOrder)
                }
            }
            quickSelection(group: group, members: members)
        }
        .padding(.top, 8)
    }

    /// Avanzamento della revisione gruppo per gruppo e cosa succede dopo una scelta.
    private func sequenceProgress(_ sequence: GroupSequenceControl) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: Double(sequence.position - 1), total: Double(max(sequence.total, 1)))
                .tint(Theme.keep)
                .accessibilityLabel("Gruppo \(sequence.position) di \(sequence.total)")
            Text(isMasculine
                 ? "Dopo «Tieni solo il migliore» o «Tieni tutti» compare da solo il gruppo successivo. «Salta» lo lascia da decidere."
                 : "Dopo «Tieni solo la migliore» o «Tieni tutte» compare da solo il gruppo successivo. «Salta» lo lascia da decidere.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recommendation(group: ItemGroup, members: [IndexedItem]) -> some View {
        let starredCount = members.filter { $0.isStarred }.count
        return VStack(alignment: .leading, spacing: 6) {
            if starredCount > 0 {
                Label {
                    Text(starredCount == 1
                         ? "Hai scelto \(isMasculine ? "il tuo migliore" : "la tua migliore")"
                         : "Hai scelto \(starredCount) migliori")
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Theme.best)
                }
                .font(.subheadline.weight(.semibold))
            }
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
            }
            Text("\(group.kind.title). \(group.certainty.explanation)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func quickSelection(group: ItemGroup, members: [IndexedItem]) -> some View {
        let keepers = GroupChoice.preferredKeepers(members: members, suggestedID: group.suggestedKeepID)
        let hasStars = members.contains { $0.isStarred }
        let all = Set(members.map { $0.id })
        // Su più righe se serve: nessun pulsante resta tagliato sul bordo.
        return FlowLayout(spacing: 8, lineSpacing: 8) {
            quickButton(isMasculine ? "Seleziona tutti" : "Seleziona tutte") {
                selection = all
            }
            if !keepers.isEmpty && keepers.count < members.count {
                quickButton(hasStars
                            ? (isMasculine ? "Tutti tranne i tuoi migliori" : "Tutte tranne le tue migliori")
                            : (isMasculine ? "Tutti tranne il consigliato" : "Tutte tranne la consigliata")) {
                    selection = all.subtracting(keepers)
                }
            }
            if !selection.isEmpty {
                quickButton("Deseleziona") {
                    selection.removeAll()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            env.recordTutorial(.quickSelect)
            action()
        }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    // MARK: - Barra delle azioni

    private func actionBar(group: ItemGroup, members: [IndexedItem]) -> some View {
        let selected = members.filter { selection.contains($0.id) }
        let removesStars = !selected.isEmpty && selected.allSatisfy { $0.isStarred }
        let keepers = GroupChoice.preferredKeepers(members: members, suggestedID: group.suggestedKeepID)
        let starredCount = members.filter { $0.isStarred }.count
        return VStack(spacing: 8) {
            HStack {
                Text(selectionSummary(selected.count))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("grid.selectionCount")
                Spacer(minLength: 8)
                if opensComparison {
                    Button {
                        let start = selected.first?.id ?? group.suggestedKeepID ?? members[0].id
                        comparison = ComparisonStart(itemID: start)
                    } label: {
                        Label("Confronta", systemImage: "rectangle.split.2x1")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: 8) {
                BarActionButton(
                    title: removesStars ? "Togli stella" : "Migliore",
                    systemImage: removesStars ? "star.slash" : "star.fill",
                    tint: Theme.best,
                    accessibilityTitle: removesStars ? "Togli la stella" : "Segna come migliori"
                ) {
                    if removesStars {
                        removeStars(selected)
                    } else {
                        markBest(selected)
                    }
                }
                BarActionButton(title: "Tieni", systemImage: "checkmark", tint: Theme.keep, accessibilityTitle: "Conserva le selezionate") {
                    keep(selected)
                }
                BarActionButton(
                    title: "Elimina",
                    systemImage: "trash",
                    tint: Theme.remove,
                    accessibilityTitle: "Proponi le selezionate per l'eliminazione"
                ) {
                    propose(selected)
                }
            }
            .disabled(selected.isEmpty)
            if !keepers.isEmpty && keepers.count < members.count {
                Button {
                    keepOnly(keepers, in: group)
                } label: {
                    Label(
                        GroupWording.keepBest(starredCount: starredCount, masculine: isMasculine),
                        systemImage: starredCount > 0 ? "star.fill" : "sparkles"
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.keep)
                .controlSize(.large)
                .accessibilityHint("Conserva le migliori e aggiunge le altre alla lista di revisione. Non elimina nulla.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        // La barra resta compatta anche con il testo molto grande: la griglia sopra deve restare visibile.
        .compactControlText()
    }

    private func selectionSummary(_ count: Int) -> String {
        switch count {
        case 0: return "Nessuna selezione"
        case 1: return isMasculine ? "1 selezionato" : "1 selezionata"
        default: return "\(count) \(isMasculine ? "selezionati" : "selezionate")"
        }
    }

    // MARK: - Menu

    private var moreMenu: some View {
        let current = members
        let hasStars = current.contains { $0.isStarred }
        return Menu {
            Button {
                keepAll(current)
            } label: {
                Label(isMasculine ? "Tieni tutti" : "Tieni tutte", systemImage: "checkmark.circle")
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
        .disabled(current.count < 2)
    }

    @ViewBuilder
    private func contextActions(for item: IndexedItem) -> some View {
        Button {
            env.recordTutorial(.galleryMenu)
            previewItem = item
        } label: {
            Label(item.isVideo ? "Guarda" : "Vedi a tutto schermo", systemImage: item.isVideo ? "play" : "arrow.up.left.and.arrow.down.right")
        }
        if opensComparison {
            Button {
                env.recordTutorial(.galleryMenu)
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
        Button {
            keep([item])
        } label: {
            Label("Conserva", systemImage: "checkmark")
        }
        Button(role: .destructive) {
            propose([item])
        } label: {
            Label("Proponi per l'eliminazione", systemImage: "trash")
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

    // MARK: - Azioni (nessuna elimina: cambiano solo lo stato di revisione)

    private func markBest(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        let count = env.sessions.markBest(items.map { $0.id })
        env.recordTutorial(.starBest)
        selection.removeAll()
        if count == 1 {
            toast = isMasculine ? "Segnato come migliore: resta conservato." : "Segnata come migliore: resta conservata."
        } else {
            toast = isMasculine
                ? "\(count) segnati come migliori: restano conservati."
                : "\(count) segnate come migliori: restano conservate."
        }
    }

    private func removeStars(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        env.sessions.removeBest(items.map { $0.id })
        env.recordTutorial(.removeStar)
        selection.removeAll()
        toast = items.count == 1 ? "Stella tolta." : "Stelle tolte."
    }

    private func keep(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        env.sessions.decideGroup(keep: items.map { $0.id }, delete: [])
        selection.removeAll()
        toast = "\(Format.plural(items.count, "elemento conservato", "elementi conservati"))."
    }

    private func propose(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        let result = env.sessions.decideGroup(keep: [], delete: items.map { $0.id })
        selection.removeAll()
        toast = proposalMessage(result)
    }

    private func keepOnly(_ keepers: Set<UUID>, in group: ItemGroup) {
        let choice = GroupChoice.keepOnly(keepers, among: group.memberIDs)
        let result = env.sessions.decideGroup(keep: choice.keep, delete: choice.delete)
        env.recordTutorial(.keepBest)
        selection.removeAll()
        finish(proposalMessage(result))
    }

    private func keepAll(_ items: [IndexedItem]) {
        guard !items.isEmpty else { return }
        env.sessions.decideGroup(keep: items.map { $0.id }, delete: [])
        selection.removeAll()
        finish("Tutti gli elementi del gruppo sono stati conservati.")
    }

    private func proposalMessage(_ result: (applied: Int, blocked: Int)) -> String {
        var message = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto saltato", "protetti saltati"))."
        }
        return message
    }

    private func finish(_ message: String) {
        if let sequence {
            // Revisione gruppo per gruppo: il messaggio lo mostra la sequenza, che passa al successivo.
            sequence.onDecided(message)
        } else if closesAfterDecision {
            dismiss()
        } else {
            toast = message
        }
    }
}

/// Cella della galleria: anteprima, stato della decisione, stella o consiglio, voto e selezione.
private struct GroupGridCell: View {
    let item: IndexedItem
    let position: Int
    let isSelected: Bool
    let isSuggested: Bool
    let grade: Int?

    var body: some View {
        ItemThumbnailView(item: item, pointSide: 170)
            .overlay {
                // Ciò che è già proposto per l'eliminazione appare spento.
                if item.reviewStatus.isQueuedForDeletion {
                    Color.black.opacity(0.4)
                }
            }
            .overlay(alignment: .topLeading) {
                statusBadge
                    .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                bestBadge
                    .padding(5)
            }
            .overlay(alignment: .bottomLeading) {
                cornerNote
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.3))
                    .shadow(color: .black.opacity(0.35), radius: 1)
                    .padding(5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenDescription)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.reviewStatus {
        case .kept:
            badge("checkmark", tint: Theme.keep)
        case .markedForDeletion, .deletionFailed:
            badge("trash.fill", tint: Theme.remove)
        case .postponed:
            badge("clock.fill", tint: Theme.later)
        case .unreviewed:
            EmptyView()
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
            badge("sparkles", tint: Theme.keep)
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
        } else if let grade {
            Text("\(grade)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6), in: Capsule())
        }
    }

    private func badge(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint, in: Circle())
    }

    /// "Foto 2, la tua migliore, consigliata, voto 62 su 100, Conservato".
    private var spokenDescription: String {
        let masculine = item.usesMasculineWording
        var parts = ["\(item.isVideo ? "Video" : item.isImage ? "Foto" : "Elemento") \(position)"]
        if item.isStarred { parts.append(GroupWording.starred(masculine: masculine).lowercased()) }
        if isSuggested { parts.append(GroupWording.suggested(masculine: masculine).lowercased()) }
        if let grade { parts.append("voto \(grade) su 100") }
        if item.duration > 0 { parts.append(Format.duration(item.duration)) }
        if item.reviewStatus != .unreviewed { parts.append(item.reviewStatus.title) }
        return parts.joined(separator: ", ")
    }
}
