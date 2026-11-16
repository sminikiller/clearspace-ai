import SwiftUI

/// Striscia degli scatti simili a quello sulla carta: mostra tutto il gruppo, evidenzia lo scatto
/// consigliato e permette di confrontarli o di tenere il migliore con un solo tocco.
struct SimilarStripView: View {
    let group: ItemGroup
    let members: [IndexedItem]
    let currentID: UUID
    /// Apre il confronto partendo dall'elemento indicato.
    var onCompare: (UUID) -> Void
    var onKeepBest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    "\(group.kind.title) · \(members.count)",
                    systemImage: group.kind.isDuplicateKind ? "square.on.square" : "square.stack.3d.down.right"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Spacer()
                Button("Confronta") {
                    onCompare(currentID)
                }
                .font(.caption.weight(.semibold))
            }

            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(members) { member in
                            Button {
                                onCompare(member.id)
                            } label: {
                                thumbnail(member)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(description(of: member))
                            .accessibilityHint("Apre il confronto")
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 1)
                }

                if group.suggestedKeepID != nil {
                    Button(action: onKeepBest) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .accessibilityHidden(true)
                            Text("Tieni la migliore")
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.keep)
                    .controlSize(.small)
                    .accessibilityHint("Conserva lo scatto consigliato e aggiunge gli altri alla lista di revisione. Non elimina nulla.")
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func thumbnail(_ member: IndexedItem) -> some View {
        let isCurrent = member.id == currentID
        let isSuggested = member.id == group.suggestedKeepID
        return ItemThumbnailView(item: member, pointSide: 60)
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isSuggested {
                    miniBadge("star.fill", tint: Theme.keep)
                }
            }
            .overlay(alignment: .bottomLeading) {
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

    private func description(of member: IndexedItem) -> String {
        var parts = [member.kindDescription, Format.date(member.createdAt)]
        if member.id == currentID { parts.append("quello sulla carta") }
        if member.id == group.suggestedKeepID { parts.append("consigliato") }
        if member.reviewStatus != .unreviewed { parts.append(member.reviewStatus.title) }
        return parts.joined(separator: ", ")
    }
}
