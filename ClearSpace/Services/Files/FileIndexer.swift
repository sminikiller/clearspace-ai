import Foundation
import UniformTypeIdentifiers

/// Fase A per i file: elenca in modo ricorsivo il contenuto delle cartelle autorizzate
/// leggendo soltanto i metadati. Nessun file viene aperto o scaricato.
actor FileIndexer {

    private static let officeExtensions: Set<String> = [
        "doc", "docx", "dot", "dotx", "xls", "xlsx", "xlsm", "csv", "ppt", "pptx", "pps", "ppsx",
        "pages", "numbers", "key", "odt", "ods", "odp", "rtf"
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso", "cab"
    ]

    private static let documentExtensions: Set<String> = [
        "txt", "md", "epub", "html", "htm", "xml", "json", "log", "ics", "vcf", "eml", "msg"
    ]

    private static let downloadFolderNames: Set<String> = ["downloads", "download", "scaricati"]

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
        .contentTypeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
    ]

    /// Numero massimo di file letti per cartella, a protezione di memoria e batteria.
    private static let maximumFiles = 150_000

    /// Indicizza una cartella. Restituisce gli identificativi incontrati, oppure `nil` se interrotta.
    func index(
        folder: AuthorizedFolder,
        root: URL,
        control: ScanControl,
        onBatch: @Sendable ([IndexedItem]) async -> Void
    ) async -> Set<String>? {
        let collected = Self.enumerate(folderID: folder.id, root: root)
        var seen = Set<String>()
        seen.reserveCapacity(collected.count)

        var position = 0
        while position < collected.count {
            let upper = min(position + 500, collected.count)
            let batch = Array(collected[position..<upper])
            for item in batch {
                seen.insert(item.sourceIdentifier)
            }
            position = upper
            await onBatch(batch)
            await control.progress(position, collected.count)
            if !(await control.shouldContinue()) { return nil }
        }
        return seen
    }

    /// Indicizza i file importati nella cartella interna dell'app.
    func indexImports(directory: URL) -> [IndexedItem] {
        let keys = Self.resourceKeys
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var items: [IndexedItem] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            let item = IndexedItem(
                sourceIdentifier: url.lastPathComponent,
                source: .appImports,
                category: Self.category(for: url, contentType: values.contentType),
                filename: url.lastPathComponent,
                createdAt: values.creationDate,
                modifiedAt: values.contentModificationDate,
                estimatedBytes: size,
                bytesAreEstimated: false,
                localBytes: size
            )
            items.append(item)
        }
        return items
    }

    private static func enumerate(folderID: UUID, root: URL) -> [IndexedItem] {
        var collected: [IndexedItem] = []
        var coordinationError: NSError?
        let keys = resourceKeys
        let keySet = Set(keys)

        NSFileCoordinator().coordinate(readingItemAt: root, options: [.withoutChanges], error: &coordinationError) { coordinatedRoot in
            guard let enumerator = FileManager.default.enumerator(
                at: coordinatedRoot,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return
            }
            let rootPath = coordinatedRoot.path

            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: keySet), values.isRegularFile == true else {
                    continue
                }

                var relativePath = fileURL.path
                if relativePath.hasPrefix(rootPath) {
                    relativePath = String(relativePath.dropFirst(rootPath.count))
                }
                relativePath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !relativePath.isEmpty else { continue }

                let isUbiquitous = values.isUbiquitousItem ?? false
                let isCloudOnly = isUbiquitous && values.ubiquitousItemDownloadingStatus == .notDownloaded
                let size = Int64(values.fileSize ?? 0)

                var item = IndexedItem(
                    sourceIdentifier: folderID.uuidString + "/" + relativePath,
                    source: isUbiquitous ? .iCloudDrive : .localFiles,
                    category: category(for: fileURL, contentType: values.contentType),
                    filename: fileURL.lastPathComponent,
                    createdAt: values.creationDate,
                    modifiedAt: values.contentModificationDate,
                    estimatedBytes: size,
                    bytesAreEstimated: false,
                    localBytes: isCloudOnly ? 0 : size
                )
                item.folderID = folderID
                item.relativePath = relativePath

                var traits: ItemTraits = []
                if isCloudOnly { traits.insert(.cloudOnly) }
                let folders = relativePath.lowercased().split(separator: "/").dropLast()
                if folders.contains(where: { downloadFolderNames.contains(String($0)) })
                    || downloadFolderNames.contains(coordinatedRoot.lastPathComponent.lowercased()) {
                    traits.insert(.download)
                }
                item.traits = traits
                collected.append(item)

                if collected.count >= maximumFiles { break }
            }
        }
        return collected
    }

    /// Tipo del file, ricavato dal tipo dichiarato dal sistema e dall'estensione.
    static func category(for url: URL, contentType: UTType?) -> ContentCategory {
        let fileExtension = url.pathExtension.lowercased()
        if officeExtensions.contains(fileExtension) { return .office }
        if archiveExtensions.contains(fileExtension) { return .archive }

        let type = contentType ?? UTType(filenameExtension: fileExtension)
        if let type {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .photo }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .archive) || type.conforms(to: .zip) || type.conforms(to: .gzip) { return .archive }
            if type.conforms(to: .text) || type.conforms(to: .compositeContent) { return .otherDocument }
        }
        if documentExtensions.contains(fileExtension) { return .otherDocument }
        return .unknown
    }
}
