import Foundation
import Photos
import Observation

struct AlbumInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
}

/// Esito di una richiesta di eliminazione dalla libreria Foto.
enum LibraryDeletionResult {
    /// La modifica è stata applicata: `deleted` sono gli asset realmente rimossi (verificati),
    /// `alreadyMissing` quelli che non esistevano più, `failed` quelli rimasti con il relativo motivo.
    case completed(deleted: Set<String>, alreadyMissing: Set<String>, failed: [String: String])
    /// L'utente ha rifiutato la conferma di sistema: nulla è stato eliminato.
    case declinedBySystemDialog
    case failed(String)
}

private final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}

/// Accesso alla libreria Foto tramite PhotoKit: permessi, album, ricerca ed eliminazione degli asset.
/// PhotoKit gestisce sia i contenuti presenti sul dispositivo sia quelli di Foto di iCloud.
@MainActor
@Observable
final class PhotoLibraryService {

    private(set) var authorization: PHAuthorizationStatus
    /// Aumenta quando la libreria cambia: segnala che serve una scansione incrementale.
    private(set) var libraryChangeCount = 0

    @ObservationIgnored private var observer: LibraryChangeObserver?

    init() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        startObservingIfPossible()
    }

    var canRead: Bool {
        authorization == .authorized || authorization == .limited
    }

    var isLimited: Bool { authorization == .limited }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    var statusDescription: String {
        switch authorization {
        case .authorized: return "Accesso completo"
        case .limited: return "Accesso limitato alle foto selezionate"
        case .denied: return "Accesso negato"
        case .restricted: return "Accesso non consentito su questo dispositivo"
        case .notDetermined: return "Accesso non ancora richiesto"
        @unknown default: return "Stato sconosciuto"
        }
    }

    /// Rilegge lo stato del permesso: l'utente può revocarlo in qualsiasi momento dalle Impostazioni.
    func refreshAuthorization() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != authorization {
            authorization = current
        }
        startObservingIfPossible()
    }

    @discardableResult
    func requestAccess() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorization = status
        startObservingIfPossible()
        return status
    }

    private func startObservingIfPossible() {
        guard canRead, observer == nil else { return }
        let newObserver = LibraryChangeObserver { [weak self] in
            Task { @MainActor in
                self?.libraryChangeCount += 1
            }
        }
        PHPhotoLibrary.shared().register(newObserver)
        observer = newObserver
    }

    // MARK: - Album

    func userAlbums() -> [AlbumInfo] {
        guard canRead else { return [] }
        var result: [AlbumInfo] = []
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        for index in 0..<collections.count {
            let collection = collections.object(at: index)
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            result.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Album",
                count: count
            ))
        }
        return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Identificativi degli asset contenuti negli album indicati (per gli album protetti).
    nonisolated static func memberIdentifiers(ofAlbums albumIDs: Set<String>) -> Set<String> {
        guard !albumIDs.isEmpty else { return [] }
        var result = Set<String>()
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: Array(albumIDs),
            options: nil
        )
        for index in 0..<collections.count {
            let assets = PHAsset.fetchAssets(in: collections.object(at: index), options: lookupOptions())
            for assetIndex in 0..<assets.count {
                result.insert(assets.object(at: assetIndex).localIdentifier)
            }
        }
        return result
    }

    // MARK: - Ricerca degli asset

    /// Opzioni per ritrovare un asset preciso: includono nascosti e singoli scatti delle raffiche.
    nonisolated static func lookupOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        return options
    }

    nonisolated static func asset(_ identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: lookupOptions()).firstObject
    }

    nonisolated static func assets(_ identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: lookupOptions())
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        for index in 0..<result.count {
            assets.append(result.object(at: index))
        }
        return assets
    }

    // MARK: - Eliminazione

    /// Sposta gli asset in "Eliminati di recente". iOS mostra sempre la propria richiesta di conferma.
    /// Va chiamato esclusivamente dal `SafetyEngine`, dopo revisione e conferma dell'utente.
    func deleteAssets(identifiers: [String]) async -> LibraryDeletionResult {
        guard canRead else {
            return .failed("L'accesso alla libreria Foto non è autorizzato.")
        }
        let found = Self.assets(identifiers)
        let foundIDs = Set(found.map { $0.localIdentifier })
        let alreadyMissing = Set(identifiers).subtracting(foundIDs)

        var failures: [String: String] = [:]
        var deletable: [PHAsset] = []
        for asset in found {
            if asset.canPerform(.delete) {
                deletable.append(asset)
            } else {
                failures[asset.localIdentifier] = "iOS non consente di eliminare questo elemento (ad esempio perché sincronizzato da un computer)."
            }
        }

        guard !deletable.isEmpty else {
            return .completed(deleted: [], alreadyMissing: alreadyMissing, failed: failures)
        }

        let toDelete = deletable as NSArray
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(toDelete)
            }
        } catch {
            if let photosError = error as? PHPhotosError, photosError.code == .userCancelled {
                return .declinedBySystemDialog
            }
            return .failed(error.localizedDescription)
        }

        // Verifica: un asset è considerato eliminato solo se non è più nella libreria.
        let requested = deletable.map { $0.localIdentifier }
        let remaining = Set(Self.assets(requested).map { $0.localIdentifier })
        var deleted = Set<String>()
        for identifier in requested {
            if remaining.contains(identifier) {
                failures[identifier] = "L'elemento risulta ancora presente nella libreria."
            } else {
                deleted.insert(identifier)
            }
        }
        return .completed(deleted: deleted, alreadyMissing: alreadyMissing, failed: failures)
    }
}
