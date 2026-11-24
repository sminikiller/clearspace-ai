import CoreGraphics
import Foundation

/// Geometria di una griglia a colonne fisse con celle quadrate. Dice quale cella si trova sotto
/// un punto: la selezione con trascinamento ne ha bisogno a ogni movimento del dito, senza poter
/// chiedere a ogni cella la sua posizione (in una griglia pigra quelle fuori schermo non esistono).
struct GridMetrics: Equatable, Sendable {
    var columns: Int
    var spacing: CGFloat
    /// Lato di ogni cella, uguale per tutte.
    var cellSide: CGFloat

    /// Colonne che stanno in `width` con celle di almeno `minimumSide` punti, entro i limiti dati.
    static func fitting(
        width: CGFloat,
        minimumSide: CGFloat,
        spacing: CGFloat,
        minimumColumns: Int = 3,
        maximumColumns: Int = 8
    ) -> GridMetrics {
        let lower = max(1, minimumColumns)
        let upper = max(lower, maximumColumns)
        guard width > 0, minimumSide > 0 else {
            return GridMetrics(columns: lower, spacing: spacing, cellSide: 0)
        }
        let fitting = Int(((width + spacing) / (minimumSide + spacing)).rounded(.down))
        let columns = min(max(fitting, lower), upper)
        let side = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return GridMetrics(columns: columns, spacing: spacing, cellSide: max(0, side))
    }

    /// Distanza tra l'inizio di una riga e l'inizio della successiva.
    var rowStride: CGFloat { cellSide + spacing }

    func row(of index: Int) -> Int {
        index / max(1, columns)
    }

    func rowCount(for count: Int) -> Int {
        count <= 0 ? 0 : (count - 1) / max(1, columns) + 1
    }

    /// Indice della cella sotto `point`, espresso nelle coordinate della griglia. Un punto nello spazio
    /// tra due celle conta per quella che lo precede; uno oltre i bordi vale per la cella più vicina,
    /// così il trascinamento continua anche quando il dito esce dalla griglia.
    func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0, columns > 0, cellSide > 0 else { return nil }
        let column = min(max(Int((point.x / rowStride).rounded(.down)), 0), columns - 1)
        let lastRow = rowCount(for: count) - 1
        let row = min(max(Int((point.y / rowStride).rounded(.down)), 0), lastRow)
        return min(row * columns + column, count - 1)
    }

    /// Prima riga visibile e ultima riga visibile quando la griglia è spostata di `offset` punti
    /// (quanto è scorsa oltre il bordo superiore) in un riquadro alto `height`.
    func visibleRows(offset: CGFloat, height: CGFloat, count: Int) -> ClosedRange<Int>? {
        let rows = rowCount(for: count)
        guard rows > 0, rowStride > 0, height > 0 else { return nil }
        let first = min(max(Int((offset / rowStride).rounded(.down)), 0), rows - 1)
        let last = min(max(Int(((offset + height) / rowStride).rounded(.down)), first), rows - 1)
        return first...last
    }
}

/// Che cosa diventa un trascinamento del dito sulla griglia: selezione o scorrimento.
///
/// Lo spostamento va misurato sullo schermo e non sulla griglia: mentre la griglia scorre si muove
/// insieme al dito, e misurato su di essa ogni scorrimento sembrerebbe quasi fermo in verticale, così
/// basterebbe una piccola deviazione laterale del pollice per far partire la selezione.
enum GridDragIntent: Equatable, Sendable {
    case undecided
    case painting
    case scrolling

    /// Movimento del dito, in punti sullo schermo, prima di decidere.
    static let decisionDistance: CGFloat = 12
    /// Oltre questo spostamento del contenuto la griglia sta già scorrendo.
    static let movingContentTolerance: CGFloat = 10

    /// Decide una volta sola, nei primi millimetri del gesto. Si seleziona soltanto con un gesto
    /// chiaramente orizzontale e con la griglia ferma; in tutti gli altri casi si scorre.
    /// - Parameters:
    ///   - screenTranslation: spostamento del dito sullo schermo dall'inizio del gesto.
    ///   - contentMoved: di quanto si è spostata la griglia sullo schermo dall'inizio del gesto.
    static func decide(screenTranslation: CGSize, contentMoved: CGFloat) -> GridDragIntent {
        let horizontal = abs(screenTranslation.width)
        let vertical = abs(screenTranslation.height)
        guard max(horizontal, vertical) >= decisionDistance else { return .undecided }
        let moving = abs(contentMoved) > movingContentTolerance
        return startsSelection(translation: screenTranslation, contentIsMoving: moving) ? .painting : .scrolling
    }

    /// La regola usata dalle griglie quando il dito ha appena iniziato a muoversi (vedi
    /// `GridDragSelector`): si seleziona solo con un movimento almeno due volte più orizzontale che
    /// verticale e con la griglia ferma. Un pollice che scorre devia di lato, ma molto meno.
    static func startsSelection(translation: CGSize, contentIsMoving: Bool) -> Bool {
        guard !contentIsMoving else { return false }
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        return horizontal > 0 && horizontal > vertical * 2
    }
}

/// Scorrimento automatico mentre si seleziona trascinando il dito: fermo lontano dai bordi, sempre più
/// veloce man mano che il dito si avvicina al bordo superiore o inferiore della parte visibile.
enum GridAutoScroll {
    /// Fascia vicino ai bordi in cui la griglia scorre da sola, in punti.
    static let edge: CGFloat = 72
    static let minimumSpeed: CGFloat = 160
    static let maximumSpeed: CGFloat = 1_100

