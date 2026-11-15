import Foundation
import CoreGraphics
import Photos
import Vision

/// Elemento basato su file insieme all'indirizzo da cui leggerlo.
struct FileEntry: Sendable {
    let item: IndexedItem
    let url: URL
}

/// Analisi dei file delle cartelle autorizzate: duplicati esatti, versioni dello stesso documento,
/// copie di immagini già presenti in Foto e caratteristiche delle registrazioni audio.
/// I file presenti solo online vengono letti soltanto se l'utente ha consentito il download.
actor FileAnalysisPipeline {

    // MARK: - Duplicati esatti

    /// Due file sono candidati solo se hanno la stessa dimensione; l'hash SHA-256 conferma l'identità.
    /// Restituisce `nil` se l'analisi è stata interrotta.
    func verifyExactDuplicates(
        entries: [FileEntry],
        control: ScanControl,
        apply: @Sendable ([AnalysisUpdate]) async -> Void
    ) async -> [ItemGroup]? {
        var bySize: [Int64: [FileEntry]] = [:]
        for entry in entries {
            guard let bytes = entry.item.estimatedBytes, bytes > 0 else { continue }
            bySize[bytes, default: []].append(entry)
        }
        let candidates = bySize.values.filter { $0.count >= 2 }
        let total = candidates.reduce(0) { $0 + $1.count }

        var hashes: [UUID: String] = [:]
        var done = 0
        for bucket in candidates {
            for entry in bucket {
                done += 1
                if let known = entry.item.contentHash {
                    hashes[entry.item.id] = known
                    continue
                }
                var update = AnalysisUpdate(id: entry.item.id)
                let wasCloudOnly = entry.item.traits.contains(.cloudOnly)
                let networkAllowed = await control.networkAllowed()
                if wasCloudOnly && !networkAllowed {
                    update.status = .unavailableOffline
                } else if let hash = try? FileHasher.sha256(ofFileAt: entry.url) {
                    hashes[entry.item.id] = hash
                    update.contentHash = hash
                    update.status = .deepAnalyzed
                    if wasCloudOnly {
                        // Il file è stato scaricato solo per la verifica: la copia locale viene rilasciata.
                        try? FileManager.default.evictUbiquitousItem(at: entry.url)
                    }
                } else {
                    update.status = .failed
                }
                await apply([update])
                if done % 5 == 0 {
                    await control.progress(done, total)
                    if !(await control.shouldContinue()) { return nil }
                }
            }
        }
        await control.progress(total, total)

        var byHash: [String: [IndexedItem]] = [:]
        for bucket in candidates {
            for entry in bucket {
                if let hash = hashes[entry.item.id] {
                    byHash[hash, default: []].append(entry.item)
                }
            }
        }

        var groups: [ItemGroup] = []
        for members in byHash.values where members.count >= 2 {
            let suggestion = QualityRanker.originalSuggestion(among: members)
            groups.append(ItemGroup(
                kind: .exactDuplicate,
                scope: .files,
                memberIDs: members.map { $0.id },
                suggestedKeepID: suggestion?.keepID,
                suggestionReason: suggestion?.reason
            ))
        }
        return groups
    }

    // MARK: - Versioni dello stesso documento

    private struct TextSignature {
        let entryIndex: Int
        let pages: [String]
        let pageCount: Int
        let signature: [UInt64]
        let shingles: Set<UInt64>
    }

    /// Cerca documenti simili ma non identici: PDF con testo quasi uguale e file con nomi che
    /// differiscono solo per un suffisso di versione. La decisione spetta sempre all'utente.
    /// Restituisce `nil` se l'analisi è stata interrotta.
    func findDocumentVersions(
        entries: [FileEntry],
        control: ScanControl,
        apply: @Sendable ([AnalysisUpdate]) async -> Void
    ) async -> [ItemGroup]? {
        var groups: [ItemGroup] = []
        var groupedIDs = Set<UUID>()

        // 1) PDF: confronto del testo estratto (con OCR per le scansioni).
        let pdfs = Array(entries
            .filter { $0.item.category == .pdf && !$0.item.traits.contains(.cloudOnly) && $0.item.duplicateGroupID == nil }
            .prefix(600))

        var signatures: [TextSignature] = []
        var updates: [AnalysisUpdate] = []
        for (index, entry) in pdfs.enumerated() {
            let extracted = autoreleasepool { DocumentTextExtractor.extract(pdfAt: entry.url) }
            if let extracted {
                var update = AnalysisUpdate(id: entry.item.id)
                update.pageCount = extracted.pageCount
                let text = extracted.fullText
                if !text.isEmpty {
                    update.textContent = String(text.prefix(1_500))
                    update.addTraits.insert(.hasText)
                    let classification = TextClassifier.classify(
                        lines: [String(text.prefix(4_000))],
                        coverage: 0,
                        isScreenshot: false
                    )
                    update.addTraits.formUnion(classification.traits.intersection([.receipt, .ticket, .sensitiveText]))
                }
                update.status = .previewAnalyzed
                updates.append(update)

                let shingles = TextSimilarity.shingles(TextSimilarity.tokens(text))
                if shingles.count >= 20 {
                    signatures.append(TextSignature(
                        entryIndex: index,
                        pages: extracted.pages,
                        pageCount: extracted.pageCount,
                        signature: TextSimilarity.minHashSignature(shingles),
                        shingles: shingles
                    ))
                }
            }
            if index % 5 == 4 {
                await apply(updates)
                updates.removeAll(keepingCapacity: true)
                await control.progress(index + 1, pdfs.count)
                if !(await control.shouldContinue()) { return nil }
            }
        }
        if !updates.isEmpty {
            await apply(updates)
        }

        if signatures.count >= 2 {
            let threshold = AppConfiguration.Thresholds.similarDocumentScore
            var sets = DisjointSet(count: signatures.count)
            for first in 0..<(signatures.count - 1) {
                for second in (first + 1)..<signatures.count {
                    // La firma MinHash scarta in fretta le coppie chiaramente diverse.
                    let estimate = TextSimilarity.estimatedSimilarity(
                        signatures[first].signature,
                        signatures[second].signature
                    )
                    guard estimate >= threshold - 0.15 else { continue }
                    if TextSimilarity.jaccard(signatures[first].shingles, signatures[second].shingles) >= threshold {
                        sets.union(first, second)
                    }
                }
            }
            for indices in sets.groups() where indices.count >= 2 {
                let members = indices.map { pdfs[signatures[$0].entryIndex].item }
                var note = "Il testo di questi documenti è quasi identico."
                if indices.count == 2 {
                    let first = signatures[indices[0]]
                    let second = signatures[indices[1]]
                    note = TextSimilarity.describeDifference(
                        pagesOfFirst: first.pages,
                        pagesOfSecond: second.pages,
                        firstPageCount: first.pageCount,
                        secondPageCount: second.pageCount
                    )
                }
                groups.append(Self.versionGroup(members: members, note: note))
                for member in members {
                    groupedIDs.insert(member.id)
                }
            }
        }

        // 2) Nomi quasi identici: "Contratto.pdf", "Contratto (1).pdf", "contratto_v2.pdf".
        var byName: [String: [IndexedItem]] = [:]
        for entry in entries where entry.item.category.isDocument && !groupedIDs.contains(entry.item.id) {
            guard let filename = entry.item.filename else { continue }
            let base = TextSimilarity.normalizedBaseName(filename)
            guard base.count >= 3 else { continue }
            let key = entry.item.category.rawValue + "|" + base
            byName[key, default: []].append(entry.item)
        }
        for members in byName.values where members.count >= 2 {
            // Le copie identiche sono già segnalate come duplicati esatti.
            let sharedGroup = members.first?.duplicateGroupID
            if sharedGroup != nil && members.allSatisfy({ $0.duplicateGroupID == sharedGroup }) { continue }
            groups.append(Self.versionGroup(
                members: members,
                note: "I nomi sono quasi identici: potrebbero essere versioni dello stesso file."
            ))
        }

        await control.progress(pdfs.count, pdfs.count)
        return groups
    }

    private static func versionGroup(members: [IndexedItem], note: String) -> ItemGroup {
        let newest = members.max {
            ($0.modifiedAt ?? Date.distantPast) < ($1.modifiedAt ?? Date.distantPast)
        }
        return ItemGroup(
            kind: .documentVersion,
            scope: .files,
            memberIDs: members.map { $0.id },
            suggestedKeepID: newest?.id,
            suggestionReason: newest == nil ? nil : "è la versione modificata più di recente",
            note: note
        )
    }

    // MARK: - Duplicati tra file e libreria Foto

    /// Cerca immagini presenti sia nelle cartelle sia nella libreria Foto.
    /// Il confronto avviene sulle anteprime: il gruppo è dichiarato "esatto" soltanto se anche
    /// gli hash dei contenuti originali coincidono.
    /// Restituisce `nil` se l'analisi è stata interrotta.
    func findCrossSourceDuplicates(
        imageEntries: [FileEntry],
        libraryItems: [IndexedItem],
        control: ScanControl,
        apply: @Sendable ([AnalysisUpdate]) async -> Void
    ) async -> [ItemGroup]? {
        let library = libraryItems.filter { item in
            guard item.category == .photo, item.duplicateGroupID == nil, let hash = item.perceptualHash else {
                return false
            }
            return ImageMetrics.isInformative(hash: hash)
        }
        guard !library.isEmpty else { return [] }

        var groups: [ItemGroup] = []
        var usedLibraryIDs = Set<UUID>()
        var updates: [AnalysisUpdate] = []

        for (index, entry) in imageEntries.enumerated() {
            if !entry.item.traits.contains(.cloudOnly) && entry.item.duplicateGroupID == nil {
                let allowNetwork = await control.networkAllowed()
                let match = await Self.crossMatch(
                    entry: entry,
                    library: library,
                    excluding: usedLibraryIDs,
                    allowNetwork: allowNetwork
                )
                if let hash = match.hash {
                    var update = AnalysisUpdate(id: entry.item.id)
                    update.perceptualHash = hash
                    update.status = .previewAnalyzed
                    updates.append(update)
                }
                if let group = match.group {
                    groups.append(group)
                    if let libraryID = group.memberIDs.first {
                        usedLibraryIDs.insert(libraryID)
                    }
                }
            }
            if index % 10 == 9 {
                await apply(updates)
                updates.removeAll(keepingCapacity: true)
                await control.progress(index + 1, imageEntries.count)
                if !(await control.shouldContinue()) { return nil }
            }
        }
        if !updates.isEmpty {
            await apply(updates)
        }
        await control.progress(imageEntries.count, imageEntries.count)
        return groups
    }

    private static func crossMatch(
        entry: FileEntry,
        library: [IndexedItem],
        excluding usedLibraryIDs: Set<UUID>,
        allowNetwork: Bool
    ) async -> (hash: UInt64?, group: ItemGroup?) {
        guard let thumbnail = ImageAnalyzer.thumbnail(ofImageAt: entry.url, maxSide: 360),
              let hash = ImageAnalyzer.perceptualHash(of: thumbnail) else {
            return (nil, nil)
        }
        guard ImageMetrics.isInformative(hash: hash) else {
            return (hash, nil)
        }

        // Le due anteprime nascono da ridimensionamenti diversi: si tollerano pochi bit di differenza.
        let nearby = library
            .filter { item in
                guard !usedLibraryIDs.contains(item.id), let other = item.perceptualHash else { return false }
                return ImageMetrics.hammingDistance(hash, other) <= 3
            }
            .prefix(5)
        guard !nearby.isEmpty, let filePrint = ImageAnalyzer.featurePrint(for: thumbnail) else {
            return (hash, nil)
        }

        for candidate in nearby {
            guard let asset = PhotoLibraryService.asset(candidate.sourceIdentifier),
                  let image = AnalysisImageLoader.thumbnail(for: asset, maxSide: 360),
                  let libraryPrint = ImageAnalyzer.featurePrint(for: image),
                  let distance = ImageAnalyzer.distance(filePrint, libraryPrint),
                  distance < AppConfiguration.Thresholds.duplicateFeatureDistance else {
                continue
            }

            // Verifica sul contenuto: solo hash identici giustificano la dicitura "duplicato esatto".
            var kind = GroupKind.visualDuplicate
            if let fileHash = try? FileHasher.sha256(ofFileAt: entry.url),
               let resource = PhotoResourceInspector.primaryResource(for: asset),
               let libraryHash = await FileHasher.sha256(of: resource, allowNetwork: allowNetwork),
               fileHash == libraryHash {
                kind = .exactDuplicate
            }

            let group = ItemGroup(
                kind: kind,
                scope: .crossSource,
                memberIDs: [candidate.id, entry.item.id],
                suggestedKeepID: candidate.id,
                suggestionReason: "è già nella libreria Foto",
                note: "La stessa immagine è presente sia in Foto sia tra i file."
            )
            return (hash, group)
        }
        return (hash, nil)
    }

    // MARK: - Audio

    /// Analizza le registrazioni non ancora esaminate (durata, silenzi, impronta sonora) e raggruppa
    /// quelle dall'andamento molto simile. Restituisce `nil` se l'analisi è stata interrotta.
    func analyzeAudio(
        entries: [FileEntry],
        control: ScanControl,
        apply: @Sendable ([AnalysisUpdate]) async -> Void
    ) async -> [ItemGroup]? {
        var fingerprints: [UUID: [Float]] = [:]
        var durations: [UUID: Double] = [:]

        for (index, entry) in entries.enumerated() {
            let item = entry.item
            if let known = item.fingerprint, item.analysisStatus != .metadataOnly {
                fingerprints[item.id] = known
                durations[item.id] = item.duration
            } else if !item.traits.contains(.cloudOnly) {
                var update = AnalysisUpdate(id: item.id)
                if let analysis = try? AudioAnalyzer.analyze(url: entry.url) {
                    update.duration = analysis.duration
                    update.fingerprint = analysis.fingerprint
                    if analysis.longestSilence >= AppConfiguration.Thresholds.longSilence {
                        update.addTraits.insert(.longSilence)
                    } else {
                        update.removeTraits.insert(.longSilence)
                    }
                    update.status = .previewAnalyzed
                    fingerprints[item.id] = analysis.fingerprint
                    durations[item.id] = analysis.duration
                } else {
                    update.status = .failed
                }
                await apply([update])
            }
            if index % 3 == 2 {
                await control.progress(index + 1, entries.count)
                if !(await control.shouldContinue()) { return nil }
            }
        }
        await control.progress(entries.count, entries.count)

        // Registrazioni simili: durata quasi uguale e impronta sonora molto vicina.
        let analyzed = entries
            .map { $0.item }
            .filter { fingerprints[$0.id] != nil && $0.duplicateGroupID == nil }
            .sorted { (durations[$0.id] ?? 0) < (durations[$1.id] ?? 0) }
        guard analyzed.count >= 2 else { return [] }

        var sets = DisjointSet(count: analyzed.count)
        var matched = false
        for first in 0..<(analyzed.count - 1) {
            let firstDuration = durations[analyzed[first].id] ?? 0
            let tolerance = max(1.0, firstDuration * 0.03)
            var second = first + 1
            while second < analyzed.count, (durations[analyzed[second].id] ?? 0) - firstDuration <= tolerance {
                if let a = fingerprints[analyzed[first].id], let b = fingerprints[analyzed[second].id],
                   AudioAnalyzer.similarity(a, b) >= AppConfiguration.Thresholds.similarAudioScore {
                    sets.union(first, second)
                    matched = true
                }
                second += 1
            }
        }
        guard matched else { return [] }

        var groups: [ItemGroup] = []
        for indices in sets.groups() where indices.count >= 2 {
            let members = indices.map { analyzed[$0] }
            let largest = members.max { $0.bytes < $1.bytes }
            groups.append(ItemGroup(
                kind: .similarAudio,
                scope: .files,
                memberIDs: members.map { $0.id },
                suggestedKeepID: largest?.id,
                suggestionReason: largest == nil ? nil : "è la versione con la qualità più alta",
                note: "Durata e andamento sonoro quasi identici."
            ))
        }
        return groups
    }
}
