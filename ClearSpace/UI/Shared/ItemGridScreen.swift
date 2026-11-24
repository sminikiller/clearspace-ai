import SwiftUI

/// Descrive un insieme di elementi da mostrare in griglia: una categoria, un filtro o un elenco preciso.
struct ItemQuery: Sendable {
    var title: String
    var subtitle: String?
    var defaultSort: ItemSort = .sizeDescending
    var sessionMode: CleanupMode = .custom
    var predicate: @Sendable (IndexedItem, CollectionContext) -> Bool

    static func collection(_ collection: SmartCollection) -> ItemQuery {
        ItemQuery(
            title: collection.title,
            subtitle: collection.subtitle,
            sessionMode: .collection(id: collection.rawValue),
            predicate: { item, context in collection.contains(item, context: context) }
        )
    }

    static func filter(_ filter: ItemFilter, title: String, mode: CleanupMode = .advanced) -> ItemQuery {
        ItemQuery(
            title: title,
            defaultSort: filter.sort,
            sessionMode: mode,
            predicate: { item, _ in filter.matches(item) }
        )
    }

    static func ids(_ ids: [UUID], title: String, subtitle: String? = nil) -> ItemQuery {
        let wanted = Set(ids)
        return ItemQuery(
            title: title,
            subtitle: subtitle,
            defaultSort: .oldestFirst,
            predicate: { item, _ in wanted.contains(item.id) }
        )
    }
}

/// Griglia di elementi con ordinamento, selezione multipla e avvio della modalità swipe.
/// Con «Seleziona» si scelgono gli elementi a tocchi o trascinando il dito, come nell'app Foto, e
/// «Elimina» li elimina subito (con la conferma di iOS); le altre azioni cambiano soltanto lo stato
/// di revisione o la protezione degli elementi.
///
/// Mentre la si guarda la griglia non cambia ordine: se l'analisi aggiorna i dati, gli elementi già
/// mostrati restano al loro posto e i nuovi arrivano in fondo (`StableOrder`).
struct ItemGridScreen: View {
    let query: ItemQuery
    /// Numero massimo di elementi restituiti (per le ricerche con limite esplicito).
    var limit: Int?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var items: [IndexedItem] = []
    /// Ordinamento con cui sono disposti gli elementi mostrati.
    @State private var arrangedBy: ItemSort?
    @State private var protectedIDs = Set<UUID>()
    @State private var totalBytes: Int64 = 0
    @State private var sort: ItemSort?
    @State private var visibleCount = 300
    @State private var isLoading = true
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var previewItem: IndexedItem?
    @State private var toast: String?
    @State private var isDeleting = false
    @State private var confirmsDeletion = false
    @State private var pendingDeletion: [UUID] = []
    /// Esito dell'ultima eliminazione fatta da qui: ricorda come liberare davvero lo spazio.
    @State private var lastDeletion: DirectDeletionResult?
    @State private var deletionsDone = 0
    @State private var lastReload: Date?

    /// Oltre questo numero di elementi ClearSpace chiede conferma anche per le sole foto.
    private static var largeDeletion: Int { 100 }

    private var activeSort: ItemSort { sort ?? query.defaultSort }

    private struct ReloadKey: Equatable {
        let revision: Int
        let sort: ItemSort
    }

    var body: some View {
        SelectableGrid(
            items: Array(items.prefix(visibleCount)),
            selection: $selection,
            isSelecting: isSelecting,
            minimumCellSide: 100,
            onOpen: { item in env.recordTutorial(.preview); previewItem = item },
            onExpand: { item in env.recordTutorial(.preview); previewItem = item },
            // Le griglie lunghe caricano da sole gli elementi successivi mentre si scorre.
            onNearEnd: { loadMoreIfNeeded() },
            header: {
                header
                if items.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "Nessun elemento",
                        systemImage: "tray",
                        description: Text("Non ci sono contenuti in questa categoria, oppure l'analisi non li ha ancora esaminati.")
                    )
                    .padding(.top, 40)
                }
            },
            footer: {
                if items.count > visibleCount {
                    // Di solito non serve: gli elementi successivi arrivano da soli scorrendo.
                    Button("Mostra altri \(min(300, items.count - visibleCount))") {
                        loadMoreIfNeeded()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            },
            cell: { item, isSelected in
                ItemTile(
                    item: item,
                    isSelected: isSelected,
                    showsSelection: isSelecting,
                    isProtected: protectedIDs.contains(item.id)
                )
            }
        )
        .background(Theme.background)
        .navigationTitle(query.title)
        .onAppear { env.recordTutorial(.openCategory) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .task(id: ReloadKey(revision: env.listRevision, sort: activeSort)) {
            // Durante un'analisi l'indice cambia di continuo: la griglia già mostrata si aggiorna al
            // massimo ogni pochi secondi, così non lavora mentre si scorre.
            if arrangedBy == activeSort, env.scan.isRunning, let lastReload {
                let wait = ScanThrottle.wait(since: lastReload, now: Date())
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled else { return }
                }
            }
            await reload()
        }
        .fullScreenCover(item: $previewItem) { item in
            // A tutto schermo si scorre tra gli elementi della griglia, come in Foto.
            ItemPreviewScreen(
                itemID: item.id,
                itemIDs: ItemPreviewScreen.window(items.prefix(visibleCount).map { $0.id }, around: item.id)
            )
        }
        .confirmationDialog(
            "Eliminare \(Format.plural(pendingDeletion.count, "elemento", "elementi"))?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Elimina \(Format.plural(pendingDeletion.count, "elemento", "elementi"))", role: .destructive) {
                performDeletion(pendingDeletion)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(deletionMessage(for: pendingDeletion))
        }
        .sensoryFeedback(.success, trigger: deletionsDone)
        .toast($toast)
    }