    /// - Parameters:
    ///   - finger: altezza del dito nel riquadro dello scorrimento.
    ///   - top: inizio della parte visibile, sotto la barra in alto.
    ///   - bottom: fine della parte visibile, sopra le barre in basso.
    /// - Returns: punti al secondo; negativi verso l'alto, zero lontano dai bordi.
    static func speed(finger: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
        guard bottom > top else { return 0 }
        if finger < top + edge {
            let depth = min(1, max(0, (top + edge - finger) / edge))
            return -(minimumSpeed + (maximumSpeed - minimumSpeed) * depth)
        }
        if finger > bottom - edge {
            let depth = min(1, max(0, (finger - (bottom - edge)) / edge))
            return minimumSpeed + (maximumSpeed - minimumSpeed) * depth
        }
        return 0
    }
}

/// Durante un'analisi l'indice cambia di continuo: gli elenchi già mostrati si aggiornano al massimo
/// una volta ogni `interval` secondi, così non lavorano mentre li si scorre.
enum ScanThrottle {
    static let interval: TimeInterval = 4

    /// Quanto aspettare ancora prima del prossimo aggiornamento.
    static func wait(since last: Date, now: Date) -> TimeInterval {
        max(0, interval - now.timeIntervalSince(last))
    }
}

/// Ordine stabile degli elenchi che si aggiornano mentre li si guarda (per esempio durante un'analisi).
/// Gli elementi già mostrati restano dove sono; quelli nuovi si aggiungono in fondo, nell'ordine
/// ricevuto; quelli spariti escono. Così nulla salta sotto il dito mentre si scorre.
enum StableOrder {

    /// - Parameters:
    ///   - fresh: il nuovo elenco, già ordinato come lo si vorrebbe da zero.
    ///   - previous: gli identificativi nell'ordine mostrato finora.
    static func merge<Element, ID: Hashable>(
        _ fresh: [Element],
        keeping previous: [ID],
        id: (Element) -> ID
    ) -> [Element] {
        guard !previous.isEmpty else { return fresh }
        var byID: [ID: Element] = [:]
        byID.reserveCapacity(fresh.count)
        for element in fresh {
            byID[id(element)] = element
        }
        var result: [Element] = []
        result.reserveCapacity(fresh.count)
        var placed = Set<ID>()
        for identifier in previous {
            guard let element = byID[identifier], !placed.contains(identifier) else { continue }
            result.append(element)
            placed.insert(identifier)
        }
        for element in fresh where !placed.contains(id(element)) {
            result.append(element)
            placed.insert(id(element))
        }
        return result
    }
}

/// Selezione con trascinamento, come nell'app Foto: si parte da un elemento e tutti quelli tra il
/// primo e quello sotto il dito prendono lo stato opposto a quello iniziale del primo (se era
/// selezionato si deseleziona, altrimenti si seleziona). Tornando indietro con il dito, gli elementi
/// usciti dall'intervallo riprendono lo stato che avevano prima del gesto.
struct DragSelection: Equatable, Sendable {
    let anchor: Int
    /// `true` se il gesto seleziona, `false` se deseleziona.
    let selects: Bool
    /// Selezione prima del gesto.
    let baseline: Set<UUID>

    init?(anchor: Int, ids: [UUID], current: Set<UUID>) {
        guard ids.indices.contains(anchor) else { return nil }
        self.anchor = anchor
        self.selects = !current.contains(ids[anchor])
        self.baseline = current
    }

    /// Selezione quando il dito è sull'elemento `index`.
    func selection(reaching index: Int, ids: [UUID]) -> Set<UUID> {
        guard !ids.isEmpty else { return baseline }
        let target = min(max(index, 0), ids.count - 1)
        let low = min(anchor, target)
        let high = min(max(anchor, target), ids.count - 1)
        guard low <= high else { return baseline }
        var result = baseline
        for position in low...high {
            if selects {
                result.insert(ids[position])
            } else {
                result.remove(ids[position])
            }
        }
        return result
    }
}

/// Scelte rapide su un gruppo di simili: quali elementi conservare e quali proporre per l'eliminazione.
/// Sono solo proposte: nulla viene eliminato senza la revisione e la conferma finale.
enum GroupChoice {

    /// Conserva `keepIDs` e propone tutti gli altri membri, nell'ordine del gruppo.
    static func keepOnly(_ keepIDs: Set<UUID>, among memberIDs: [UUID]) -> (keep: [UUID], delete: [UUID]) {
        var keep: [UUID] = []
        var delete: [UUID] = []
        for id in memberIDs {
            if keepIDs.contains(id) {
                keep.append(id)
            } else {
                delete.append(id)
            }
        }
        return (keep, delete)
    }

    /// Gli elementi da tenere quando si sceglie «solo le migliori»: quelli con la stella dell'utente,
    /// oppure, se non ce ne sono, quello consigliato dall'app.
    static func preferredKeepers(members: [IndexedItem], suggestedID: UUID?) -> Set<UUID> {
        let starred = Set(members.filter { $0.isStarred }.map { $0.id })
        if !starred.isEmpty { return starred }
        if let suggestedID, members.contains(where: { $0.id == suggestedID }) {
            return [suggestedID]
        }
        return []
    }
}
