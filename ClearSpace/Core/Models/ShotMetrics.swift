import Foundation

/// Misure usate per scegliere lo scatto migliore tra foto simili.
/// Vengono calcolate soltanto per i membri dei gruppi, su un'anteprima più grande
/// di quella usata nella scansione generale, e restano sul dispositivo.
struct ShotMetrics: Codable, Hashable, Sendable {
    /// Nitidezza dell'intera immagine (0…1).
    var detailSharpness: Double
    /// Nitidezza del soggetto: il volto più grande oppure, senza volti, la zona centrale (0…1).
    var subjectSharpness: Double?
    /// Volti riconosciuti nell'immagine.
    var faceCount: Int
    /// Qualità dei volti secondo Vision (0…1): messa a fuoco, luce, posa, espressione.
    var faceQuality: Double?
    /// Quota di volti con gli occhi aperti (0…1). `nil` se non è stato possibile stabilirlo.
    var openEyes: Double?
    /// Quota di volti sorridenti (0…1).
    var smiles: Double?
    /// Giudizio estetico complessivo di Vision, da −1 a 1. Disponibile da iOS 18.
    var aesthetics: Double?

    init(
        detailSharpness: Double,
        subjectSharpness: Double? = nil,
        faceCount: Int = 0,
        faceQuality: Double? = nil,
        openEyes: Double? = nil,
        smiles: Double? = nil,
        aesthetics: Double? = nil
    ) {
        self.detailSharpness = detailSharpness
        self.subjectSharpness = subjectSharpness
        self.faceCount = faceCount
        self.faceQuality = faceQuality
        self.openEyes = openEyes
        self.smiles = smiles
        self.aesthetics = aesthetics
    }

    var hasFaces: Bool { faceCount > 0 && faceQuality != nil }

    /// Almeno un volto ha gli occhi chiusi.
    var hasClosedEyes: Bool {
        guard let openEyes else { return false }
        return openEyes < 0.99
    }
}

/// Rettangolo di pixel di un'immagine; gli estremi massimi sono esclusi.
struct PixelRegion: Equatable, Sendable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { max(0, maxX - minX) }
    var height: Int { max(0, maxY - minY) }
}
