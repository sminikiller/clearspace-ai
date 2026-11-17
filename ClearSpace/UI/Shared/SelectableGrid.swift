import SwiftUI

/// Riquadro visibile dello scorrimento: non si sposta quando il contenuto scorre.
private var viewportSpace: NamedCoordinateSpace { NamedCoordinateSpace.named("SelectableGrid.viewport") }
/// Spazio della griglia: le posizioni del dito vi si confrontano con quelle delle celle.
private var gridSpace: NamedCoordinateSpace { NamedCoordinateSpace.named("SelectableGrid.grid") }

/// Parte visibile della griglia: altezza del riquadro e spazio occupato dalle barre in alto e in basso.
private struct VisibleArea: Equatable {
    var height: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

/// Stato del trascinamento che cambia a ogni fotogramma e non deve ridisegnare la griglia:
/// posizione della griglia nel riquadro, ultimo punto del dito, scorrimento automatico in corso.
/// Si usa solo dal thread principale, come la vista che lo possiede.
private final class GridDragTracker {
    var visible = VisibleArea()
    /// Inizio della griglia nel riquadro visibile: diventa negativo man mano che si scorre in basso.
    var gridTop: CGFloat = 0
    /// Ultimo punto del dito, nelle coordinate della griglia.
    var finger: CGPoint?
    /// Altezza del dito nel riquadro visibile: resta valida anche quando la griglia scorre da sola.
    var fingerInViewport: CGFloat?
    var autoScrollDirection = 0
    var autoScrollTask: Task<Void, Never>?

    func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = 0
    }
}

/// Griglia con selezione multipla come nell'app Foto.
///
/// - Un tocco seleziona o deseleziona (con la selezione spenta apre l'elemento).
/// - Trascinando in orizzontale si selezionano tutti gli elementi tra il primo e quello sotto il dito,
///   anche spostandosi poi in verticale su più righe; se il primo era già selezionato, il gesto deseleziona.
/// - Vicino al bordo superiore o inferiore la griglia scorre da sola mentre si trascina.
/// - Un trascinamento che parte in verticale fa scorrere la griglia come sempre.
struct SelectableGrid<Header: View, Footer: View, Cell: View>: View {
    let items: [IndexedItem]
    @Binding var selection: Set<UUID>
    let isSelecting: Bool
    let minimumCellSide: CGFloat
    let spacing: CGFloat
    let horizontalPadding: CGFloat
    let onOpen: (IndexedItem) -> Void
    let header: () -> Header
    let footer: () -> Footer
    let cell: (IndexedItem, Bool) -> Cell

    @State private var gridWidth: CGFloat = 0
    @State private var painter: DragSelection?
    @State private var intent: DragIntent = .idle
    @State private var tracker = GridDragTracker()
    @GestureState private var isDragging = false

    private enum DragIntent {
        case idle
        case painting
        case scrolling
    }

    init(
        items: [IndexedItem],
        selection: Binding<Set<UUID>>,
        isSelecting: Bool,
        minimumCellSide: CGFloat = 100,
        spacing: CGFloat = 3,
        horizontalPadding: CGFloat = 12,
        onOpen: @escaping (IndexedItem) -> Void,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder footer: @escaping () -> Footer,
        @ViewBuilder cell: @escaping (IndexedItem, Bool) -> Cell
    ) {
        self.items = items
        self._selection = selection
        self.isSelecting = isSelecting
        self.minimumCellSide = minimumCellSide
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.onOpen = onOpen
        self.header = header
        self.footer = footer
        self.cell = cell
    }

