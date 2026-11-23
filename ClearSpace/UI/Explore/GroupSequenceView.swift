import SwiftUI

/// Passaggio da un gruppo al successivo nella revisione gruppo per gruppo.
struct GroupSequenceControl {
    /// Posizione del gruppo mostrato, da 1.
    let position: Int
    let total: Int
    /// Il gruppo è stato deciso per intero («Tieni solo la migliore», «Tieni tutte»): si passa al
    /// successivo mostrando il messaggio ricevuto.
    let onDecided: (String) -> Void
    /// L'utente salta il gruppo, oppure va avanti dopo averlo deciso foto per foto.
    let onNext: () -> Void
}

/// Revisione dei gruppi uno dopo l'altro, come un mazzo di carte: si apre la galleria del primo gruppo
/// da decidere e, dopo una scelta su tutto il gruppo, si passa da soli al successivo. «Salta» lo lascia
/// da decidere. Prima vengono i gruppi che liberano più spazio. Come ovunque nell'app, nulla viene
/// eliminato: le foto scartate passano alla Revisione.
struct GroupSequenceView: View {
    let collection: SmartCollection

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    /// Gruppi da proporre, fissati all'apertura: decidere un gruppo non cambia l'ordine degli altri.
    @State private var queue: [UUID]?
    @State private var position = 0
    @State private var decidedCount = 0
    @State private var skippedCount = 0
    @State private var toast: String?

    var body: some View {
        content
            .toast($toast)
            .onAppear {
                guard queue == nil else { return }
                env.recordTutorial(.groupSequence)
                let groups = GroupCatalog.sequence(for: collection, env: env)
                queue = groups
                position = firstAvailable(from: 0, in: groups)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let queue {
            if position < queue.count {
                let groupID = queue[position]
                GroupSelectionView(
                    groupID: groupID,
                    sequence: GroupSequenceControl(
                        position: position + 1,
                        total: queue.count,
                        onDecided: { message in
                            decidedCount += 1
                            toast = message
                            advance()
                        },
                        onNext: {
                            if isDecided(groupID) {
                                decidedCount += 1
                            } else {
                                skippedCount += 1
                            }
                            advance()
                        }
                    )
                )
                // Ogni gruppo riparte da zero: selezione, ordine e confronto non passano al successivo.
                .id(groupID)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                completion(total: queue.count)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
    }

    // MARK: - Fine

    private func completion(total: Int) -> some View {
        CenteredScrollView {
            VStack(spacing: 16) {
                Image(systemName: total == 0 ? "square.on.square" : "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(total == 0 ? Color.secondary : Theme.keep)
                    .accessibilityHidden(true)
                Text(total == 0 ? "Nessun gruppo da rivedere" : "Hai visto tutti i gruppi")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if total > 0 {
                    Text("Decisi: \(decidedCount) · Saltati: \(skippedCount)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(env.store.markedCount > 0
                     ? "Gli elementi che hai scartato sono nella scheda Revisione: nulla è stato eliminato. I gruppi saltati restano da decidere."
                     : "Nulla è stato eliminato. I gruppi saltati restano da decidere e li ritrovi nell'elenco.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    if env.store.markedCount > 0 {
                        Button {
                            openReview()
                        } label: {
                            Text("Vai alla revisione")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Button {
                        dismiss()
                    } label: {
                        Text("Torna all'elenco")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 6)
            }
            .padding(24)
        }
        .background(Theme.background)
        .navigationTitle("Gruppi")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Avanzamento

    private func advance() {
        guard let queue else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            position = firstAvailable(from: position + 1, in: queue)
        }
    }

    /// Salta i gruppi che nel frattempo non esistono più, ad esempio dopo una nuova analisi.
    private func firstAvailable(from start: Int, in queue: [UUID]) -> Int {
        GroupReview.nextAvailable(from: start, count: queue.count) { index in
            guard let group = env.store.group(queue[index]) else { return false }
            return env.store.members(of: group).count >= 2
        }
    }

    private func isDecided(_ groupID: UUID) -> Bool {
        guard let group = env.store.group(groupID) else { return true }
        let members = env.store.members(of: group)
        return GroupReview.summary(
            members: members,
            suggestedID: group.suggestedKeepID,
            evaluator: env.safety.evaluator()
        ).isDecided
    }

    private func openReview() {
        let router = env.router
        dismiss()
        router.selectedTab = .review
    }
}
