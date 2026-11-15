import Foundation

/// Parametri che servono per valutare l'appartenenza a una categoria.
struct CollectionContext: Sendable {
    var now: Date
    var largeVideoBytes: Int64

    init(now: Date = Date(), largeVideoBytes: Int64 = 100 * AppConfiguration.Thresholds.megabyte) {
        self.now = now
        self.largeVideoBytes = largeVideoBytes
    }
}

enum CollectionSection: String, CaseIterable, Identifiable, Sendable {
    case photos
    case videos
    case documents
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: return "Foto"
        case .videos: return "Video"
        case .documents: return "Documenti e file"
        case .audio: return "Audio e registrazioni"
        }
    }

    var systemImage: String {
        switch self {
        case .photos: return "photo.on.rectangle.angled"
        case .videos: return "video"
        case .documents: return "doc.on.doc"
        case .audio: return "waveform"
        }
    }
}

/// Catalogo delle categorie esplorabili. Ogni categoria è un filtro sui contenuti indicizzati:
/// appartenere a una categoria non significa mai che l'elemento sia da eliminare.
enum SmartCollection: String, CaseIterable, Identifiable, Codable, Sendable {
    // Foto
    case allPhotos
    case screenshots
    case oldScreenshots
    case recentScreenshots
    case textScreenshots
    case conversationScreenshots
    case receiptScreenshots
    case qrCodes
    case duplicatePhotos
    case similarPhotos
    case blurryPhotos
    case darkPhotos
    case lowResolutionPhotos
    case heavyPhotos
    case selfies
    case portraits
    case panoramas
    case livePhotos
    case bursts
    case savedFromApps
    case photosWithText
    case photographedDocuments
    case alreadyKept
    // Video
    case allVideos
    case largeVideos
    case veryLargeVideos
    case hugeVideos
    case longVideos
    case screenRecordings
    case video4K
    case highFrameRateVideos
    case duplicateVideos
    case similarVideos
    case oldVideos
    // Documenti e file
    case allFiles
    case pdfs
    case officeDocuments
    case archives
    case downloads
    case mediaFiles
    case unknownFiles
    case largeFiles
    case oldFiles
    case duplicateFiles
    case documentVersions
    case cloudOnlyFiles
    case downloadedCloudFiles
    // Audio
    case allAudio
    case longAudio
    case silentAudio
    case duplicateAudio
    case similarAudio

    var id: String { rawValue }

    var section: CollectionSection {
        switch self {
        case .allPhotos, .screenshots, .oldScreenshots, .recentScreenshots, .textScreenshots,
             .conversationScreenshots, .receiptScreenshots, .qrCodes, .duplicatePhotos, .similarPhotos,
             .blurryPhotos, .darkPhotos, .lowResolutionPhotos, .heavyPhotos, .selfies, .portraits,
             .panoramas, .livePhotos, .bursts, .savedFromApps, .photosWithText, .photographedDocuments,
             .alreadyKept:
            return .photos
        case .allVideos, .largeVideos, .veryLargeVideos, .hugeVideos, .longVideos, .screenRecordings,
             .video4K, .highFrameRateVideos, .duplicateVideos, .similarVideos, .oldVideos:
            return .videos
        case .allFiles, .pdfs, .officeDocuments, .archives, .downloads, .mediaFiles, .unknownFiles,
             .largeFiles, .oldFiles, .duplicateFiles, .documentVersions, .cloudOnlyFiles,
             .downloadedCloudFiles:
            return .documents
        case .allAudio, .longAudio, .silentAudio, .duplicateAudio, .similarAudio:
            return .audio
        }
    }

