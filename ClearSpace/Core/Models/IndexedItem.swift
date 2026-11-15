import Foundation

/// Origine fisica di un contenuto.
enum StorageSource: String, Codable, CaseIterable, Sendable {
    case photoLibrary
    case localFiles
    case iCloudDrive
    case appImports

    var title: String {
        switch self {
        case .photoLibrary: return "Libreria Foto"
        case .localFiles: return "File locali"
        case .iCloudDrive: return "iCloud Drive"
        case .appImports: return "Importati in ClearSpace"
        }
    }

    var systemImage: String {
        switch self {
        case .photoLibrary: return "photo.on.rectangle"
        case .localFiles: return "folder"
        case .iCloudDrive: return "icloud"
        case .appImports: return "square.and.arrow.down"
        }
    }

    var isFileBased: Bool { self != .photoLibrary }
}

/// Tipo principale del contenuto, indipendente dall'origine.
enum ContentCategory: String, Codable, CaseIterable, Sendable {
    case photo
    case video
    case pdf
    case office
    case archive
    case audio
    case otherDocument
    case unknown

    var title: String {
        switch self {
        case .photo: return "Foto"
        case .video: return "Video"
        case .pdf: return "PDF"
        case .office: return "Documento Office"
        case .archive: return "Archivio compresso"
        case .audio: return "Audio"
        case .otherDocument: return "Documento"
        case .unknown: return "File sconosciuto"
        }
    }

    var systemImage: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .pdf: return "doc.richtext"
        case .office: return "doc.text"
        case .archive: return "doc.zipper"
        case .audio: return "waveform"
        case .otherDocument: return "doc"
        case .unknown: return "questionmark.folder"
        }
    }

    var isDocument: Bool {
        switch self {
        case .pdf, .office, .archive, .otherDocument, .unknown: return true
        case .photo, .video, .audio: return false
        }
    }
}

/// Caratteristiche di un elemento: alcune arrivano dai metadati, altre dalle analisi locali.
struct ItemTraits: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int64

    init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    // Metadati
    static let screenshot = ItemTraits(rawValue: 1 << 0)
    static let livePhoto = ItemTraits(rawValue: 1 << 1)
    static let burst = ItemTraits(rawValue: 1 << 2)
    static let panorama = ItemTraits(rawValue: 1 << 3)
    static let selfie = ItemTraits(rawValue: 1 << 4)
    static let portrait = ItemTraits(rawValue: 1 << 5)
    static let hdr = ItemTraits(rawValue: 1 << 6)
    static let raw = ItemTraits(rawValue: 1 << 7)
    static let edited = ItemTraits(rawValue: 1 << 8)
    static let favorite = ItemTraits(rawValue: 1 << 9)
    static let hidden = ItemTraits(rawValue: 1 << 10)
    static let screenRecording = ItemTraits(rawValue: 1 << 11)
    static let slowMotion = ItemTraits(rawValue: 1 << 12)
    static let timelapse = ItemTraits(rawValue: 1 << 13)
    static let cinematic = ItemTraits(rawValue: 1 << 14)
    static let video4K = ItemTraits(rawValue: 1 << 15)
    static let highFrameRate = ItemTraits(rawValue: 1 << 16)
    /// L'originale non è presente sul dispositivo (solo su iCloud).
    static let cloudOnly = ItemTraits(rawValue: 1 << 17)
    static let fromOtherApp = ItemTraits(rawValue: 1 << 18)
    static let download = ItemTraits(rawValue: 1 << 19)
    static let lowResolution = ItemTraits(rawValue: 1 << 20)
    static let heavyForResolution = ItemTraits(rawValue: 1 << 21)

    // Analisi locali
    static let hasText = ItemTraits(rawValue: 1 << 32)
    static let conversation = ItemTraits(rawValue: 1 << 33)
    static let receipt = ItemTraits(rawValue: 1 << 34)
    static let qrCode = ItemTraits(rawValue: 1 << 35)
    static let documentLike = ItemTraits(rawValue: 1 << 36)
    static let ticket = ItemTraits(rawValue: 1 << 37)
    static let sensitiveText = ItemTraits(rawValue: 1 << 38)
    static let blurry = ItemTraits(rawValue: 1 << 39)
    static let dark = ItemTraits(rawValue: 1 << 40)
    static let blank = ItemTraits(rawValue: 1 << 41)
    static let longSilence = ItemTraits(rawValue: 1 << 42)
    static let similarityChecked = ItemTraits(rawValue: 1 << 43)
    static let transcribed = ItemTraits(rawValue: 1 << 44)

    /// Tratti prodotti dalle analisi: sopravvivono a un semplice aggiornamento dei metadati.
    static let analysisMask: ItemTraits = [
        .hasText, .conversation, .receipt, .qrCode, .documentLike, .ticket, .sensitiveText,
        .blurry, .dark, .blank, .longSilence, .similarityChecked, .transcribed
    ]

    /// Tratti che richiedono particolare cautela prima di un'eliminazione.
    static let sensitiveMask: ItemTraits = [.receipt, .qrCode, .documentLike, .ticket, .sensitiveText]

    static let lowQualityMask: ItemTraits = [.blurry, .dark, .blank]
}

