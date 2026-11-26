import SwiftUI

/// Anteprima di un elemento, caricata in modo asincrono.
/// Per impostazione predefinita non usa la rete: mostra ciò che è disponibile sul dispositivo.
struct ItemThumbnailView: View {
    let item: IndexedItem
    /// Lato dell'immagine richiesta, in punti.
    var pointSide: CGFloat = 130
    var fill = true
    /// Consente di scaricare l'originale da iCloud, se le impostazioni di rete lo permettono.
    var allowsNetwork = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Theme.placeholder)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fill ? .fill : .fit)
                } else {
                    Image(systemName: item.category.systemImage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            // Un'immagine che riempie il riquadro lo supera ai lati: il ritaglio ne nasconde la parte in
            // eccesso, la forma esplicita le toglie anche i tocchi, che spettano ai riquadri vicini.
            .contentShape(Rectangle())
            .task(id: item.id) {
                await load()
            }
            .accessibilityHidden(true)
    }

    private func load() async {
        image = nil
        // Gli audio non hanno un'anteprima visiva: resta il simbolo della categoria.
        guard item.category != .audio else { return }
        let stream = env.thumbnails.images(
            for: item,
            pixelSide: pointSide * displayScale,
            fill: fill,
            allowNetwork: allowsNetwork && env.canDownloadForViewing
        )
        for await next in stream {
            image = next
        }
    }
}

/// Riquadro di una griglia: anteprima con dimensione, durata e stato dell'elemento.
struct ItemTile: View {
    let item: IndexedItem
    var isSelected = false
    var showsSelection = false
    var isProtected = false

    var body: some View {
        ItemThumbnailView(item: item)
            .aspectRatio(1, contentMode: .fit)
            // Fondo scuro sotto ogni scritta: si legge anche sulle foto chiare.
            .overlay(alignment: .bottomLeading) {
                Text(Format.bytesOrUnknown(item.estimatedBytes))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.68), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if item.duration > 0 && (item.isVideo || item.category == .audio) {
                    Text(Format.duration(item.duration))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.68), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    if item.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.best)
                            .frame(width: 20, height: 20)
                            .background(.black.opacity(0.6), in: Circle())
                    }
                    if isProtected {
                        badge("lock.fill", tint: .gray)
                    }
                    if item.traits.contains(.cloudOnly) {
                        badge("icloud", tint: Theme.info)
                    }
                    // Durante la selezione resta solo il cerchio della selezione: un secondo segno di
                    // spunta («conservato») sembrerebbe un'altra selezione.
                    if !showsSelection {
                        switch item.reviewStatus {
                        case .markedForDeletion:
                            badge("trash.fill", tint: Theme.remove)
                        case .deletionFailed:
                            badge("exclamationmark.triangle.fill", tint: Theme.remove)
                        case .kept:
                            badge("checkmark", tint: Theme.keep)
                        case .postponed:
                            badge("clock.fill", tint: Theme.later)
                        case .unreviewed:
                            EmptyView()
                        }
                    }
                }
                .padding(4)
            }
            .overlay(alignment: .topTrailing) {
                if showsSelection {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            // Le scritte sull'anteprima restano piccole anche con il testo grande: non coprono la foto e
            // non si sovrappongono tra loro. Gli stessi dati sono nella descrizione per VoiceOver.
            .thumbnailBadgeText()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func badge(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint, in: Circle())
    }

    private var accessibilityDescription: String {
        var parts = [item.kindDescription, Format.date(item.createdAt), Format.bytesOrUnknown(item.estimatedBytes)]
        if item.isStarred { parts.append("con la stella") }
        if isProtected { parts.append("protetto") }
        if item.traits.contains(.cloudOnly) { parts.append("solo su iCloud") }
        if item.reviewStatus != .unreviewed { parts.append(item.reviewStatus.title) }
        return parts.joined(separator: ", ")
    }
}
