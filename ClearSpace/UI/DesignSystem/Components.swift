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
