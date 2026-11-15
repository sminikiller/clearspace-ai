import Foundation
import Photos

/// Modo in cui un file è stato rimosso.
enum FileRemovalKind: Sendable {
    /// Spostato nel cestino del provider ("Eliminati di recente"): l'operazione è reversibile.
    case movedToTrash
    case deletedPermanently
}

enum FileOperationError: Error {
    /// Il provider non offre un cestino: l'eliminazione sarebbe definitiva e richiede un consenso esplicito.
    case trashUnsupported
    case notUbiquitous
    case notUploaded
    case verificationFailed
    case unavailable
    case underlying(String)

    var message: String {
        switch self {
        case .trashUnsupported:
            return "Questa posizione non supporta il cestino: il file può essere eliminato solo in modo definitivo."
        case .notUbiquitous:
            return "Il file non si trova in iCloud Drive: non esiste una copia online da conservare."
        case .notUploaded:
            return "Il file non è ancora stato caricato su iCloud: la copia locale è l'unica esistente."
        case .verificationFailed:
            return "La copia non corrisponde all'originale ed è stata scartata."
        case .unavailable:
            return "L'elemento non è più disponibile."
        case .underlying(let reason):
            return reason
        }
    }
}

/// Operazioni sui file delle cartelle autorizzate. Sono tre azioni distinte, con effetti diversi:
/// liberare la sola copia locale, eliminare il file, organizzare (spostare o rinominare).
/// L'eliminazione va invocata esclusivamente dal `SafetyEngine`, dopo revisione e conferma.
struct FileOperationService: Sendable {

    // MARK: - Eliminazione

    /// Elimina un file. Prova sempre prima il cestino del provider; l'eliminazione definitiva
    /// avviene solo se `allowPermanent` è vero.
    func remove(at url: URL, allowPermanent: Bool) async throws -> FileRemovalKind {
        try await Task.detached(priority: .userInitiated) {
            try Self.removeCoordinated(at: url, allowPermanent: allowPermanent)
        }.value
    }

    private static func removeCoordinated(at url: URL, allowPermanent: Bool) throws -> FileRemovalKind {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileOperationError.unavailable
        }
        var coordinationError: NSError?
        var outcome: Result<FileRemovalKind, Error> = .failure(FileOperationError.underlying("Operazione non eseguita."))
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
                outcome = .success(.movedToTrash)
            } catch {
                guard allowPermanent else {
                    outcome = .failure(FileOperationError.trashUnsupported)
                    return
                }
                do {
                    try FileManager.default.removeItem(at: target)
                    outcome = .success(.deletedPermanently)
                } catch {
                    outcome = .failure(FileOperationError.underlying(error.localizedDescription))
                }
            }
        }
        if let coordinationError {
            throw FileOperationError.underlying(coordinationError.localizedDescription)
        }
        return try outcome.get()
    }

    // MARK: - Copia locale di iCloud Drive

    /// Rimuove la sola copia scaricata di un file di iCloud Drive: il documento resta disponibile online.
    /// Rifiuta l'operazione se il file non è ancora stato caricato, per non perdere l'unica copia.
    func evictLocalCopy(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) { () throws -> Void in
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey])
            guard values.isUbiquitousItem == true else { throw FileOperationError.notUbiquitous }
            guard values.ubiquitousItemIsUploaded == true else { throw FileOperationError.notUploaded }
            try FileManager.default.evictUbiquitousItem(at: url)
        }.value
    }

    /// Avvia il download di un file presente solo su iCloud Drive.
    func startDownload(at url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - Organizzazione

    /// Sposta o rinomina un file, creando la cartella di destinazione se manca.
    func move(from source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) { () throws -> Void in
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw FileOperationError.underlying("Esiste già un file con lo stesso nome nella destinazione.")
            }
            var coordinationError: NSError?
            var failure: Error?
            NSFileCoordinator().coordinate(
                writingItemAt: source,
                options: .forMoving,
                writingItemAt: destination,
                options: .forReplacing,
                error: &coordinationError
            ) { from, to in
                do {
                    try FileManager.default.createDirectory(
                        at: to.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try FileManager.default.moveItem(at: from, to: to)
                } catch {
                    failure = error
                }
            }
            if let coordinationError {
                throw FileOperationError.underlying(coordinationError.localizedDescription)
            }
            if let failure {
                throw FileOperationError.underlying(failure.localizedDescription)
            }
        }.value
    }

    // MARK: - Archiviazione guidata

    private static func uniqueDestination(in directory: URL, filename: String) -> URL {
        let name = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        var destination = directory.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            counter += 1
            let candidate = fileExtension.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(fileExtension)"
            destination = directory.appendingPathComponent(candidate)
        }
        return destination
    }

    /// Copia un file in una cartella scelta dall'utente e verifica con SHA-256 che la copia sia identica.
    func copyVerified(from source: URL, to directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) { () throws -> URL in
            let accessing = directory.startAccessingSecurityScopedResource()
            defer {
                if accessing { directory.stopAccessingSecurityScopedResource() }
            }
            let destination = Self.uniqueDestination(in: directory, filename: source.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                let original = try FileHasher.sha256(ofFileAt: source)
                let copy = try FileHasher.sha256(ofFileAt: destination)
                guard original == copy else {
                    try? FileManager.default.removeItem(at: destination)
                    throw FileOperationError.verificationFailed
                }
            } catch let error as FileOperationError {
                throw error
            } catch {
                throw FileOperationError.underlying(error.localizedDescription)
            }
            return destination
        }.value
    }

    /// Esporta gli originali di un asset della libreria Foto in una cartella scelta dall'utente
    /// e verifica che ogni file scritto corrisponda al contenuto di partenza.
    func exportLibraryAsset(identifier: String, to directory: URL, allowNetwork: Bool) async throws -> [URL] {
        guard let asset = PhotoLibraryService.asset(identifier) else {
            throw FileOperationError.unavailable
        }
        let wanted: Set<PHAssetResourceType> = [
            .photo, .video, .pairedVideo, .alternatePhoto, .fullSizePhoto, .fullSizeVideo, .fullSizePairedVideo
        ]
        let resources = PHAssetResource.assetResources(for: asset).filter { wanted.contains($0.type) }
        guard !resources.isEmpty else {
            throw FileOperationError.unavailable
        }

        let accessing = directory.startAccessingSecurityScopedResource()
        defer {
            if accessing { directory.stopAccessingSecurityScopedResource() }
        }

        var written: [URL] = []
        for resource in resources {
            let destination = Self.uniqueDestination(in: directory, filename: resource.originalFilename)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = allowNetwork
            do {
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options)
            } catch {
                throw FileOperationError.underlying(error.localizedDescription)
            }
            let expected = await FileHasher.sha256(of: resource, allowNetwork: allowNetwork)
            let actual = try? FileHasher.sha256(ofFileAt: destination)
            guard let expected, expected == actual else {
                try? FileManager.default.removeItem(at: destination)
                throw FileOperationError.verificationFailed
            }
            written.append(destination)
        }
        return written
    }
}