/// Stato di avanzamento dell'analisi di un elemento.
enum AnalysisStatus: String, Codable, CaseIterable, Sendable {
    /// Fase A: solo metadati.
    case metadataOnly
    /// Fase B: analizzata l'anteprima.
    case previewAnalyzed
    /// Fase C: analizzato il contenuto originale (hash).
    case deepAnalyzed
    /// Il contenuto è solo online e non è stato scaricato.
    case unavailableOffline
    case failed

    var title: String {
        switch self {
        case .metadataOnly: return "Solo metadati"
        case .previewAnalyzed: return "Anteprima analizzata"
        case .deepAnalyzed: return "Contenuto verificato"
        case .unavailableOffline: return "Solo online, non scaricato"
        case .failed: return "Analisi non riuscita"
        }
    }
}

/// Decisione dell'utente su un elemento. Nessuno di questi stati comporta un'eliminazione:
/// i file vengono rimossi soltanto dal `SafetyEngine` dopo revisione e conferma.
enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case unreviewed
    case kept
    case markedForDeletion
    case postponed
    case deletionFailed

    var title: String {
        switch self {
        case .unreviewed: return "Da rivedere"
        case .kept: return "Conservato"
        case .markedForDeletion: return "In attesa di eliminazione"
        case .postponed: return "Rimandato"
        case .deletionFailed: return "Operazione non riuscita"
        }
    }

    /// L'elemento è nella lista di revisione delle eliminazioni.
    var isQueuedForDeletion: Bool {
        self == .markedForDeletion || self == .deletionFailed
    }
}

/// Record logico di un elemento indicizzato.
/// Contiene solo riferimenti e metadati: il file originale non viene mai copiato nell'indice.
struct IndexedItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// `PHAsset.localIdentifier` per la libreria Foto, percorso relativo alla cartella per i file.
    let sourceIdentifier: String
    let source: StorageSource
    var category: ContentCategory

    var filename: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var estimatedBytes: Int64?
    /// `true` quando la dimensione è stimata e non letta dal sistema.
    var bytesAreEstimated: Bool
    /// Spazio effettivamente occupato sul dispositivo, se noto.
    var localBytes: Int64?
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: Double
    var latitude: Double?
    var longitude: Double?
    var traits: ItemTraits
    var burstIdentifier: String?
    var folderID: UUID?
    var relativePath: String?
    var pageCount: Int?

    // Risultati delle analisi
    /// SHA-256 del contenuto originale: presente solo dopo una verifica completa.
    var contentHash: String?
    /// Hash percettivo calcolato sull'anteprima.
    var perceptualHash: UInt64?
    var duplicateGroupID: UUID?
    var similarityGroupID: UUID?
    var sharpness: Double?
    var brightness: Double?
    /// Testo riconosciuto (OCR) o trascrizione, troncato.
    var textContent: String?
    /// Impronta compatta dell'andamento sonoro, per confrontare le registrazioni tra loro.
    var fingerprint: [Float]?
    var analysisStatus: AnalysisStatus
    var analysisVersion: Int

    // Decisioni dell'utente
    var reviewStatus: ReviewStatus
    /// Protezione esplicita scelta dall'utente.
    var isProtected: Bool
    /// L'utente ha sbloccato esplicitamente una protezione automatica (es. preferito).
    var protectionOverride: Bool
    var decidedAt: Date?

    init(
        id: UUID = UUID(),
        sourceIdentifier: String,
        source: StorageSource,
        category: ContentCategory,
        filename: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        estimatedBytes: Int64? = nil,
        bytesAreEstimated: Bool = false,
        localBytes: Int64? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        duration: Double = 0,
        traits: ItemTraits = []
    ) {
        self.id = id
        self.sourceIdentifier = sourceIdentifier
        self.source = source
        self.category = category
        self.filename = filename
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.estimatedBytes = estimatedBytes
        self.bytesAreEstimated = bytesAreEstimated
        self.localBytes = localBytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.latitude = nil
        self.longitude = nil
        self.traits = traits
        self.burstIdentifier = nil
        self.folderID = nil
        self.relativePath = nil
        self.pageCount = nil
        self.contentHash = nil
        self.perceptualHash = nil
        self.duplicateGroupID = nil
        self.similarityGroupID = nil
        self.sharpness = nil
        self.brightness = nil
        self.textContent = nil
        self.fingerprint = nil
        self.analysisStatus = .metadataOnly
        self.analysisVersion = AppConfiguration.analysisVersion
        self.reviewStatus = .unreviewed
        self.isProtected = false
        self.protectionOverride = false
        self.decidedAt = nil
    }
}

