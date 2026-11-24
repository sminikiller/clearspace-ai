import SwiftUI

/// Selezione con trascinamento in corso. È un riferimento e non uno stato da disegnare: cambiarla non
/// ridisegna la griglia, e chi la legge subito dopo averla scritta trova il valore nuovo.
private final class GridDragState {
    var painter: DragSelection?
}

/// Griglia con selezione multipla come nell'app Foto.
///
/// - Un tocco seleziona o deseleziona (con la selezione spenta apre l'elemento).
/// - Un trascinamento che parte su una cella, chiaramente in orizzontale e con la griglia ferma,
///   seleziona tutti gli elementi tra il primo e quello sotto il dito, anche spostandosi poi su più
///   righe; se il primo era già selezionato, il gesto deseleziona. Vicino ai bordi la griglia scorre
///   da sola.
/// - Qualsiasi altro trascinamento fa scorrere la griglia. La decisione si prende prima che la griglia
///   si muova (`GridDragSelector`): uno scorrimento non diventa mai una selezione e una selezione non
///   blocca mai lo scorrimento.
struct SelectableGrid<Header: View, Footer: View, Cell: View>: View {
    let items: [IndexedItem]
    @Binding var selection: Set<UUID>
    let isSelecting: Bool
    let minimumCellSide: CGFloat
    /// Numero fisso di colonne, per esempio due per poche foto da guardare bene. Se manca, le colonne
    /// dipendono dalla larghezza (celle di almeno `minimumCellSide` punti).
    let columns: Int?
    let spacing: CGFloat
    let horizontalPadding: CGFloat
    let onOpen: (IndexedItem) -> Void
    /// Apre l'elemento a tutto schermo: con VoiceOver è un'azione di ogni cella.
    let onExpand: ((IndexedItem) -> Void)?
    /// Chiamata quando compaiono le ultime celle: serve a caricare gli elementi successivi.
    let onNearEnd: (() -> Void)?
    let header: () -> Header
    let footer: () -> Footer
    let cell: (IndexedItem, Bool) -> Cell

    @Environment(AppEnvironment.self) private var env
    @State private var gridWidth: CGFloat = 0
    @State private var dragState = GridDragState()

    /// Quante celle prima della fine chiedere gli elementi successivi.
    private static var nearEndMargin: Int { 30 }

    init(
        items: [IndexedItem],
        selection: Binding<Set<UUID>>,
        isSelecting: Bool,
        minimumCellSide: CGFloat = 100,
        columns: Int? = nil,
        spacing: CGFloat = 3,
        horizontalPadding: CGFloat = 12,
        onOpen: @escaping (IndexedItem) -> Void,
        onExpand: ((IndexedItem) -> Void)? = nil,
        onNearEnd: (() -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder footer: @escaping () -> Footer,
        @ViewBuilder cell: @escaping (IndexedItem, Bool) -> Cell
    ) {
        self.items = items
        self._selection = selection
        self.isSelecting = isSelecting
        self.minimumCellSide = minimumCellSide
        self.columns = columns
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.onOpen = onOpen
        self.onExpand = onExpand
        self.onNearEnd = onNearEnd
        self.header = header
        self.footer = footer
        self.cell = cell
    }

    private var metrics: GridMetrics {
        if let columns {
            return GridMetrics.fitting(
                width: gridWidth,
                minimumSide: 1,
                spacing: spacing,
                minimumColumns: columns,
                maximumColumns: columns
            )
        }
        return GridMetrics.fitting(width: gridWidth, minimumSide: minimumCellSide, spacing: spacing)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header()
                grid
                footer()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 16)
        }
        // Un leggero scatto a ogni elemento che cambia, come nell'app Foto.
        .sensoryFeedback(.selection, trigger: isSelecting ? selection.count : 0)
        .onDisappear {
            dragState.painter = nil
        }
    }

    // MARK: - Griglia

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: metrics.columns)
        let count = items.count
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        cell(item, selection.contains(item.id))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tap(item)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("grid.cell.\(index)")
                    .accessibilityAction {
                        tap(item)
                    }
                    .accessibilityActions {
                        if let onExpand {
                            Button("Apri a tutto schermo") {
                                onExpand(item)
                            }
                        }
                    }
                    .onAppear {
                        if index >= count - Self.nearEndMargin {
                            onNearEnd?()
                        }
                    }
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            gridWidth = width
        }
        .background {
            GridDragSelector(
                isEnabled: isSelecting && !items.isEmpty,
                onBegin: { point in beginDrag(at: point) },
                onMove: { point in extendDrag(to: point) },
                onEnd: { dragState.painter = nil }
            )
            .accessibilityHidden(true)
        }
    }

    private func tap(_ item: IndexedItem) {
        guard isSelecting else {
            onOpen(item)
            return
        }
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    // MARK: - Selezione con trascinamento

    /// Il dito parte da `point` (coordinate della griglia): la cella lì sotto decide se il gesto
    /// seleziona o deseleziona.
    private func beginDrag(at point: CGPoint) -> Bool {
        guard isSelecting,
              let start = metrics.index(at: point, count: items.count),
              let painter = DragSelection(anchor: start, ids: items.map { $0.id }, current: selection) else {
            return false
        }
        dragState.painter = painter
        env.recordTutorial(.dragSelect)
        return true
    }

    private func extendDrag(to point: CGPoint) {
        guard let painter = dragState.painter, let index = metrics.index(at: point, count: items.count) else { return }
        let next = painter.selection(reaching: index, ids: items.map { $0.id })
        if next != selection {
            selection = next
        }
    }
}
