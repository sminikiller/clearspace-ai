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