    var title: String {
        switch self {
        case .allPhotos: return "Tutte le foto"
        case .screenshots: return "Screenshot"
        case .oldScreenshots: return "Screenshot vecchi"
        case .recentScreenshots: return "Screenshot recenti"
        case .textScreenshots: return "Screenshot con testo"
        case .conversationScreenshots: return "Schermate di conversazioni"
        case .receiptScreenshots: return "Ricevute e biglietti"
        case .qrCodes: return "Codici QR"
        case .duplicatePhotos: return "Foto duplicate"
        case .similarPhotos: return "Foto simili"
        case .blurryPhotos: return "Foto sfocate"
        case .darkPhotos: return "Foto scure o vuote"
        case .lowResolutionPhotos: return "Bassa risoluzione"
        case .heavyPhotos: return "Pesanti per la risoluzione"
        case .selfies: return "Selfie"
        case .portraits: return "Ritratti"
        case .panoramas: return "Panoramiche"
        case .livePhotos: return "Live Photo"
        case .bursts: return "Raffiche"
        case .savedFromApps: return "Salvate da altre app"
        case .photosWithText: return "Immagini con testo"
        case .photographedDocuments: return "Documenti fotografati"
        case .alreadyKept: return "Già conservate"
        case .allVideos: return "Tutti i video"
        case .largeVideos: return "Video grandi"
        case .veryLargeVideos: return "Video oltre 500 MB"
        case .hugeVideos: return "Video oltre 1 GB"
        case .longVideos: return "Video lunghi"
        case .screenRecordings: return "Registrazioni schermo"
        case .video4K: return "Video 4K"
        case .highFrameRateVideos: return "Alto frame rate"
        case .duplicateVideos: return "Video duplicati"
        case .similarVideos: return "Video simili"
        case .oldVideos: return "Video vecchi"
        case .allFiles: return "Tutti i file"
        case .pdfs: return "PDF"
        case .officeDocuments: return "Word, Excel, PowerPoint"
        case .archives: return "ZIP, RAR e archivi"
        case .downloads: return "Download"
        case .mediaFiles: return "Immagini e video nei file"
        case .unknownFiles: return "File sconosciuti"
        case .largeFiles: return "File pesanti"
        case .oldFiles: return "File vecchi"
        case .duplicateFiles: return "File duplicati"
        case .documentVersions: return "Versioni dello stesso documento"
        case .cloudOnlyFiles: return "Solo su iCloud Drive"
        case .downloadedCloudFiles: return "Copie locali di iCloud Drive"
        case .allAudio: return "Tutti gli audio"
        case .longAudio: return "Registrazioni lunghe"
        case .silentAudio: return "Con silenzi lunghi"
        case .duplicateAudio: return "Audio identici"
        case .similarAudio: return "Registrazioni simili"
        }
    }