    private var metrics: GridMetrics {
        GridMetrics.fitting(width: gridWidth, minimumSide: minimumCellSide, spacing: spacing)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header()
                    grid(proxy: proxy)
                    footer()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 16)
            }
            .scrollDisabled(painter != nil)
            .coordinateSpace(viewportSpace)
            .onGeometryChange(for: VisibleArea.self) { geometry in
                VisibleArea(
                    height: geometry.size.height,
                    top: geometry.safeAreaInsets.top,
                    bottom: geometry.safeAreaInsets.bottom
                )
            } action: { area in
                tracker.visible = area
            }
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging {
                endDrag()
            }
        }
        .onDisappear {
            tracker.stopAutoScroll()
        }
    }

    // MARK: - Griglia

    private func grid(proxy: ScrollViewProxy) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: metrics.columns)
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
                    .id(item.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            gridWidth = width
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.frame(in: viewportSpace).minY
        } action: { top in
            tracker.gridTop = top
        }
        .simultaneousGesture(dragGesture(proxy: proxy), including: isSelecting ? .all : .subviews)
        // Per ultimo: lo spazio con nome deve racchiudere il gesto, che vi misura la posizione del dito.
        .coordinateSpace(gridSpace)
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

    private func dragGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: gridSpace)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                handleDrag(value, proxy: proxy)
            }
    }

    private func handleDrag(_ value: DragGesture.Value, proxy: ScrollViewProxy) {
        var active = painter
        switch intent {
        case .scrolling:
            return
        case .idle:
            // Come nell'app Foto: si seleziona solo se il gesto parte chiaramente in orizzontale.
            // Uno che parte in verticale o in diagonale resta uno scorrimento, così la griglia
            // scorre sempre quando si vuole scorrerla.
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            // Prima di decidere serve un movimento abbastanza ampio da capirne la direzione.
            guard max(horizontal, vertical) >= 12 else { return }
            guard horizontal > vertical * 2,
                  let start = metrics.index(at: value.startLocation, count: items.count),
                  let next = DragSelection(anchor: start, ids: items.map { $0.id }, current: selection) else {
                intent = .scrolling
                return
            }
            intent = .painting
            painter = next
            active = next
        case .painting:
            break
        }
        guard let active else { return }
        tracker.finger = value.location
        tracker.fingerInViewport = tracker.gridTop + value.location.y
        paint(at: value.location, with: active)
        updateAutoScroll(proxy: proxy, painter: active)
    }

    private func paint(at location: CGPoint, with painter: DragSelection) {
        guard let index = metrics.index(at: location, count: items.count) else { return }
        let next = painter.selection(reaching: index, ids: items.map { $0.id })
        if next != selection {
            selection = next
        }
    }

    private func endDrag() {
        intent = .idle
        painter = nil
        tracker.finger = nil
        tracker.fingerInViewport = nil
        tracker.stopAutoScroll()
    }

    // MARK: - Scorrimento automatico vicino ai bordi

    private func updateAutoScroll(proxy: ScrollViewProxy, painter: DragSelection) {
        guard let fingerY = tracker.fingerInViewport else {
            tracker.stopAutoScroll()
            return
        }
        let area = tracker.visible
        let edge: CGFloat = 64
        let direction: Int
        if fingerY > area.height - area.bottom - edge {
            direction = 1
        } else if fingerY < area.top + edge {
            direction = -1
        } else {
            direction = 0
        }
        guard direction != 0 else {
            tracker.stopAutoScroll()
            return
        }
        guard tracker.autoScrollTask == nil || tracker.autoScrollDirection != direction else { return }
        tracker.stopAutoScroll()
        tracker.autoScrollDirection = direction
        tracker.autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                autoScrollStep(direction, proxy: proxy, painter: painter)
                try? await Task.sleep(for: .milliseconds(220))
            }
        }
    }

    /// Porta in vista la riga successiva (o precedente) e, poiché il dito resta fermo mentre la griglia
    /// scorre, estende la selezione alla cella che ora si trova sotto il dito.
    private func autoScrollStep(_ direction: Int, proxy: ScrollViewProxy, painter: DragSelection) {
        guard !items.isEmpty else { return }
        let metrics = self.metrics
        let area = tracker.visible
        let visibleHeight = max(0, area.height - area.top - area.bottom)
        let offset = area.top - tracker.gridTop
        guard let rows = metrics.visibleRows(offset: offset, height: visibleHeight, count: items.count) else { return }
        let lastRow = metrics.rowCount(for: items.count) - 1
        let target = direction > 0 ? min(rows.upperBound + 1, lastRow) : max(rows.lowerBound - 1, 0)
        let targetIndex = min(target * metrics.columns, items.count - 1)
        withAnimation(.linear(duration: 0.2)) {
            proxy.scrollTo(items[targetIndex].id, anchor: direction > 0 ? .bottom : .top)
        }
        if let finger = tracker.finger, let fingerY = tracker.fingerInViewport {
            paint(at: CGPoint(x: finger.x, y: fingerY - tracker.gridTop), with: painter)
        }
    }
}
