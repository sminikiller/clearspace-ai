import SwiftUI

/// Titolo di sezione con sottotitolo facoltativo.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Barra orizzontale che mostra una quota (0…1).
struct StorageBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.placeholder)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Avviso informativo su una riga colorata.
struct InfoBanner: View {
    let text: String
    var systemImage = "info.circle.fill"
    var tint: Color = Theme.info

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Etichetta compatta, ad esempio "Solo su iCloud" o "Protetto".
struct TagChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Valore numerico con didascalia, usato nei riepiloghi.
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// Riga di una categoria con conteggio, spazio occupato ed eventuale lucchetto del piano.
struct CollectionRow: View {
    let collection: SmartCollection
    let stat: CollectionStat
    var isLocked = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collection.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.body)
                Text(collection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Richiede un piano superiore")
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.count(stat.count))
                        .font(.subheadline.weight(.semibold))
                    Text(Format.bytes(stat.bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Schermata mostrata al posto di una funzione non inclusa nel piano attuale.
struct LockedFeatureView: View {
    let feature: Feature

    var body: some View {
        ContentUnavailableView {
            Label(feature.title, systemImage: "lock.fill")
        } description: {
            Text("Questa funzione fa parte del piano \(feature.requiredTier.title). Revisione, conferma, protezioni e annullamento restano sempre disponibili in ogni piano.")
        } actions: {
            NavigationLink("Scopri i piani") {
                PlanView()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Icona e titolo per i pulsanti. Dentro un elenco `Label` colora l'icona con la tinta dell'app:
/// su un pulsante a sfondo pieno diventa invisibile, su uno distruttivo stona con il testo rosso.
/// Qui icona e testo prendono entrambi il colore del pulsante.
struct ButtonTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
    }
}

/// Pulsante di una barra di azioni in basso: icona sopra, scritta sotto. La scritta resta su una
/// riga e si rimpicciolisce un po' se serve, così tre pulsanti stanno sempre affiancati.
struct BarActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    /// Testo per VoiceOver, se diverso dalla scritta breve.
    var accessibilityTitle: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                // Colore del testo, non quello del pulsante: con la tinta grigia sembrerebbe disattivato.
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            // I colori sono scelti a mano: senza questo, in tema scuro un pulsante disattivato
            // sembrerebbe attivo.
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
        .accessibilityLabel(accessibilityTitle ?? title)
    }
}

// MARK: - Layout che si adattano al testo ingrandito

/// Affianca gli elementi quando ci stanno e li mette uno sotto l'altro quando non ci stanno
/// (testo ingrandito, schermo stretto): pulsanti e testi non escono mai dallo schermo.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: verticalAlignment, spacing: spacing) {
                content()
            }
            VStack(alignment: horizontalAlignment, spacing: spacing) {
                content()
            }
        }
    }
}

/// Contenuto centrato in verticale quando ci sta e che scorre quando è più alto dello spazio
/// disponibile (per esempio con il testo molto ingrandito): non resta mai tagliato in alto e in basso.
struct CenteredScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Dispone gli elementi in righe che vanno a capo, come le parole di un testo. Le etichette restano
/// tutte visibili, senza tagli sul bordo e senza dover scorrere di lato.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = Self.size(of: subview, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = Self.size(of: subview, maxWidth: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    /// Dimensione naturale dell'elemento, ristretta alla larghezza disponibile se è più largo
    /// (in quel caso il testo va a capo dentro l'elemento).
    private static func size(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        guard natural.width > maxWidth, maxWidth.isFinite else { return natural }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}

/// Selettore a segmenti che con il testo molto grande diventa un menu: i segmenti affiancati
/// taglierebbero le scritte.
private struct AdaptivePickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.pickerStyle(.menu)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

extension View {
    /// Segmenti con il testo normale, menu con il testo molto grande.
    func adaptiveSegmentedStyle() -> some View {
        modifier(AdaptivePickerStyle())
    }

    /// Limite alla dimensione del testo per barre di comandi e controlli fitti, che non possono
    /// crescere oltre lo spazio dello schermo. Il resto dell'app segue le impostazioni di iOS.
    func compactControlText() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Riga "etichetta: valore" con il valore allineato a destra.
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
