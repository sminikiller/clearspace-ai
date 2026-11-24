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

/// Soglie con cui due scatti vengono considerati simili.
struct SimilarityThresholds: Equatable, Sendable {
    /// Distanza massima tra le impronte visive di Vision (0 = immagini identiche).
    var featureDistance: Float
    /// Distanza massima tra due screenshot: le schermate si somigliano molto anche quando sono diverse.
    var screenshotDistance: Float
    /// Due scatti vengono confrontati solo se fatti entro questo intervallo l'uno dall'altro.
    var timeWindow: TimeInterval
    /// Bit di differenza tra impronte percettive, usati quando l'impronta di Vision manca.
    var hashDistance: Int

    static let standard = SimilarityThresholds(
        featureDistance: AppConfiguration.Thresholds.similarFeatureDistance,
        screenshotDistance: AppConfiguration.Thresholds.similarScreenshotDistance,
        timeWindow: AppConfiguration.Thresholds.similarTimeWindow,
        hashDistance: AppConfiguration.Thresholds.similarHashDistance
    )
}

/// Quanto devono somigliarsi due scatti per finire nello stesso gruppo di foto simili.
enum SimilaritySensitivity: String, Codable, CaseIterable, Sendable {
    /// Solo scatti quasi identici, fatti a breve distanza: gruppi più piccoli e più sicuri.
    case strict
    case standard
    /// Anche scatti con inquadrature un po' diverse e più distanti nel tempo: gruppi più grandi.
    case broad

    var title: String {
        switch self {
        case .strict: return "Rigorosa"
        case .standard: return "Normale"
        case .broad: return "Ampia"
        }
    }

    var detail: String {
        switch self {
        case .strict: return "Rigorosa: solo scatti quasi identici, fatti a pochi secondi di distanza. Gruppi più piccoli."
        case .standard: return "Normale: scatti dello stesso soggetto fatti entro pochi minuti. È l'impostazione consigliata."
        case .broad: return "Ampia: anche scatti con inquadrature un po' diverse o fatti a qualche minuto di distanza. Gruppi più grandi, da controllare con più attenzione."
        }
    }

    var thresholds: SimilarityThresholds {
        let standard = SimilarityThresholds.standard
        switch self {
        case .strict:
            return SimilarityThresholds(
                featureDistance: standard.featureDistance * 0.76,
                screenshotDistance: standard.screenshotDistance * 0.72,
                timeWindow: standard.timeWindow / 2,
                hashDistance: max(1, standard.hashDistance - 3)
            )
        case .standard:
            return standard
        case .broad:
            return SimilarityThresholds(
                featureDistance: standard.featureDistance * 1.24,
                screenshotDistance: standard.screenshotDistance * 1.28,
                timeWindow: standard.timeWindow * 2,
                hashDistance: standard.hashDistance + 3
            )
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
    /// Ultima build di cui l'utente ha visto le novità. Serve a mostrarle una volta dopo ogni aggiornamento.
    var lastSeenBuild: String?
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
    /// La foto che si sta esaminando (confronto, tutto schermo) si scarica nitida anche con la rete
    /// cellulare. Le altre anteprime rispettano `wifiOnlyDownloads`.
    var sharpPreviewsOnCellular = true
    /// Quanto devono somigliarsi due scatti per formare un gruppo di foto simili.
    var similaritySensitivity: SimilaritySensitivity = .standard
    var reminderFrequency: ReminderFrequency = .off
    var protection = ProtectionRules()
    var transcriptionLocaleIdentifier = "it-IT"
    var lastScanCompletedAt: Date?
    /// Versione dei criteri di scelta dello scatto migliore già applicata ai gruppi esistenti.
    var shotRankingVersion = 0
    /// Solo per provare i piani durante lo sviluppo.
    var developerTier: PlanTier?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        lastSeenBuild = try container.decodeIfPresent(String.self, forKey: .lastSeenBuild)
        iCloudPhotosState = try container.decodeIfPresent(ICloudPhotosState.self, forKey: .iCloudPhotosState) ?? .unknown
        manualICloudQuota = try container.decodeIfPresent(ManualICloudQuota.self, forKey: .manualICloudQuota)
        wifiOnlyDownloads = try container.decodeIfPresent(Bool.self, forKey: .wifiOnlyDownloads) ?? true
        allowCloudDownloadsForAnalysis = try container.decodeIfPresent(Bool.self, forKey: .allowCloudDownloadsForAnalysis) ?? false
        pauseOnLowBattery = try container.decodeIfPresent(Bool.self, forKey: .pauseOnLowBattery) ?? true
        includeHiddenAssets = try container.decodeIfPresent(Bool.self, forKey: .includeHiddenAssets) ?? false
        quickSessionSize = try container.decodeIfPresent(Int.self, forKey: .quickSessionSize) ?? 50
        largeVideoThresholdMB = try container.decodeIfPresent(Int.self, forKey: .largeVideoThresholdMB) ?? 100
        autoplayVideos = try container.decodeIfPresent(Bool.self, forKey: .autoplayVideos) ?? true
        sharpPreviewsOnCellular = try container.decodeIfPresent(Bool.self, forKey: .sharpPreviewsOnCellular) ?? true
        // Un valore sconosciuto (ad esempio salvato da una versione più recente) non deve far perdere
        // tutte le altre preferenze.
        similaritySensitivity = (try? container.decodeIfPresent(SimilaritySensitivity.self, forKey: .similaritySensitivity)) ?? .standard
        reminderFrequency = try container.decodeIfPresent(ReminderFrequency.self, forKey: .reminderFrequency) ?? .off
        protection = try container.decodeIfPresent(ProtectionRules.self, forKey: .protection) ?? ProtectionRules()
        transcriptionLocaleIdentifier = try container.decodeIfPresent(String.self, forKey: .transcriptionLocaleIdentifier) ?? "it-IT"
        lastScanCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastScanCompletedAt)
        shotRankingVersion = try container.decodeIfPresent(Int.self, forKey: .shotRankingVersion) ?? 0
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