extension IndexedItem {

    var bytes: Int64 { estimatedBytes ?? 0 }

    /// Spazio che l'elemento occupa sull'iPhone (zero se l'originale è solo su iCloud).
    var deviceBytes: Int64 {
        if let localBytes { return localBytes }
        return traits.contains(.cloudOnly) ? 0 : bytes
    }

    var pixelCount: Int { pixelWidth * pixelHeight }

    var isImage: Bool { category == .photo }
    var isVideo: Bool { category == .video }
    var isLibraryAsset: Bool { source == .photoLibrary }

    /// Non ancora deciso: mai visto oppure rimandato.
    var isPendingReview: Bool {
        reviewStatus == .unreviewed || reviewStatus == .postponed
    }

    /// Contenuto potenzialmente importante: richiede una revisione più attenta.
    var isSensitive: Bool {
        if !traits.isDisjoint(with: .sensitiveMask) { return true }
        return category == .pdf || category == .office
    }

    var isLowQuality: Bool { !traits.isDisjoint(with: .lowQualityMask) }

    /// Descrizione breve del tipo: "Screenshot", "Live Photo", "Video 4K"…
    var kindDescription: String {
        switch category {
        case .photo:
            if traits.contains(.screenshot) { return "Screenshot" }
            if traits.contains(.panorama) { return "Panoramica" }
            if traits.contains(.livePhoto) { return "Live Photo" }
            if traits.contains(.burst) { return "Scatto in raffica" }
            if traits.contains(.selfie) { return "Selfie" }
            if traits.contains(.portrait) { return "Ritratto" }
            return source == .photoLibrary ? "Foto" : "Immagine"
        case .video:
            if traits.contains(.screenRecording) { return "Registrazione schermo" }
            if traits.contains(.slowMotion) { return "Slow motion" }
            if traits.contains(.timelapse) { return "Time-lapse" }
            if traits.contains(.video4K) { return "Video 4K" }
            return "Video"
        default:
            return category.title
        }
    }

    /// Titolo mostrato nell'interfaccia.
    var displayTitle: String {
        if source.isFileBased, let filename, !filename.isEmpty { return filename }
        return kindDescription
    }

    /// Testo su cui cercare: nome del file più testo riconosciuto, senza accenti e in minuscolo.
    var searchableText: String {
        let combined = [filename, relativePath, textContent].compactMap { $0 }.joined(separator: " ")
        return combined.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    func age(at now: Date) -> TimeInterval? {
        guard let createdAt else { return nil }
        return now.timeIntervalSince(createdAt)
    }

    /// Aggiorna i metadati con una nuova lettura, conservando decisioni e analisi
    /// se il contenuto non è cambiato.
    mutating func applyMetadata(from fresh: IndexedItem) {
        let contentChanged =
            fresh.modifiedAt != modifiedAt
            || fresh.pixelWidth != pixelWidth
            || fresh.pixelHeight != pixelHeight
            || (fresh.estimatedBytes != nil && !fresh.bytesAreEstimated && fresh.estimatedBytes != estimatedBytes)
            || analysisVersion != AppConfiguration.analysisVersion

        category = fresh.category
        filename = fresh.filename ?? filename
        createdAt = fresh.createdAt
        modifiedAt = fresh.modifiedAt
        if fresh.estimatedBytes != nil {
            estimatedBytes = fresh.estimatedBytes
            bytesAreEstimated = fresh.bytesAreEstimated
        }
        localBytes = fresh.localBytes
        pixelWidth = fresh.pixelWidth
        pixelHeight = fresh.pixelHeight
        if fresh.duration > 0 { duration = fresh.duration }
        latitude = fresh.latitude
        longitude = fresh.longitude
        burstIdentifier = fresh.burstIdentifier
        folderID = fresh.folderID
        relativePath = fresh.relativePath

        if contentChanged {
            traits = fresh.traits
            contentHash = nil
            perceptualHash = nil
            duplicateGroupID = nil
            similarityGroupID = nil
            sharpness = nil
            brightness = nil
            textContent = nil
            fingerprint = nil
            pageCount = fresh.pageCount
            analysisStatus = .metadataOnly
            analysisVersion = AppConfiguration.analysisVersion
        } else {
            traits = fresh.traits.union(traits.intersection(.analysisMask))
        }
    }
}
