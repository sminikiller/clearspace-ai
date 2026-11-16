import SwiftUI

/// Ingrandimento e posizione condivisi da tutte le foto di un confronto: passando da uno scatto
/// all'altro lo zoom resta sullo stesso punto, così le differenze si notano subito.
struct CompareViewport: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    /// Valori al termine dell'ultimo gesto: da qui parte il successivo.
    var anchorScale: CGFloat = 1
    var anchorOffset: CGSize = .zero

    var isZoomed: Bool { scale > 1.01 }
}

/// Confronto degli scatti di un gruppo di simili o duplicati.
///
/// In alto la foto selezionata, grande e ingrandibile; sotto, tutte le foto del gruppo con il voto
/// di ciascuna. Lo scatto consigliato è indicato insieme ai motivi (nitidezza, volti, occhi aperti,
/// esposizione, risoluzione), ma la scelta resta all'utente: si può tenere la migliore, quella
/// selezionata oppure tutte. Ogni scelta passa dalla revisione: da qui non si elimina nulla.
struct GroupComparisonView: View {
    let groupID: UUID
    /// Foto da mostrare all'apertura; senza indicazione si parte da quella consigliata.
    var initialItemID: UUID?
    /// Chiude il confronto dopo una scelta sull'intero gruppo (usato dalla modalità swipe).
    var closesAfterDecision = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var viewport = CompareViewport()
    @State private var isRefining = false
    @State private var toast: String?