    var subtitle: String {
        switch self {
        case .allPhotos: return "L'intera libreria fotografica"
        case .screenshots: return "Tutte le schermate catturate"
        case .oldScreenshots: return "Catturati più di un anno fa"
        case .recentScreenshots: return "Catturati nell'ultimo anno"
        case .textScreenshots: return "Schermate che contengono testo"
        case .conversationScreenshots: return "Chat e messaggi"
        case .receiptScreenshots: return "Da controllare con attenzione"
        case .qrCodes: return "Immagini che contengono un codice QR"
        case .duplicatePhotos: return "Copie identiche o visivamente uguali"
        case .similarPhotos: return "Raffiche e scatti dello stesso soggetto"
        case .blurryPhotos: return "Possibile mosso o messa a fuoco scarsa"
        case .darkPhotos: return "Esposizione molto insufficiente"
        case .lowResolutionPhotos: return "Meno di 0,5 megapixel"
        case .heavyPhotos: return "File grandi rispetto ai pixel"
        case .selfies: return "Scatti con la fotocamera frontale"
        case .portraits: return "Foto con effetto profondità"
        case .panoramas: return "Scatti panoramici"
        case .livePhotos: return "Foto con video incluso"
        case .bursts: return "Sequenze di scatti rapidi"
        case .savedFromApps: return "Stima basata sul nome del file"
        case .photosWithText: return "Foto in cui è stato riconosciuto testo"
        case .photographedDocuments: return "Pagine, ricevute e biglietti"
        case .alreadyKept: return "Elementi che hai già deciso di tenere"
        case .allVideos: return "Tutti i video della libreria"
        case .largeVideos: return "Sopra la soglia che hai scelto"
        case .veryLargeVideos: return "I più ingombranti"
        case .hugeVideos: return "Occupano più di 1 GB ciascuno"
        case .longVideos: return "Più di tre minuti"
        case .screenRecordings: return "Riprese dello schermo"
        case .video4K: return "Registrati in 4K"
        case .highFrameRateVideos: return "Slow motion e 60 fps o più"
        case .duplicateVideos: return "Copie identiche"
        case .similarVideos: return "Possibili versioni dello stesso video"
        case .oldVideos: return "Registrati più di due anni fa"
        case .allFiles: return "Nelle cartelle che hai autorizzato"
        case .pdfs: return "Documenti PDF"
        case .officeDocuments: return "Documenti, fogli e presentazioni"
        case .archives: return "Archivi compressi"
        case .downloads: return "File nelle cartelle Download"
        case .mediaFiles: return "Possibili copie di foto e video"
        case .unknownFiles: return "Formato non riconosciuto"
        case .largeFiles: return "Più di 50 MB"
        case .oldFiles: return "Non modificati da più di due anni"
        case .duplicateFiles: return "Stesso contenuto, verificato"
        case .documentVersions: return "Testo quasi identico o nomi simili"
        case .cloudOnlyFiles: return "Non occupano spazio sull'iPhone"
        case .downloadedCloudFiles: return "Si può liberare la copia locale"
        case .allAudio: return "File audio accessibili o importati"
        case .longAudio: return "Più di dieci minuti"
        case .silentAudio: return "Pause prolungate rilevate"
        case .duplicateAudio: return "Stesso contenuto, verificato"
        case .similarAudio: return "Durata e andamento simili"
        }
    }

    var systemImage: String {
        switch self {
        case .allPhotos: return "photo.on.rectangle"
        case .screenshots, .oldScreenshots, .recentScreenshots: return "camera.viewfinder"
        case .textScreenshots, .photosWithText: return "text.viewfinder"
        case .conversationScreenshots: return "bubble.left.and.bubble.right"
        case .receiptScreenshots: return "doc.plaintext"
        case .qrCodes: return "qrcode"
        case .duplicatePhotos, .duplicateVideos, .duplicateFiles, .duplicateAudio: return "square.on.square"
        case .similarPhotos, .similarVideos, .similarAudio: return "square.stack.3d.down.right"
        case .blurryPhotos: return "camera.metering.unknown"
        case .darkPhotos: return "moon"
        case .lowResolutionPhotos: return "rectangle.compress.vertical"
        case .heavyPhotos, .largeFiles: return "scalemass"
        case .selfies: return "person.crop.square"
        case .portraits: return "person.crop.rectangle"
        case .panoramas: return "pano"
        case .livePhotos: return "livephoto"
        case .bursts: return "square.stack.3d.up"
        case .savedFromApps: return "square.and.arrow.down"
        case .photographedDocuments: return "doc.viewfinder"
        case .alreadyKept: return "checkmark.seal"
        case .allVideos: return "video"
        case .largeVideos, .veryLargeVideos, .hugeVideos: return "externaldrive"
        case .longVideos, .longAudio: return "timer"
        case .screenRecordings: return "record.circle"
        case .video4K: return "4k.tv"
        case .highFrameRateVideos: return "slowmo"
        case .oldVideos, .oldFiles: return "clock.arrow.circlepath"
        case .allFiles: return "folder"
        case .pdfs: return "doc.richtext"
        case .officeDocuments: return "doc.text"
        case .archives: return "doc.zipper"
        case .downloads: return "arrow.down.circle"
        case .mediaFiles: return "photo.stack"
        case .unknownFiles: return "questionmark.folder"
        case .documentVersions: return "doc.on.doc"
        case .cloudOnlyFiles: return "icloud"
        case .downloadedCloudFiles: return "icloud.and.arrow.down"
        case .allAudio: return "waveform"
        case .silentAudio: return "speaker.slash"
        }
    }

