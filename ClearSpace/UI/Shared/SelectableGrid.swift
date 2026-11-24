import SwiftUI

/// Riquadro visibile dello scorrimento: non si sposta quando il contenuto scorre.
private var viewportSpace: NamedCoordinateSpace { NamedCoordinateSpace.named("SelectableGrid.viewport") }

/// Parte visibile della griglia: posizione sullo schermo, altezza del riquadro e spazio occupato
/// dalle barre in alto e in basso.
private struct VisibleArea: Equatable {
    /// Bordo superiore del riquadro sullo schermo (coordinate globali).
    var minY: CGFloat = 0
    var height: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

/// Stato del trascinamento che cambia a ogni fotogramma e non deve ridisegnare la griglia:
/// posizione della griglia, ultimo punto del dito, scorrimento automatico in corso.
/// Si usa solo dal thread principale, come la vista che lo possiede.
private final class GridDragTracker {
    var visible = VisibleArea()
    /// Angolo in alto a sinistra della griglia sullo schermo (coordinate globali): cambia mentre scorre.
    var gridOrigin: CGPoint = .zero
    /// Posizione della griglia al primo movimento del gesto in corso: dice se nel frattempo è scorsa.
    var gridOriginAtStart: CGPoint?
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
/// - Un trascinamento che parte chiaramente in orizzontale seleziona tutti gli elementi tra il primo e
///   quello sotto il dito, anche spostandosi poi in verticale su più righe; se il primo era già
///   selezionato, il gesto deseleziona.
/// - Vicino al bordo superiore o inferiore la griglia scorre da sola mentre si trascina.
/// - Un trascinamento verticale o in diagonale, oppure con la griglia ancora in movimento, fa sempre
///   scorrere la griglia: la direzione si misura sullo schermo, una volta sola, all'inizio del gesto.
struct SelectableGrid<Header: View, Footer: View, Cell: View>: View {
    let items: [IndexedItem]
    @Binding var selection: Set<UUID>
    let isSelecting: Bool
    let minimumCellSide: CGFloat
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
    @State private var painter: DragSelection?
    @State private var intent: GridDragIntent = .undecided
    @State private var tracker = GridDragTracker()
    @GestureState private var isDragging = false

    /// Quante celle prima della fine chiedere gli elementi successivi.
    private static var nearEndMargin: Int { 30 }

    init(
        items: [IndexedItem],
        selection: Binding<Set<UUID>>,
        isSelecting: Bool,
        minimumCellSide: CGFloat = 100,
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
                    minY: geometry.frame(in: .global).minY,
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
            endDrag()
        }
    }

    // MARK: - Griglia

    private func grid(proxy: ScrollViewProxy) -> some View {
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
        .onGeometryChange(for: CGPoint.self) { geometry in
            geometry.frame(in: .global).origin
        } action: { origin in
            tracker.gridOrigin = origin
        }
        .simultaneousGesture(dragGesture(proxy: proxy), including: isSelecting ? .all : .subviews)
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
        // Coordinate dello schermo: la direzione del dito non deve dipendere da quanto scorre la griglia.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
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
        case .undecided:
            if tracker.gridOriginAtStart == nil {
                tracker.gridOriginAtStart = tracker.gridOrigin
            }
            let startY = tracker.gridOriginAtStart?.y ?? tracker.gridOrigin.y
            let decision = GridDragIntent.decide(
                screenTranslation: value.translation,
                contentMoved: tracker.gridOrigin.y - startY
            )
            switch decision {
            case .undecided:
                return
            case .scrolling:
                intent = .scrolling
                return
            case .painting:
                guard let start = metrics.index(at: gridPoint(value.startLocation), count: items.count),
                      let next = DragSelection(anchor: start, ids: items.map { $0.id }, current: selection) else {
                    intent = .scrolling
                    return
                }
                intent = .painting
                painter = next
                active = next
                env.recordTutorial(.dragSelect)
            }
        case .painting:
            break
        }
        guard let active else { return }
        let point = gridPoint(value.location)
        tracker.finger = point
        tracker.fingerInViewport = value.location.y - tracker.visible.minY
        paint(at: point, with: active)
        updateAutoScroll(proxy: proxy, painter: active)
    }

    /// Punto dello schermo nelle coordinate della griglia, che si sposta mentre scorre.
    private func gridPoint(_ screenPoint: CGPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - tracker.gridOrigin.x, y: screenPoint.y - tracker.gridOrigin.y)
    }

    private func paint(at location: CGPoint, with painter: DragSelection) {
        guard let index = metrics.index(at: location, count: items.count) else { return }
        let next = painter.selection(reaching: index, ids: items.map { $0.id })
        if next != selection {
            selection = next
        }
    }

    private func endDrag() {
        intent = .undecided
        painter = nil
        tracker.gridOriginAtStart = nil
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
