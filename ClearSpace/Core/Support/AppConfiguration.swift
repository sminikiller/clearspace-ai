import Foundation

/// Costanti di configurazione dell'app.
/// Le soglie sono punti di partenza ragionevoli e vanno tarate su librerie reali.
enum AppConfiguration {

    /// Versione delle analisi: aumentandola, gli elementi vengono rianalizzati alla scansione successiva.
    static let analysisVersion = 1

    /// Finché è `false` tutte le funzioni sono sbloccate e StoreKit non viene interrogato.
    /// Va attivato solo dopo aver configurato i prodotti in App Store Connect.
    static let monetizationEnabled = false

    /// Identificativi dei prodotti StoreKit (da creare in App Store Connect).
    static let proProductID = "clearspace.pro"
    static let proPlusProductID = "clearspace.proplus"

    /// Identificativo dell'attività in background; deve comparire in Info.plist.
    static var backgroundTaskIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "ClearSpace") + ".analysis"
    }

    enum Thresholds {
        /// Unità decimali, come quelle mostrate da iOS nelle Impostazioni.
        static let megabyte: Int64 = 1_000_000
        static let gigabyte: Int64 = 1_000_000_000

        /// Uno screenshot è considerato "vecchio" dopo un anno.
        static let oldScreenshotAge: TimeInterval = 365 * 86_400
        /// File e video "vecchi" dopo due anni. L'età non è mai una prova di inutilità.
        static let oldContentAge: TimeInterval = 2 * 365 * 86_400
        static let longVideoDuration: Double = 180
        static let longAudioDuration: Double = 600
        static let largeFileBytes: Int64 = 50 * megabyte

        /// Sotto mezzo megapixel un'immagine è a bassa risoluzione.
        static let lowResolutionPixels = 500_000
        /// Byte per pixel oltre i quali una foto è "pesante rispetto alla risoluzione".
        static let heavyBytesPerPixel = 1.2
        static let heavyBytesPerPixelLive = 2.0

        /// Finestra temporale entro cui due scatti consecutivi vengono confrontati.
        static let similarTimeWindow: TimeInterval = 180
        static let similarBucketLimit = 40
        /// Distanze tra feature print normalizzati di Vision (revisione 2): 0 = identiche.
        static let similarFeatureDistance: Float = 0.50
        static let similarScreenshotDistance: Float = 0.25
        static let duplicateFeatureDistance: Float = 0.12
        static let similarVideoDistance: Float = 0.35

        /// Varianza del laplaciano (miniatura da 512 px) sotto cui una foto è probabilmente sfocata.
        static let blurVariance = 60.0
        static let sharpVariance = 1_000.0
        static let darkBrightness = 0.10
        static let blankContrast = 0.02

        /// Silenzio considerato "lungo" in una registrazione audio.
        static let longSilence: Double = 5
        static let silenceLevel: Float = 0.006

        static let similarDocumentScore = 0.60
        static let similarAudioScore = 0.90
    }
}
