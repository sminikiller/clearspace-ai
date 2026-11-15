import Foundation

/// Risultato parziale di un'analisi, da applicare a un elemento dell'indice.
/// I campi `nil` lasciano invariato il valore esistente.
struct AnalysisUpdate: Sendable {
    let id: UUID
    var addTraits: ItemTraits = []
    var removeTraits: ItemTraits = []
    var contentHash: String?
    var perceptualHash: UInt64?
    var sharpness: Double?
    var brightness: Double?
    var textContent: String?
    var fingerprint: [Float]?
    var duration: Double?
    var pageCount: Int?
    var status: AnalysisStatus?

    init(id: UUID) {
        self.id = id
    }

    func apply(to item: inout IndexedItem) {
        item.traits.subtract(removeTraits)
        item.traits.formUnion(addTraits)
        if let contentHash { item.contentHash = contentHash }
        if let perceptualHash { item.perceptualHash = perceptualHash }
        if let sharpness { item.sharpness = sharpness }
        if let brightness { item.brightness = brightness }
        if let textContent { item.textContent = textContent }
        if let fingerprint { item.fingerprint = fingerprint }
        if let duration, duration > 0 { item.duration = duration }
        if let pageCount { item.pageCount = pageCount }
        if let status { item.analysisStatus = status }
        item.analysisVersion = AppConfiguration.analysisVersion
    }
}