    // MARK: - Contenuto

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let subtitle = query.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(Format.plural(items.count, "elemento", "elementi")) · \(Format.bytes(totalBytes))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                // Solo al primo caricamento: dopo, un aggiornamento non deve spostare la griglia.
                if isLoading && items.isEmpty {
                    ProgressView()
                }
            }
            if let lastDeletion, lastDeletion.deletedCount > 0 {
                InfoBanner(
                    text: "Gli elementi eliminati restano 30 giorni in «Eliminati di recente» dell'app Foto: svuotalo per liberare subito lo spazio.",
                    systemImage: "trash.circle.fill",
                    tint: Theme.keep
                )
            }
            if !items.isEmpty && !isSelecting {
                Button {
                    startSwipe()
                } label: {
                    Label("Rivedi con gli swipe", systemImage: "hand.draw")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.top, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Ordina", selection: Binding(get: { activeSort }, set: { sort = $0; env.recordTutorial(.sortGrid) })) {
                    ForEach(ItemSort.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                Label("Ordina", systemImage: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isSelecting.toggle()
                if isSelecting {
                    env.recordTutorial(.selectMode)
                }
                if !isSelecting {
                    selection.removeAll()
                }
            } label: {
                // Con il testo molto grande solo l'icona: la scritta toglierebbe spazio al titolo.
                if dynamicTypeSize.isAccessibilitySize {
                    Label(isSelecting ? "Fine" : "Seleziona", systemImage: isSelecting ? "checkmark" : "checkmark.circle")
                        .labelStyle(.iconOnly)
                } else {
                    Text(isSelecting ? "Fine" : "Seleziona")
                }
            }
            .disabled(items.isEmpty || isDeleting)
        }
    }

    private var selectionBar: some View {
        let chosen = items.filter { selection.contains($0.id) }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(spacing: 8) {
            HStack {
                Text(Format.plural(selection.count, "selezionato", "selezionati"))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .accessibilityIdentifier("grid.selectionCount")
                Spacer(minLength: 8)
                Button(selection.count == items.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    if selection.count == items.count {
                        selection.removeAll()
                    } else {
                        selection = Set(items.map { $0.id })
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            Button {
                deleteSelection(chosen)
            } label: {
                Group {
                    if isDeleting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label(
                            chosen.isEmpty ? "Elimina" : "Elimina \(chosen.count) · \(Format.bytes(bytes))",
                            systemImage: "trash"
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.remove)
            .controlSize(.large)
            .disabled(chosen.isEmpty || isDeleting)
            .accessibilityIdentifier("grid.delete")
            HStack(spacing: 8) {
                BarActionButton(
                    title: "Revisione",
                    systemImage: "tray.and.arrow.down",
                    tint: Theme.info,
                    accessibilityTitle: "Aggiungi alla Revisione"
                ) {
                    markSelection()
                }
                BarActionButton(title: "Conserva", systemImage: "checkmark", tint: Theme.keep) {
                    env.safety.keep(Array(selection))
                    finishSelection("Elementi conservati.")
                }
                BarActionButton(title: "Proteggi", systemImage: "lock", tint: Theme.info) {
                    env.safety.protect(Array(selection))
                    env.recordTutorial(.protectItem)
                    finishSelection("Elementi protetti.")
                }
            }
            .disabled(selection.isEmpty || isDeleting)
        }
        .padding(12)
        .background(.bar)
        // La barra resta compatta anche con il testo molto grande: la griglia sopra deve restare visibile.
        .compactControlText()
    }

    // MARK: - Azioni

    private func loadMoreIfNeeded() {
        guard items.count > visibleCount else { return }
        visibleCount += 300
    }

    private func markSelection() {
        let result = env.safety.markForDeletion(Array(selection))
        var message = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto è stato saltato", "protetti sono stati saltati"))."
        }
        finishSelection(message)
    }

    private func finishSelection(_ message: String) {
        env.recordTutorial(.gridAction)
        // La scelta va vista subito, anche durante un'analisi.
        lastReload = nil
        selection.removeAll()
        isSelecting = false
        toast = message
    }

    /// «Elimina»: per foto e video basta la conferma di iOS; per i file, per i contenuti che potrebbero
    /// essere importanti e per le selezioni molto grandi chiede prima anche ClearSpace.
    private func deleteSelection(_ chosen: [IndexedItem]) {
        guard !chosen.isEmpty, !isDeleting else { return }
        let ids = chosen.map { $0.id }
        if env.needsInAppConfirmation(chosen) || chosen.count > Self.largeDeletion {
            pendingDeletion = ids
            confirmsDeletion = true
        } else {
            performDeletion(ids)
        }
    }

    private func performDeletion(_ ids: [UUID]) {
        guard !ids.isEmpty, !isDeleting else { return }
        isDeleting = true
        let chosen = env.store.items(ids)
        let isImage = !chosen.isEmpty && chosen.allSatisfy { $0.isImage }
        let isVideo = !chosen.isEmpty && chosen.allSatisfy { $0.isVideo }
        Task {
            let result = await env.deleteDirectly(delete: ids)
            isDeleting = false
            pendingDeletion = []
            switch result.outcome {
            case .cancelled:
                toast = "Eliminazione annullata: non è stato eliminato nulla."
            case .nothing:
                toast = result.note ?? "Non è stato eliminato nulla."
            case .deleted:
                deletionsDone += 1
                lastDeletion = result
                env.recordTutorial(.gridAction)
                selection.removeAll()
                isSelecting = false
                toast = result.summary(isImage: isImage, isVideo: isVideo)
            }
        }
    }

    private func deletionMessage(for ids: [UUID]) -> String {
        let chosen = env.store.items(ids)
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.bytes }
        var parts = ["Liberi fino a \(Format.bytes(bytes))."]
        if chosen.contains(where: { $0.source == .photoLibrary }) {
            parts.append("Foto e video restano 30 giorni in «Eliminati di recente» dell'app Foto e, con Foto di iCloud, spariscono anche dagli altri dispositivi.")
        }
        if chosen.contains(where: { $0.source != .photoLibrary }) {
            parts.append("I file vanno nel cestino dell'app File, se il servizio lo consente.")
        }
        let evaluator = env.safety.evaluator()
        let cautious = chosen.filter { evaluator.needsCaution($0) }.count
        if cautious > 0 {
            parts.append(cautious == 1
                         ? "Attenzione: uno potrebbe contenere qualcosa di importante."
                         : "Attenzione: \(cautious) potrebbero contenere qualcosa di importante.")
        }
        if chosen.contains(where: { $0.source == .photoLibrary }) {
            parts.append("iOS ti chiederà ancora una conferma.")
        }
        return parts.joined(separator: " ")
    }

    private func startSwipe() {
        let started = env.startSession(title: query.title, mode: query.sessionMode, itemIDs: items.map { $0.id })
        if !started {
            toast = "Tutti gli elementi sono già stati decisi o sono protetti."
        }
    }

    private func reload() async {
        isLoading = true
        lastReload = Date()
        let input = env.plannerInput()
        let predicate = query.predicate
        let order = activeSort
        let maximum = limit

        let result = await Task.detached(priority: .userInitiated) { () -> (items: [IndexedItem], locked: Set<UUID>, bytes: Int64) in
            let matched = input.items.filter { predicate($0, input.context) }
            var ordered = ItemFilter.sorted(matched, by: order, score: { input.scorer.score($0) })
            if let maximum, maximum < ordered.count {
                ordered = Array(ordered.prefix(maximum))
            }
            var locked = Set<UUID>()
            var bytes: Int64 = 0
            for item in ordered {
                bytes += item.bytes
                if input.evaluator.isProtected(item) {
                    locked.insert(item.id)
                }
            }
            return (ordered, locked, bytes)
        }.value

        guard !Task.isCancelled else { return }
        // Stesso ordinamento di prima: ciò che è già sullo schermo resta dov'è.
        if arrangedBy == order {
            items = StableOrder.merge(result.items, keeping: items.map { $0.id }, id: { $0.id })
        } else {
            items = result.items
            arrangedBy = order
        }
        protectedIDs = result.locked
        totalBytes = result.bytes
        selection.formIntersection(Set(result.items.map { $0.id }))
        isLoading = false
    }
}
