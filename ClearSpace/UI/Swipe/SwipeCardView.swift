import SwiftUI

/// Carta della modalità swipe: l'elemento a tutta larghezza con le informazioni essenziali.
///
/// - Le foto vengono caricate nella versione nitida (scaricandola da iCloud quando serve) e si
///   ingrandiscono con il pizzico, per controllarne la qualità prima di decidere.
/// - I video si riproducono direttamente nella carta.
/// - Se l'elemento fa parte di un gruppo di simili, la carta dice se è lo scatto consigliato.
struct SwipeCardView: View {
    let item: IndexedItem
    var isInteractive = true
    /// Gruppo di simili o duplicati a cui appartiene l'elemento, se esiste.
    var group: ItemGroup?
    /// Avvia il video anche se la riproduzione automatica è disattivata nelle impostazioni.
    var autoplaysVideo = false
    /// Un'altra schermata copre la carta: il video si ferma finché non si torna.
    var isSuspended = false
    var onExpand: () -> Void = {}

    @State private var zoom: CGFloat = 1
    @State private var zoomAnchor: UnitPoint = .center

    var body: some View {
        VStack(spacing: 0) {
            media
            caption
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }

    // MARK: - Contenuto

    private var media: some View {
        Color.black
            .overlay {
                mediaContent
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                badges
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                if isInteractive {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel("Apri a tutto schermo")
                }
            }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if !isInteractive {
            // La carta in attesa sotto quella corrente mostra solo la miniatura.
            ItemThumbnailView(item: item, pointSide: 430, fill: false, allowsNetwork: true)
        } else if item.isVideo {
            InlineVideoView(item: item, forcesAutoplay: autoplaysVideo, isSuspended: isSuspended)
        } else {
            ItemImageView(item: item, pixelSide: 2_048, zoom: zoom, zoomAnchor: zoomAnchor)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    onExpand()
                }
                .gesture(magnifyGesture)
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(value.magnification, 1), 6)
                zoomAnchor = value.startAnchor
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    zoom = 1
                }
            }
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: 5) {
            if item.isStarred {
                cardBadge(GroupWording.starred(masculine: item.usesMasculineWording), "star.fill", iconTint: Theme.best)
            }
            if let group {
                if group.suggestedKeepID == item.id {
                    cardBadge(
                        item.usesMasculineWording ? "Il consigliato del gruppo" : "La consigliata del gruppo",
                        "sparkles",
                        tint: Theme.keep
                    )
                } else if group.kind.isDuplicateKind {
                    cardBadge("Ha \(group.memberIDs.count - 1) \(group.memberIDs.count == 2 ? "copia" : "copie")", "square.on.square")
                } else {
                    cardBadge(
                        "\(group.memberIDs.count) \(item.isVideo ? "video simili" : "scatti simili")",
                        "square.stack.3d.down.right"
                    )
                }
            }
            if item.traits.contains(.livePhoto) {
                cardBadge("Live", "livephoto")
            }
            if item.traits.contains(.cloudOnly) {
                cardBadge("Solo su iCloud", "icloud")
            }
            if item.isSensitive {
                cardBadge("Da controllare", "exclamationmark.shield")
            }
            if let shot = item.shot, shot.hasClosedEyes {
                cardBadge("Occhi chiusi", "eye.slash")
            }
            if item.isLowQuality {
                cardBadge(lowQualityLabel, "camera.metering.unknown")
            }
        }
    }

    private var lowQualityLabel: String {
        if item.traits.contains(.blank) { return "Apparentemente vuota" }
        if item.traits.contains(.dark) { return "Molto scura" }
        return "Forse sfocata"
    }

    private func cardBadge(
        _ text: String,
        _ systemImage: String,
        tint: Color = .black.opacity(0.55),
        iconTint: Color = .white
    ) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconTint)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint, in: Capsule())
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Text(detailLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var detailLine: String {
        var parts: [String] = []
        if item.source.isFileBased {
            parts.append(item.category.title)
        }
        parts.append(Format.bytesOrUnknown(item.estimatedBytes))
        if item.duration > 0 {
            parts.append(Format.duration(item.duration))
        }
        parts.append(Format.date(item.createdAt))
        if item.isImage, item.shot != nil || item.sharpness != nil {
            parts.append("Qualità \(QualityRanker.breakdown(item).grade)/100")
        }
        return parts.joined(separator: " · ")
    }
}
