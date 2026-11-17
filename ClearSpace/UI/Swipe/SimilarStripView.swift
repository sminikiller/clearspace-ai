import SwiftUI

/// Striscia degli elementi simili a quello sulla carta (foto o video dello stesso gruppo).
///
/// - Un tocco su un'anteprima porta quell'elemento sulla carta: lo si guarda (un video parte subito)
///   e lo si decide con i soliti gesti e pulsanti. Vale anche per gli elementi già decisi.
/// - Tenendo premuto si può conservare, scartare o segnare come migliore un elemento senza spostarsi.
/// - «Griglia» apre tutte le anteprime con la selezione multipla, «Confronta» le mette a confronto.
/// - I due pulsanti a destra chiudono l'intero gruppo: tenere le migliori (le stelle dell'utente
///   o, se non ce ne sono, quella consigliata) oppure quello sulla carta.
struct SimilarStripView: View {
    let group: ItemGroup
    let members: [IndexedItem]
    let currentID: UUID
    /// Porta sulla carta l'elemento indicato.
    var onSelect: (UUID) -> Void
    var onOpenGrid: () -> Void
    var onCompare: () -> Void
    var onKeepBest: () -> Void
    /// Conserva l'elemento sulla carta e propone tutti gli altri per l'eliminazione.
    var onKeepOnlyCurrent: () -> Void
    /// Decide un singolo elemento del gruppo senza portarlo sulla carta.
    var onDecide: (UUID, SwipeChoice) -> Void
    /// Mette o toglie la stella dei migliori.
    var onToggleBest: (UUID) -> Void

    /// I video sono maschili ("il migliore"), le foto femminili ("la migliore").
    private var isMasculine: Bool {
        !(members.first?.isImage ?? true)
    }

    private var starredCount: Int {
        members.filter { $0.isStarred }.count
    }

