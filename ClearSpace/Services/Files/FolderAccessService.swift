import Foundation
import Observation

private let foldersFileName = "folders.v1.bin"

enum FolderAccessError: Error {
    case alreadyAdded
    case bookmarkFailed
    case importFailed(String)

    var message: String {
        switch self {
        case .alreadyAdded: return "Questa cartella è già stata aggiunta."
        case .bookmarkFailed: return "Non è stato possibile salvare l'accesso alla cartella."
        case .importFailed(let reason): return "Importazione non riuscita: \(reason)"
        }
    }
}

/// Cartelle a cui l'utente ha concesso l'accesso con il selettore di sistema.
/// L'accesso viene conservato tramite segnalibri con ambito di sicurezza e può essere revocato
/// in qualsiasi momento rimuovendo la cartella dall'elenco.
@MainActor
@Observable
final class FolderAccessService {

    private(set) var folders: [AuthorizedFolder] = []

    @ObservationIgnored private var resolved: [UUID: URL] = [:]

    private let files: SecureFileStore
    /// Cartella interna in cui finiscono i file importati in ClearSpace (es. memo vocali condivisi).
    let importsDirectory: URL

    init(files: SecureFileStore = SecureFileStore()) {
        self.files = files
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var directory = base.appendingPathComponent("ClearSpaceImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        self.importsDirectory = directory
    }

    func load() async {
        let files = self.files
        let loaded = await Task.detached(priority: .userInitiated) {
            files.load([AuthorizedFolder].self, from: foldersFileName)
        }.value
        if let loaded {
            folders = loaded
        }
    }

    private func persist() {
        let snapshot = folders
        let files = self.files
        Task.detached(priority: .utility) {
            try? files.save(snapshot, as: foldersFileName)
        }
    }

    func folder(_ id: UUID) -> AuthorizedFolder? {
        folders.first { $0.id == id }
    }

    // MARK: - Aggiunta e rimozione

    /// Registra una cartella scelta dall'utente e ne conserva l'accesso per i prossimi avvii.
    @discardableResult
    func addFolder(at url: URL) throws -> AuthorizedFolder {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let path = url.standardizedFileURL.path
        for existing in folders {
            if resolvedURL(for: existing.id)?.standardizedFileURL.path == path {
                throw FolderAccessError.alreadyAdded
            }
        }

        guard let bookmark = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            throw FolderAccessError.bookmarkFailed
        }

        let isICloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem ?? false
        let folder = AuthorizedFolder(name: url.lastPathComponent, bookmark: bookmark, isICloud: isICloud)
        folders.append(folder)
        persist()
        return folder
    }

    /// Revoca l'accesso a una cartella. I file non vengono toccati.
    func removeFolder(_ id: UUID) {
        if let url = resolved.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
        folders.removeAll { $0.id == id }
        persist()
    }

    func updateStatistics(folderID: UUID, itemCount: Int, totalBytes: Int64, scannedAt: Date = Date()) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].itemCount = itemCount
        folders[index].totalBytes = totalBytes
        folders[index].lastScanAt = scannedAt
        persist()
    }

    // MARK: - Risoluzione degli indirizzi

    /// Riapre la cartella a partire dal segnalibro salvato. Restituisce `nil` se l'accesso non è più valido.
    func resolvedURL(for folderID: UUID) -> URL? {
        if let cached = resolved[folderID] {
            return cached
        }
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return nil }

        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: folders[index].bookmark, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        // L'accesso resta attivo finché la cartella è in elenco.
        _ = url.startAccessingSecurityScopedResource()

        if isStale, let renewed = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            folders[index].bookmark = renewed
            persist()
        }
        resolved[folderID] = url
        return url
    }

    /// Indirizzo del file corrispondente a un elemento dell'indice (non valido per la libreria Foto).
    func url(for item: IndexedItem) -> URL? {
        switch item.source {
        case .photoLibrary:
            return nil
        case .appImports:
            return importsDirectory.appendingPathComponent(item.sourceIdentifier)
        case .localFiles, .iCloudDrive:
            guard let folderID = item.folderID,
                  let root = resolvedURL(for: folderID),
                  let path = item.relativePath else {
                return nil
            }
            return root.appendingPathComponent(path)
        }
    }

    // MARK: - Importazione

    /// Copia un file nella cartella interna di ClearSpace. L'originale nell'app di origine non viene toccato.
    func importFile(from source: URL) throws -> URL {
        let accessing = source.startAccessingSecurityScopedResource()
        defer {
            if accessing { source.stopAccessingSecurityScopedResource() }
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        let fileExtension = source.pathExtension
        var destination = importsDirectory.appendingPathComponent(source.lastPathComponent)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            counter += 1
            let name = fileExtension.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(fileExtension)"
            destination = importsDirectory.appendingPathComponent(name)
        }

        do {
            // I file ricevuti con "Apri in ClearSpace" arrivano nella cartella Inbox dell'app: da lì vengono spostati.
            if source.path.contains("/Inbox/") {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            throw FolderAccessError.importFailed(error.localizedDescription)
        }
        return destination
    }
}