    /// Funzione a piano richiesta, se la categoria non appartiene al piano gratuito.
    var requiredFeature: Feature? {
        switch self {
        case .duplicatePhotos, .duplicateVideos:
            return .exactDuplicates
        case .similarPhotos, .similarVideos:
            return .similarPhotos
        case .textScreenshots, .conversationScreenshots, .receiptScreenshots, .qrCodes,
             .photosWithText, .photographedDocuments:
            return .ocrClassification
        case .documentVersions:
            return .similarDocuments
        case .allFiles, .pdfs, .officeDocuments, .archives, .downloads, .mediaFiles, .unknownFiles,
             .largeFiles, .oldFiles, .duplicateFiles, .cloudOnlyFiles, .downloadedCloudFiles:
            return .documents
        case .allAudio, .longAudio, .silentAudio, .duplicateAudio, .similarAudio:
            return .audioTools
        default:
            return nil
        }
    }

    /// Le categorie a gruppi mostrano i confronti affiancati invece di una griglia semplice.
    var isGroupBased: Bool {
        switch self {
        case .duplicatePhotos, .similarPhotos, .duplicateVideos, .similarVideos,
             .duplicateFiles, .documentVersions, .duplicateAudio, .similarAudio:
            return true
        default:
            return false
        }
    }

    /// Vero se i gruppi della categoria sono duplicati (e non semplici somiglianze).
    var usesDuplicateGroups: Bool {
        switch self {
        case .duplicatePhotos, .duplicateVideos, .duplicateFiles, .duplicateAudio: return true
        default: return false
        }
    }

