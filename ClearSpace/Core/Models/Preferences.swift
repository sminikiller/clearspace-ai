import Foundation

/// Stato di Foto di iCloud. iOS non lo espone alle app: lo dichiara l'utente,
/// oppure viene dedotto quando si trovano originali presenti solo online.
enum ICloudPhotosState: String, Codable, CaseIterable, Sendable {
    case unknown
    case enabled
    case disabled

    var title: String {
        switch self {
        case .unknown: return "Non so"
        case .enabled: return "Attivo"
        case .disabled: return "Non attivo"
        }
    }
}

/// Dati sul piano iCloud inseriti a mano dall'utente (iOS non li rende leggibili alle app).
struct ManualICloudQuota: Codable, Equatable, Sendable {
    var totalGB: Double
    var usedGB: Double
    var updatedAt: Date
}

enum ReminderFrequency: String, Codable, CaseIterable, Sendable {
    case off
    case weekly
    case monthly
    case quarterly

    var title: String {
        switch self {
        case .off: return "Mai"
        case .weekly: return "Ogni settimana"
        case .monthly: return "Ogni mese"
        case .quarterly: return "Ogni tre mesi"
        }
    }
}

enum PlanTier: Int, Codable, CaseIterable, Comparable, Sendable {
    case free = 0
    case pro = 1
    case proPlus = 2

    static func < (lhs: PlanTier, rhs: PlanTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .free: return "Gratuito"
        case .pro: return "Pro"
        case .proPlus: return "Pro Plus"
        }
    }
}

/// Funzioni soggette a piano. Le funzioni di sicurezza (revisione, conferma, protezioni,
/// annullamento) non compaiono qui: sono sempre disponibili.
enum Feature: String, CaseIterable, Sendable {
    case exactDuplicates
    case similarPhotos
    case ocrClassification
    case advancedFilters
    case documents
    case smartSearch
    case audioTools
    case videoCompression
    case organization
    case similarDocuments

    var requiredTier: PlanTier {
        switch self {
        case .exactDuplicates, .similarPhotos, .ocrClassification, .advancedFilters, .documents:
            return .pro
        case .smartSearch, .audioTools, .videoCompression, .organization, .similarDocuments:
            return .proPlus
        }
    }

    var title: String {
        switch self {
        case .exactDuplicates: return "Analisi avanzata dei duplicati"
        case .similarPhotos: return "Foto e video simili"
        case .ocrClassification: return "Classificazione degli screenshot con OCR"
        case .advancedFilters: return "Filtri evoluti"
        case .documents: return "Documenti e iCloud Drive"
        case .smartSearch: return "Ricerca in linguaggio naturale"
        case .audioTools: return "Strumenti per audio e registrazioni"
        case .videoCompression: return "Compressione dei video"
        case .organization: return "Organizzazione dei file"
        case .similarDocuments: return "Versioni simili dei documenti"
        }
    }
}

/// Preferenze dell'utente. La decodifica tollera campi mancanti, così nuove versioni
/// dell'app possono aggiungere impostazioni senza perdere quelle esistenti.
struct UserPreferences: Codable, Equatable, Sendable {
    var hasCompletedOnboarding = false
    var iCloudPhotosState: ICloudPhotosState = .unknown
    var manualICloudQuota: ManualICloudQuota?
    /// Scarica contenuti da iCloud solo con Wi‑Fi.
    var wifiOnlyDownloads = true
    /// Consenso a scaricare gli originali da iCloud quando serve per verificare un duplicato.
    var allowCloudDownloadsForAnalysis = false
    /// Sospende le analisi costose con batteria scarica o dispositivo caldo.
    var pauseOnLowBattery = true
    var includeHiddenAssets = false
    var quickSessionSize = 50
    var largeVideoThresholdMB = 100
    /// Nella modalità swipe i video partono da soli, senza audio.
    var autoplayVideos = true
    var reminderFrequency: ReminderFrequency = .off
    var protection = ProtectionRules()
    var transcriptionLocaleIdentifier = "it-IT"
    var lastScanCompletedAt: Date?
    /// Solo per provare i piani durante lo sviluppo.
    var developerTier: PlanTier?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        iCloudPhotosState = try container.decodeIfPresent(ICloudPhotosState.self, forKey: .iCloudPhotosState) ?? .unknown
        manualICloudQuota = try container.decodeIfPresent(ManualICloudQuota.self, forKey: .manualICloudQuota)
        wifiOnlyDownloads = try container.decodeIfPresent(Bool.self, forKey: .wifiOnlyDownloads) ?? true
        allowCloudDownloadsForAnalysis = try container.decodeIfPresent(Bool.self, forKey: .allowCloudDownloadsForAnalysis) ?? false
        pauseOnLowBattery = try container.decodeIfPresent(Bool.self, forKey: .pauseOnLowBattery) ?? true
        includeHiddenAssets = try container.decodeIfPresent(Bool.self, forKey: .includeHiddenAssets) ?? false
        quickSessionSize = try container.decodeIfPresent(Int.self, forKey: .quickSessionSize) ?? 50
        largeVideoThresholdMB = try container.decodeIfPresent(Int.self, forKey: .largeVideoThresholdMB) ?? 100
        autoplayVideos = try container.decodeIfPresent(Bool.self, forKey: .autoplayVideos) ?? true
        reminderFrequency = try container.decodeIfPresent(ReminderFrequency.self, forKey: .reminderFrequency) ?? .off
        protection = try container.decodeIfPresent(ProtectionRules.self, forKey: .protection) ?? ProtectionRules()
        transcriptionLocaleIdentifier = try container.decodeIfPresent(String.self, forKey: .transcriptionLocaleIdentifier) ?? "it-IT"
        lastScanCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastScanCompletedAt)
        developerTier = try container.decodeIfPresent(PlanTier.self, forKey: .developerTier)
    }

    var largeVideoBytes: Int64 {
        Int64(max(1, largeVideoThresholdMB)) * AppConfiguration.Thresholds.megabyte
    }
}

/// Cartella a cui l'utente ha concesso l'accesso tramite il selettore di sistema.
struct AuthorizedFolder: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// Segnalibro con ambito di sicurezza: permette di riaprire la cartella ai successivi avvii.
    var bookmark: Data
    var addedAt: Date
    var lastScanAt: Date?
    var isICloud: Bool
    var itemCount: Int
    var totalBytes: Int64

    init(id: UUID = UUID(), name: String, bookmark: Data, isICloud: Bool, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.addedAt = addedAt
        self.lastScanAt = nil
        self.isICloud = isICloud
        self.itemCount = 0
        self.totalBytes = 0
    }
}
