import SwiftUI

/// Anteprime di un gruppo su tutta la larghezza della riga: fino a quattro riquadri uguali, l'ultimo
/// con «+N» quando gli elementi sono di più. I riquadri vuoti mantengono la stessa misura, così le
/// anteprime hanno la stessa grandezza in tutte le righe e la riga non resta sbilanciata a sinistra.
struct GroupStrip<Badge: View>: View {
    let members: [IndexedItem]
    var slots = 4
    /// Elementi mostrati spenti, ad esempio quelli che verranno eliminati.
    var dimmed: (IndexedItem) -> Bool = { _ in false }
    /// Descrizione per VoiceOver; senza, le anteprime restano nascoste a VoiceOver (la riga le
    /// descrive già con il testo).
    var accessibilityDescription: String?
    /// Segno nell'angolo in basso a destra di ogni anteprima.
    @ViewBuilder var badge: (IndexedItem) -> Badge

    var body: some View {
        let shown = Array(members.prefix(slots))
        let extra = members.count - shown.count
        HStack(spacing: 4) {
            ForEach(0..<slots, id: \.self) { slot in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if slot < shown.count {
                            tile(shown[slot], extra: slot == shown.count - 1 ? extra : 0)
                        }
                    }
            }
        }
        .thumbnailBadgeText()
        .modifier(StripAccessibility(description: accessibilityDescription))
    }

    private func tile(_ member: IndexedItem, extra: Int) -> some View {
        ItemThumbnailView(item: member, pointSide: 110)
            .overlay {
                if dimmed(member) {
                    Color.black.opacity(0.4)
                }
            }
            .overlay {
                if extra > 0 {
                    ZStack {
                        Color.black.opacity(0.55)
                        Text("+\(extra)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                badge(member)
                    .padding(3)
            }
    }
}

private struct StripAccessibility: ViewModifier {
    let description: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let description {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(description)
        } else {
            content
                .accessibilityHidden(true)
        }
    }
}

/// Segno tondo sulle anteprime piccole: cestino, segno verde, stella.
struct GroupStripBadge: View {
    let systemImage: String
    var tint: Color
    var symbolColor: Color = .white

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(symbolColor)
            .frame(width: 20, height: 20)
            .background(tint, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1)
            }
    }
}
