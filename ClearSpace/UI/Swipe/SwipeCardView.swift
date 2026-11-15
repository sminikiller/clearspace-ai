import SwiftUI

/// Carta della modalità swipe: l'elemento a tutta larghezza con le informazioni essenziali.
/// Il pizzico ingrandisce l'immagine per controllarne la qualità; il doppio tocco la apre a tutto schermo.
struct SwipeCardView: View {
    let item: IndexedItem
    var isInteractive = true
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
                ItemThumbnailView(item: item, pointSide: 430, fill: false, allowsNetwork: true)
                    .scaleEffect(zoom, anchor: zoomAnchor)
            }
            .clipped()
            .overlay {
                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 58))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .accessibilityHidden(true)
                }
            }
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
                    .padding(10)
                    .accessibilityLabel(item.isVideo ? "Riproduci" : "Apri a tutto schermo")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if isInteractive {
                    onExpand()
                }
            }
            .gesture(magnifyGesture, including: isInteractive ? .all : .none)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(value.magnification, 1), 5)
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
            if item.traits.contains(.livePhoto) {
                cardBadge("Live", "livephoto")
            }
            if item.traits.contains(.cloudOnly) {
                cardBadge("Solo su iCloud", "icloud")
            }
            if item.isSensitive {
                cardBadge("Da controllare", "exclamationmark.shield")
            }
            if item.duplicateGroupID != nil {
                cardBadge("Ha duplicati", "square.on.square")
            } else if item.similarityGroupID != nil {
                cardBadge("Ha simili", "square.stack.3d.down.right")
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

    private func cardBadge(_ text: String, _ systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
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
        return parts.joined(separator: " · ")
    }
}