    /// Il pulsante «tieni le migliori» serve solo se c'è qualcosa da tenere e qualcosa da scartare.
    private var canKeepBest: Bool {
        let keepers = GroupChoice.preferredKeepers(members: members, suggestedID: group.suggestedKeepID)
        return !keepers.isEmpty && keepers.count < members.count
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(
                    "\(group.kind.title) · \(members.count)",
                    systemImage: group.kind.isDuplicateKind ? "square.on.square" : "square.stack.3d.down.right"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
                Spacer(minLength: 4)
                // Con il testo grande restano solo le icone: le scritte spingerebbero fuori il titolo.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        gridButton(showsTitle: true)
                        compareButton(showsTitle: true)
                    }
                    HStack(spacing: 14) {
                        gridButton(showsTitle: false)
                        compareButton(showsTitle: false)
                    }
                }
            }

            if dynamicTypeSize > .large {
                // Testo ingrandito: anteprime su tutta la larghezza e pulsanti sotto, affiancati.
                thumbnails
                HStack(spacing: 8) {
                    groupButtons
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    thumbnails
                    VStack(spacing: 5) {
                        groupButtons
                    }
                    .fixedSize()
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func gridButton(showsTitle: Bool) -> some View {
        Button(action: onOpenGrid) {
            if showsTitle {
                Label("Griglia", systemImage: "square.grid.3x3")
            } else {
                Image(systemName: "square.grid.3x3")
            }
        }
        .font(.caption.weight(.semibold))
        .accessibilityLabel("Griglia")
        .accessibilityHint("Mostra tutte le anteprime in griglia, con la selezione multipla")
    }

    private func compareButton(showsTitle: Bool) -> some View {
        Button(action: onCompare) {
            if showsTitle {
                Text("Confronta")
            } else {
                Image(systemName: "rectangle.split.2x1")
            }
        }
        .font(.caption.weight(.semibold))
        .accessibilityLabel("Confronta")
    }

    @ViewBuilder
    private var groupButtons: some View {
        if canKeepBest {
            groupButton(
                GroupWording.keepBestShort(starredCount: starredCount, masculine: isMasculine),
                systemImage: starredCount > 0 ? "star.fill" : "sparkles",
                isProminent: true,
                hint: starredCount > 0
                    ? "Conserva quelli con la stella e aggiunge gli altri alla lista di revisione. Non elimina nulla."
                    : "Conserva l'elemento consigliato e aggiunge gli altri alla lista di revisione. Non elimina nulla.",
                action: onKeepBest
            )
        }
        groupButton(
            isMasculine ? "Tieni solo questo" : "Tieni solo questa",
            systemImage: "checkmark",
            isProminent: false,
            hint: "Conserva l'elemento sulla carta e aggiunge gli altri alla lista di revisione. Non elimina nulla.",
            action: onKeepOnlyCurrent
        )
    }

    private var thumbnails: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        Button {
                            onSelect(member.id)
                        } label: {
                            thumbnail(member)
                        }
                        .buttonStyle(.plain)
                        .id(member.id)
                        .contextMenu {
                            Button {
                                onSelect(member.id)
                            } label: {
                                Label(member.isVideo ? "Guarda" : "Mostra sulla carta", systemImage: member.isVideo ? "play" : "eye")
                            }
                            if member.isStarred {
                                Button {
                                    onToggleBest(member.id)
                                } label: {
                                    Label("Togli la stella", systemImage: "star.slash")
                                }
                            } else {
                                Button {
                                    onToggleBest(member.id)
                                } label: {
                                    Label("Segna come migliore", systemImage: "star")
                                }
                            }
                            Button {
                                onDecide(member.id, .keep)
                            } label: {
                                Label("Conserva", systemImage: "checkmark")
                            }
                            Button(role: .destructive) {
                                onDecide(member.id, .delete)
                            } label: {
                                Label("Proponi per l'eliminazione", systemImage: "trash")
                            }
                        }
                        .accessibilityLabel(description(of: member, position: index + 1))
                        .accessibilityHint("Lo porta sulla carta per guardarlo e deciderlo")
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .onChange(of: currentID) { _, newID in
                withAnimation {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func groupButton(
        _ title: String,
        systemImage: String,
        isProminent: Bool,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        // Affiancati sotto le anteprime (testo grande) si dividono la larghezza in parti uguali.
        let sharesWidth = dynamicTypeSize > .large
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : Theme.keep)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: sharesWidth ? 0 : 132, maxWidth: sharesWidth ? CGFloat.infinity : nil)
            .background(isProminent ? Theme.keep : Theme.keep.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private func thumbnail(_ member: IndexedItem) -> some View {
        let isCurrent = member.id == currentID
        let isSuggested = member.id == group.suggestedKeepID
        return ItemThumbnailView(item: member, pointSide: 60)
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                // Un video non ancora sulla carta mostra che si può avviare.
                if member.isVideo && !isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if member.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.best)
                        .frame(width: 16, height: 16)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(2)
                } else if isSuggested {
                    miniBadge("sparkles", tint: Theme.keep)
                }
            }
            .overlay(alignment: .topLeading) {
                switch member.reviewStatus {
                case .kept:
                    miniBadge("checkmark", tint: Theme.keep)
                case .markedForDeletion, .deletionFailed:
                    miniBadge("trash.fill", tint: Theme.remove)
                case .postponed:
                    miniBadge("clock.fill", tint: Theme.later)
                case .unreviewed:
                    EmptyView()
                }
            }
            .overlay(alignment: .bottom) {
                if member.isVideo && member.duration > 0 {
                    Text(Format.duration(member.duration))
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 3)
            }
    }

    private func miniBadge(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(tint, in: Circle())
            .padding(2)
    }

    /// "Video 2 del gruppo, sulla carta, consigliato, Conservato".
    private func description(of member: IndexedItem, position: Int) -> String {
        var parts = ["\(member.isVideo ? "Video" : member.isImage ? "Foto" : "Elemento") \(position) del gruppo"]
        if member.id == currentID { parts.append("sulla carta") }
        if member.isStarred { parts.append(GroupWording.starred(masculine: member.usesMasculineWording).lowercased()) }
        if member.id == group.suggestedKeepID { parts.append("consigliato") }
        if member.duration > 0 { parts.append(Format.duration(member.duration)) }
        if member.reviewStatus != .unreviewed { parts.append(member.reviewStatus.title) }
        return parts.joined(separator: ", ")
    }
}
