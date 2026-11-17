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
/// Con «Seleziona» si scelgono gli elementi a tocchi o trascinando il dito, come nell'app Foto.
/// Le azioni disponibili cambiano soltanto lo stato di revisione o la protezione degli elementi.
struct ItemGridScreen: View {
    let query: ItemQuery
    /// Numero massimo di elementi restituiti (per le ricerche con limite esplicito).
    var limit: Int?

    @Environment(AppEnvironment.self) private var env
    @State private var items: [IndexedItem] = []
    @State private var protectedIDs = Set<UUID>()
    @State private var totalBytes: Int64 = 0
    @State private var sort: ItemSort?
    @State private var visibleCount = 300
    @State private var isLoading = true
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var previewItem: IndexedItem?
    @State private var toast: String?

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
            onOpen: { item in previewItem = item },
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
                    Button("Mostra altri \(min(300, items.count - visibleCount))") {
                        visibleCount += 300
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .task(id: ReloadKey(revision: env.listRevision, sort: activeSort)) {
            await reload()
        }
        .fullScreenCover(item: $previewItem) { item in
            ItemPreviewScreen(itemID: item.id)
        }
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
                if isLoading {
                    ProgressView()
                }
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
                Picker("Ordina", selection: Binding(get: { activeSort }, set: { sort = $0 })) {
                    ForEach(ItemSort.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                Label("Ordina", systemImage: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(isSelecting ? "Fine" : "Seleziona") {
                isSelecting.toggle()
                if !isSelecting {
                    selection.removeAll()
                }
            }
            .disabled(items.isEmpty)
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text(Format.plural(selection.count, "selezionato", "selezionati"))
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("grid.selectionCount")
                Spacer()
                Button(selection.count == items.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    if selection.count == items.count {
                        selection.removeAll()
                    } else {
                        selection = Set(items.map { $0.id })
                    }
                }
                .font(.subheadline)
            }
            HStack(spacing: 8) {
                Button {
                    markSelection()
                } label: {
                    Label("Da eliminare", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .tint(Theme.remove)

                Button {
                    env.safety.keep(Array(selection))
                    finishSelection("Elementi conservati.")
                } label: {
                    Label("Conserva", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(Theme.keep)

                Button {
                    env.safety.protect(Array(selection))
                    finishSelection("Elementi protetti.")
                } label: {
                    Label("Proteggi", systemImage: "lock")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            .font(.footnote)
            .disabled(selection.isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Azioni

    private func markSelection() {
        let result = env.safety.markForDeletion(Array(selection))
        var message = "\(Format.plural(result.applied, "elemento aggiunto", "elementi aggiunti")) alla revisione."
        if result.blocked > 0 {
            message += " \(Format.plural(result.blocked, "protetto è stato saltato", "protetti sono stati saltati"))."
        }
        finishSelection(message)
    }

    private func finishSelection(_ message: String) {
        selection.removeAll()
        isSelecting = false
        toast = message
    }

    private func startSwipe() {
        let started = env.startSession(title: query.title, mode: query.sessionMode, itemIDs: items.map { $0.id })
        if !started {
            toast = "Tutti gli elementi sono già stati decisi o sono protetti."
        }
    }

    private func reload() async {
        isLoading = true
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
        items = result.items
        protectedIDs = result.locked
        totalBytes = result.bytes
        selection.formIntersection(Set(result.items.map { $0.id }))
        isLoading = false
    }
}