    func contains(_ item: IndexedItem, context: CollectionContext) -> Bool {
        let traits = item.traits
        let isLibraryPhoto = item.source == .photoLibrary && item.category == .photo
        let isLibraryVideo = item.source == .photoLibrary && item.category == .video
        let isFolderFile = item.source == .localFiles || item.source == .iCloudDrive
        let isAudio = item.category == .audio && item.source.isFileBased
        let megabyte = AppConfiguration.Thresholds.megabyte

        switch self {
        // Foto
        case .allPhotos:
            return isLibraryPhoto
        case .screenshots:
            return isLibraryPhoto && traits.contains(.screenshot)
        case .oldScreenshots:
            guard isLibraryPhoto, traits.contains(.screenshot), let age = item.age(at: context.now) else { return false }
            return age > AppConfiguration.Thresholds.oldScreenshotAge
        case .recentScreenshots:
            guard isLibraryPhoto, traits.contains(.screenshot) else { return false }
            guard let age = item.age(at: context.now) else { return true }
            return age <= AppConfiguration.Thresholds.oldScreenshotAge
        case .textScreenshots:
            return isLibraryPhoto && traits.isSuperset(of: [.screenshot, .hasText])
        case .conversationScreenshots:
            return isLibraryPhoto && traits.isSuperset(of: [.screenshot, .conversation])
        case .receiptScreenshots:
            return isLibraryPhoto && traits.contains(.screenshot)
                && !traits.isDisjoint(with: [.receipt, .ticket])
        case .qrCodes:
            return isLibraryPhoto && traits.contains(.qrCode)
        case .duplicatePhotos:
            return isLibraryPhoto && item.duplicateGroupID != nil
        case .similarPhotos:
            return isLibraryPhoto && item.similarityGroupID != nil
        case .blurryPhotos:
            return isLibraryPhoto && traits.contains(.blurry)
        case .darkPhotos:
            return isLibraryPhoto && !traits.isDisjoint(with: [.dark, .blank])
        case .lowResolutionPhotos:
            return isLibraryPhoto && traits.contains(.lowResolution)
        case .heavyPhotos:
            return isLibraryPhoto && traits.contains(.heavyForResolution)
        case .selfies:
            return isLibraryPhoto && traits.contains(.selfie)
        case .portraits:
            return isLibraryPhoto && traits.contains(.portrait)
        case .panoramas:
            return isLibraryPhoto && traits.contains(.panorama)
        case .livePhotos:
            return isLibraryPhoto && traits.contains(.livePhoto)
        case .bursts:
            return isLibraryPhoto && traits.contains(.burst)
        case .savedFromApps:
            return isLibraryPhoto && traits.contains(.fromOtherApp) && !traits.contains(.screenshot)
        case .photosWithText:
            return isLibraryPhoto && traits.contains(.hasText) && !traits.contains(.screenshot)
        case .photographedDocuments:
            return isLibraryPhoto && !traits.contains(.screenshot)
                && !traits.isDisjoint(with: [.documentLike, .receipt, .ticket])
        case .alreadyKept:
            return item.source == .photoLibrary && item.reviewStatus == .kept

        // Video
        case .allVideos:
            return isLibraryVideo
        case .largeVideos:
            return isLibraryVideo && item.bytes >= context.largeVideoBytes
        case .veryLargeVideos:
            return isLibraryVideo && item.bytes >= 500 * megabyte
        case .hugeVideos:
            return isLibraryVideo && item.bytes >= AppConfiguration.Thresholds.gigabyte
        case .longVideos:
            return isLibraryVideo && item.duration >= AppConfiguration.Thresholds.longVideoDuration
        case .screenRecordings:
            return isLibraryVideo && traits.contains(.screenRecording)
        case .video4K:
            return isLibraryVideo && traits.contains(.video4K)
        case .highFrameRateVideos:
            return isLibraryVideo && !traits.isDisjoint(with: [.highFrameRate, .slowMotion])
        case .duplicateVideos:
            return isLibraryVideo && item.duplicateGroupID != nil
        case .similarVideos:
            return isLibraryVideo && item.similarityGroupID != nil
        case .oldVideos:
            guard isLibraryVideo, let age = item.age(at: context.now) else { return false }
            return age > AppConfiguration.Thresholds.oldContentAge

        // Documenti e file
        case .allFiles:
            return isFolderFile && item.category != .audio
        case .pdfs:
            return isFolderFile && item.category == .pdf
        case .officeDocuments:
            return isFolderFile && item.category == .office
        case .archives:
            return isFolderFile && item.category == .archive
        case .downloads:
            return isFolderFile && traits.contains(.download)
        case .mediaFiles:
            return isFolderFile && (item.category == .photo || item.category == .video)
        case .unknownFiles:
            return isFolderFile && item.category == .unknown
        case .largeFiles:
            return isFolderFile && item.category != .audio
                && item.bytes >= AppConfiguration.Thresholds.largeFileBytes
        case .oldFiles:
            guard isFolderFile, item.category != .audio, let modified = item.modifiedAt ?? item.createdAt else {
                return false
            }
            return context.now.timeIntervalSince(modified) > AppConfiguration.Thresholds.oldContentAge
        case .duplicateFiles:
            return isFolderFile && item.category != .audio && item.duplicateGroupID != nil
        case .documentVersions:
            return isFolderFile && item.category.isDocument && item.similarityGroupID != nil
        case .cloudOnlyFiles:
            return item.source == .iCloudDrive && traits.contains(.cloudOnly)
        case .downloadedCloudFiles:
            return item.source == .iCloudDrive && !traits.contains(.cloudOnly)

        // Audio
        case .allAudio:
            return isAudio
        case .longAudio:
            return isAudio && item.duration >= AppConfiguration.Thresholds.longAudioDuration
        case .silentAudio:
            return isAudio && traits.contains(.longSilence)
        case .duplicateAudio:
            return isAudio && item.duplicateGroupID != nil
        case .similarAudio:
            return isAudio && item.similarityGroupID != nil
        }
    }

    static func collections(in section: CollectionSection) -> [SmartCollection] {
        allCases.filter { $0.section == section }
    }
}