    var body: some View {
        let _ = env.store.revision
        Group {
            if let group = env.store.group(groupID) {
                let members = env.store.members(of: group)
                if members.count >= 2 {
                    comparison(group: group, members: members)
                } else {
                    unavailable
                }
            } else {
                unavailable
            }
        }
        .background(Theme.background)
        .navigationTitle("Confronto")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .task(id: groupID) {
            if selectedID == nil {
                selectedID = initialItemID
            }
            // Se la scansione non ha ancora confrontato questi scatti, lo si fa adesso.
            isRefining = true
            await env.refineSuggestion(forGroup: groupID)
            isRefining = false
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Gruppo non più disponibile",
            systemImage: "square.on.square",
            description: Text("Gli elementi sono cambiati dall'ultima analisi.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Struttura

    private func comparison(group: ItemGroup, members: [IndexedItem]) -> some View {
        let ratings = QualityRanker.breakdowns(among: members)
        let selected = currentSelection(group: group, members: members)
        let position = (members.firstIndex(where: { $0.id == selected.id }) ?? 0) + 1
        return VStack(spacing: 0) {
            viewer(selected: selected, position: position, group: group, members: members)
            VStack(alignment: .leading, spacing: 10) {
                memberStrip(group: group, members: members, selected: selected, ratings: ratings)
                verdict(group: group, members: members)
                qualityChips(for: selected, rating: ratings[selected.id])
                decisionRow(for: selected)
                actions(group: group, members: members, selected: selected)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func currentSelection(group: ItemGroup, members: [IndexedItem]) -> IndexedItem {
        if let selectedID, let match = members.first(where: { $0.id == selectedID }) {
            return match
        }
        if let keepID = group.suggestedKeepID, let match = members.first(where: { $0.id == keepID }) {
            return match
        }
        return members[0]
    }

    private func step(_ offset: Int, from selected: IndexedItem, in members: [IndexedItem]) {
        guard let index = members.firstIndex(where: { $0.id == selected.id }) else { return }
        let next = min(max(index + offset, 0), members.count - 1)
        selectedID = members[next].id
    }

    // MARK: - Foto grande

    private func viewer(
        selected: IndexedItem,
        position: Int,
        group: ItemGroup,
        members: [IndexedItem]
    ) -> some View {
        CompareViewer(item: selected, viewport: $viewport) { offset in
            step(offset, from: selected, in: members)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                viewerTag("\(position) di \(members.count)", systemImage: nil, tint: .black.opacity(0.6))
                if selected.id == group.suggestedKeepID {
                    viewerTag("Consigliata", systemImage: "star.fill", tint: Theme.keep)
                }
            }
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if viewport.isZoomed {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewport = CompareViewport()
                    }
                } label: {
                    viewerTag("Riduci", systemImage: "arrow.down.right.and.arrow.up.left", tint: .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    private func viewerTag(_ text: String, systemImage: String?, tint: Color) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint, in: Capsule())
    }

    // MARK: - Tutte le foto del gruppo

    private func memberStrip(
        group: ItemGroup,
        members: [IndexedItem],
        selected: IndexedItem,
        ratings: [UUID: QualityRanker.Breakdown]
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        Button {
                            selectedID = member.id
                        } label: {
                            stripThumbnail(
                                member,
                                isSelected: member.id == selected.id,
                                isSuggested: member.id == group.suggestedKeepID,
                                grade: ratings[member.id]?.grade
                            )
                        }
                        .buttonStyle(.plain)
                        .id(member.id)
                        .accessibilityLabel(stripDescription(member, position: index + 1, group: group, ratings: ratings))
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 2)
            }
            .onChange(of: selected.id) { _, newID in
                withAnimation {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func stripThumbnail(_ member: IndexedItem, isSelected: Bool, isSuggested: Bool, grade: Int?) -> some View {
        ItemThumbnailView(item: member, pointSide: 80)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isSuggested {
                    stripBadge("star.fill", tint: Theme.keep)
                }
            }
            .overlay(alignment: .topLeading) {
                switch member.reviewStatus {
                case .kept:
                    stripBadge("checkmark", tint: Theme.keep)
                case .markedForDeletion, .deletionFailed:
                    stripBadge("trash.fill", tint: Theme.remove)
                case .postponed:
                    stripBadge("clock.fill", tint: Theme.later)
                case .unreviewed:
                    EmptyView()
                }
            }
            .overlay(alignment: .bottom) {
                if let grade, member.isImage {
                    Text("\(grade)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(3)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }
    }

    private func stripBadge(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(tint, in: Circle())
            .padding(3)
    }

    private func stripDescription(
        _ member: IndexedItem,
        position: Int,
        group: ItemGroup,
        ratings: [UUID: QualityRanker.Breakdown]
    ) -> String {
        var parts = ["Foto \(position)"]
        if member.id == group.suggestedKeepID { parts.append("consigliata") }
        if let rating = ratings[member.id], member.isImage { parts.append("voto \(rating.grade) su 100") }
        if member.reviewStatus != .unreviewed { parts.append(member.reviewStatus.title) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Giudizio

    private func verdict(group: ItemGroup, members: [IndexedItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let keepID = group.suggestedKeepID,
               let index = members.firstIndex(where: { $0.id == keepID }),
               let reason = group.suggestionReason {
                Text(QualityRanker.sentence(position: index + 1, noun: noun(for: members[index]), reason: reason))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(isRefining
                 ? "Sto confrontando nitidezza, volti ed esposizione…"
                 : "\(group.kind.title). \(group.certainty.explanation)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func qualityChips(for item: IndexedItem, rating: QualityRanker.Breakdown?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let rating, item.isImage {
                    TagChip(text: "Voto \(rating.grade)/100", systemImage: "chart.bar.fill", tint: Theme.info)
                    ForEach(Array(QualityRanker.highlights(for: item, rating: rating).enumerated()), id: \.offset) { _, highlight in
                        TagChip(text: highlight.text, tint: tint(for: highlight.kind))
                    }
                }
                if item.pixelCount > 0 {
                    TagChip(text: "\(Format.decimal(Double(item.pixelCount) / 1_000_000, maximumFractionDigits: 1)) MP")
                }
                if item.duration > 0 {
                    TagChip(text: Format.duration(item.duration))
                }
                TagChip(text: Format.bytesOrUnknown(item.estimatedBytes))
                TagChip(text: Format.date(item.createdAt))
            }
        }
    }

    private func tint(for kind: QualityRanker.Highlight.Kind) -> Color {
        switch kind {
        case .good: return Theme.keep
        case .neutral: return .secondary
        case .warning: return Theme.later
        }
    }

    // MARK: - Scelte

    @ViewBuilder
    private func decisionRow(for member: IndexedItem) -> some View {
        if let reason = env.safety.blockReason(for: member) {
            Label("Protetta: \(reason.message)", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Decisione per questa foto", selection: decisionBinding(for: member)) {
                Text("Tieni questa").tag(false)
                Text("Elimina questa").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private func actions(group: ItemGroup, members: [IndexedItem], selected: IndexedItem) -> some View {
        VStack(spacing: 8) {
            if let keepID = group.suggestedKeepID {
                Button {
                    keepOnly(keepID, in: group)
                } label: {
                    Text("Tieni solo la migliore")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.keep)
            }
            HStack(spacing: 8) {
                if selected.id != group.suggestedKeepID {
                    Button {
                        keepOnly(selected.id, in: group)
                    } label: {
                        Text("Tieni solo questa")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    keepAll(members)
                } label: {
                    Text("Tieni tutte")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    /// `true` = proposta per l'eliminazione, `false` = conservata.
    private func decisionBinding(for member: IndexedItem) -> Binding<Bool> {
        Binding(
            get: { env.store.item(member.id)?.reviewStatus.isQueuedForDeletion ?? false },
            set: { shouldDelete in
                if shouldDelete {
                    env.sessions.decideGroup(keep: [], delete: [member.id])
                } else {
                    env.sessions.decideGroup(keep: [member.id], delete: [])
                }
            }
        )
    }

    private func keepOnly(_ keepID: UUID, in group: ItemGroup) {
        let others = group.memberIDs.filter { $0 != keepID }
        let result = env.sessions.decideGroup(keep: [keepID], delete: others)
        var message = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto saltato", "protetti saltati"))."
        }
        finish(message)
    }

    private func keepAll(_ members: [IndexedItem]) {
        env.sessions.decideGroup(keep: members.map { $0.id }, delete: [])
        finish("Tutti gli elementi del gruppo sono stati conservati.")
    }

    private func finish(_ message: String) {
        if closesAfterDecision {
            dismiss()
        } else {
            toast = message
        }
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

/// Foto grande del confronto. Pizzico e doppio tocco ingrandiscono; con lo zoom attivo il
/// trascinamento sposta l'immagine, senza zoom lo scorrimento orizzontale passa allo scatto vicino.
struct CompareViewer: View {
    let item: IndexedItem
    @Binding var viewport: CompareViewport
    /// Richiesta di passare allo scatto successivo (+1) o precedente (−1).
    var onStep: (Int) -> Void

    init(item: IndexedItem, viewport: Binding<CompareViewport>, onStep: @escaping (Int) -> Void = { _ in }) {
        self.item = item
        self._viewport = viewport
        self.onStep = onStep
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if item.isImage {
                    ItemImageView(item: item, pixelSide: 3_000, zoom: viewport.scale, pan: viewport.offset)
                } else {
                    ItemThumbnailView(item: item, pointSide: 430, fill: false, allowsNetwork: true)
                        .scaleEffect(viewport.scale)
                        .offset(viewport.offset)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .contentShape(Rectangle())
            .gesture(magnifyGesture(in: geometry.size))
            .simultaneousGesture(dragGesture(in: geometry.size))
            .onTapGesture(count: 2) {
                toggleZoom()
            }
        }
        .clipped()
        .frame(minHeight: 200)
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let scale = min(max(viewport.anchorScale * value.magnification, 1), 8)
                viewport.scale = scale
                viewport.offset = Self.clamp(viewport.offset, scale: scale, in: size)
            }
            .onEnded { _ in
                if viewport.isZoomed {
                    viewport.anchorScale = viewport.scale
                    viewport.anchorOffset = viewport.offset
                } else {
                    viewport = CompareViewport()
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard viewport.isZoomed else { return }
                let proposed = CGSize(
                    width: viewport.anchorOffset.width + value.translation.width,
                    height: viewport.anchorOffset.height + value.translation.height
                )
                viewport.offset = Self.clamp(proposed, scale: viewport.scale, in: size)
            }
            .onEnded { value in
                if viewport.isZoomed {
                    viewport.anchorOffset = viewport.offset
                    return
                }
                let horizontal = value.translation.width
                if abs(horizontal) > 50 && abs(horizontal) > abs(value.translation.height) {
                    onStep(horizontal < 0 ? 1 : -1)
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if viewport.isZoomed {
                viewport = CompareViewport()
            } else {
                viewport = CompareViewport(scale: 3, offset: .zero, anchorScale: 3, anchorOffset: .zero)
            }
        }
    }

    /// Impedisce di trascinare l'immagine ingrandita oltre i bordi del riquadro.
    private static func clamp(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max(0, size.width * (scale - 1) / 2)
        let maxY = max(0, size.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}
