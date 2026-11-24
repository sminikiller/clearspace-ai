import Foundation
import AVFoundation
import CoreGraphics
import Photos
import Vision

/// Analisi di foto e video della libreria, eseguite sul dispositivo e fuori dal thread principale.
/// - Fase B: misure sulle anteprime (nitidezza, luminosità, hash percettivo, testo).
/// - Raggruppamento: scatti simili, raffiche, probabili duplicati.
/// - Fase C: verifica dei duplicati esatti sul contenuto originale (SHA-256).
/// Le analisi producono soltanto suggerimenti: nessuna di esse seleziona o elimina elementi.
actor PhotoAnalysisPipeline {

    struct SimilarityResult: Sendable {
        var groups: [ItemGroup]
        /// Elementi i cui raggruppamenti sono stati ricalcolati in questo passaggio.
        var processedIDs: Set<UUID>
        var isComplete: Bool
    }

    // MARK: - Lavoro in parallelo

    /// Quanti elementi si analizzano insieme: abbastanza per usare più core, non tanti da scaldare
    /// il telefono o occupare troppa memoria con le anteprime aperte contemporaneamente.
    static var parallelWorkers: Int {
        min(4, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
    }

    /// Calcola `work` per ogni posizione usando più core. Serve per i lavori pesanti e sincroni
    /// (anteprime di PhotoKit, Vision) in cui ogni elemento è indipendente dagli altri.
    /// I risultati rispettano l'ordine delle posizioni.
    static func concurrentResults<Value>(count: Int, _ work: (Int) -> Value?) -> [Value?] {
        guard count > 1 else {
            return count == 1 ? [autoreleasepool { work(0) }] : []
        }
        let slots = ConcurrentSlots<Value>(count: count)
        let workers = min(count, parallelWorkers)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            var index = worker
            while index < count {
                let value = autoreleasepool { work(index) }
                slots.store(value, at: index)
                index += workers
            }
        }
        return slots.values
    }

    /// Asset della libreria degli elementi indicati, letti con un'unica richiesta a PhotoKit invece
    /// che uno per uno.
    static func assetsByIdentifier(_ items: [IndexedItem]) -> [String: PHAsset] {
        var result: [String: PHAsset] = [:]
        let identifiers = items.filter { $0.source == .photoLibrary }.map { $0.sourceIdentifier }
        for asset in PhotoLibraryService.assets(identifiers) {
            result[asset.localIdentifier] = asset
        }
        return result
    }

    // MARK: - Fase B: anteprime

    /// Elementi esaminati tra un salvataggio e il successivo: tra un blocco e l'altro l'analisi
    /// può essere messa in pausa o interrotta.
    private static let previewChunkSize = 32

    /// Analizza le anteprime, più elementi alla volta. Restituisce `false` se l'analisi è stata interrotta.
    func analyzePreviews(
        items: [IndexedItem],
        control: ScanControl,
        apply: @Sendable ([AnalysisUpdate]) async -> Void
    ) async -> Bool {
        var start = 0
        while start < items.count {
            let chunk = Array(items[start..<min(start + Self.previewChunkSize, items.count)])
            let assets = Self.assetsByIdentifier(chunk)
            let updates = Self.concurrentResults(count: chunk.count) { (index: Int) -> AnalysisUpdate? in
                let item = chunk[index]
                return Self.previewUpdate(for: item, asset: assets[item.sourceIdentifier])
            }
            await apply(updates.compactMap { $0 })
            start += chunk.count
            await control.progress(start, items.count)
            if !(await control.shouldContinue()) { return false }
        }
        await control.progress(items.count, items.count)
        return true
    }

    static func previewUpdate(for item: IndexedItem) -> AnalysisUpdate {
        previewUpdate(for: item, asset: PhotoLibraryService.asset(item.sourceIdentifier))
    }

    static func previewUpdate(for item: IndexedItem, asset: PHAsset?) -> AnalysisUpdate {
        var update = AnalysisUpdate(id: item.id)
        guard let asset else {
            update.status = .failed
            return update
        }
        guard let preview = AnalysisImageLoader.thumbnail(for: asset, maxSide: 512) else {
            update.status = .unavailableOffline
            return update
        }

        if let gray = ImageAnalyzer.grayImage(from: preview, maxSide: 512) {
            let variance = ImageMetrics.laplacianVariance(gray)
            let light = ImageMetrics.luminance(gray)
            update.sharpness = ImageMetrics.sharpnessScore(variance: variance)
            update.brightness = light.mean

            // I difetti tecnici vengono segnalati solo per le foto scattate, non per screenshot e video.
            if item.category == .photo && !item.traits.contains(.screenshot) {
                if light.deviation < AppConfiguration.Thresholds.blankContrast {
                    update.addTraits.insert(.blank)
                } else if light.mean < AppConfiguration.Thresholds.darkBrightness {
                    update.addTraits.insert(.dark)
                } else if variance < AppConfiguration.Thresholds.blurVariance {
                    update.addTraits.insert(.blurry)
                }
            }
        }
        update.perceptualHash = ImageAnalyzer.perceptualHash(of: preview)

        if item.category == .photo {
            let isScreenshot = item.traits.contains(.screenshot)
            let looksLikeDocument = !isScreenshot && ImageAnalyzer.documentConfidence(preview) >= 0.9
            if isScreenshot || looksLikeDocument {
                // Per leggere il testo serve più dettaglio dell'anteprima usata per le misure.
                let detailed = AnalysisImageLoader.thumbnail(for: asset, maxSide: 1_400) ?? preview
                let recognized = ImageAnalyzer.recognizeText(in: detailed)
                let classification = TextClassifier.classify(
                    lines: recognized.lines,
                    coverage: recognized.coverage,
                    isScreenshot: isScreenshot
                )
                update.addTraits.formUnion(classification.traits)
                if classification.characterCount > 0 {
                    update.textContent = String(recognized.text.prefix(600))
                }
                if looksLikeDocument && classification.traits.contains(.hasText) {
                    update.addTraits.insert(.documentLike)
                }
                if ImageAnalyzer.containsQRCode(detailed) {
                    update.addTraits.insert(.qrCode)
                }
            }
        }

        update.status = .previewAnalyzed
        return update
    }

    // MARK: - Foto simili e raffiche

    /// Raggruppa raffiche e scatti consecutivi dello stesso soggetto.
    /// Confronta soltanto foto vicine nel tempo: non serve paragonare ogni foto con tutte le altre.
    func buildSimilarityGroups(
        items: [IndexedItem],
        onlyUnchecked: Bool,
        thresholds: SimilarityThresholds = .standard,
        control: ScanControl
    ) async -> SimilarityResult {
        let images = items
            .filter { $0.source == .photoLibrary && $0.category == .photo && $0.createdAt != nil }
            .sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }

        var groups: [ItemGroup] = []
        var processed = Set<UUID>()

        // Raffiche: iOS le identifica già con un identificativo comune.
        var bursts: [String: [IndexedItem]] = [:]
        for item in images {
            if let burst = item.burstIdentifier {
                bursts[burst, default: []].append(item)
            }
        }
        for members in bursts.values where members.count >= 2 {
            if onlyUnchecked && members.allSatisfy({ $0.traits.contains(.similarityChecked) }) { continue }
            let suggestion = QualityRanker.suggestion(among: members)
            groups.append(ItemGroup(
                kind: .burst,
                scope: .photoLibrary,
                memberIDs: members.map { $0.id },
                suggestedKeepID: suggestion?.keepID,
                suggestionReason: suggestion?.reason
            ))
            for member in members {
                processed.insert(member.id)
            }
        }

        // Scatti consecutivi: catene di foto distanti tra loro meno della finestra temporale.
        let window = thresholds.timeWindow
        let limit = AppConfiguration.Thresholds.similarBucketLimit
        var buckets: [[IndexedItem]] = []
        var current: [IndexedItem] = []
        for item in images where item.burstIdentifier == nil {
            guard let date = item.createdAt else { continue }
            if let lastDate = current.last?.createdAt {
                if date.timeIntervalSince(lastDate) > window || current.count >= limit {
                    if current.count >= 2 { buckets.append(current) }
                    current = []
                }
            }
            current.append(item)
        }
        if current.count >= 2 { buckets.append(current) }

        let pending = onlyUnchecked
            ? buckets.filter { bucket in bucket.contains { !$0.traits.contains(.similarityChecked) } }
            : buckets

        var completed = 0
        for bucket in pending {
            let clusters = autoreleasepool {
                Self.clusters(in: bucket, hashDistance: thresholds.hashDistance) { first, second in
                    let bothScreenshots = first.traits.contains(.screenshot) && second.traits.contains(.screenshot)
                    return bothScreenshots ? thresholds.screenshotDistance : thresholds.featureDistance
                }
            }
            for cluster in clusters {
                let suggestion = QualityRanker.suggestion(among: cluster)
                groups.append(ItemGroup(
                    kind: .similar,
                    scope: .photoLibrary,
                    memberIDs: cluster.map { $0.id },
                    suggestedKeepID: suggestion?.keepID,
                    suggestionReason: suggestion?.reason
                ))
            }
            for member in bucket {
                processed.insert(member.id)
            }
            completed += 1
            if completed % 5 == 0 {
                await control.progress(completed, pending.count)
                if !(await control.shouldContinue()) {
                    return SimilarityResult(groups: groups, processedIDs: processed, isComplete: false)
                }
            }
        }
        await control.progress(pending.count, pending.count)

        // Anche gli scatti isolati risultano controllati: non hanno vicini con cui confrontarli.
        for item in images where !item.traits.contains(.similarityChecked) {
            processed.insert(item.id)
        }
        return SimilarityResult(groups: groups, processedIDs: processed, isComplete: true)
    }

    /// Raggruppa gli elementi le cui anteprime distano meno della soglia indicata per la coppia.
    private static func clusters(
        in bucket: [IndexedItem],
        hashDistance: Int,
        threshold: (IndexedItem, IndexedItem) -> Float
    ) -> [[IndexedItem]] {
        // Le impronte visive sono la parte costosa: si calcolano in parallelo, una per scatto.
        let observations = featurePrints(for: bucket)
        var entries: [(item: IndexedItem, observation: VNFeaturePrintObservation?)] = []
        for (index, item) in bucket.enumerated() {
            let observation = observations[index]
            if observation == nil && item.perceptualHash == nil { continue }
            entries.append((item, observation))
        }
        guard entries.count >= 2 else { return [] }

        var sets = DisjointSet(count: entries.count)
        for first in 0..<(entries.count - 1) {
            for second in (first + 1)..<entries.count {
                let firstItem = entries[first].item
                let secondItem = entries[second].item
                if let firstPrint = entries[first].observation,
                   let secondPrint = entries[second].observation,
                   let distance = ImageAnalyzer.distance(firstPrint, secondPrint) {
                    if distance < threshold(firstItem, secondItem) {
                        sets.union(first, second)
                    }
                } else if hashesLookAlike(firstItem, secondItem, maxDistance: hashDistance) {
                    sets.union(first, second)
                }
            }
        }
        return sets.groups()
            .filter { $0.count >= 2 }
            .map { indices in indices.map { entries[$0].item } }
    }

    /// Confronto di riserva per quando Vision non riesce a produrre l'impronta di un'immagine
    /// (succede su alcuni dispositivi e simulatori): si usa l'hash percettivo delle anteprime.
    private static func hashesLookAlike(_ first: IndexedItem, _ second: IndexedItem, maxDistance: Int) -> Bool {
        guard let firstHash = first.perceptualHash, let secondHash = second.perceptualHash,
              ImageMetrics.isInformative(hash: firstHash), ImageMetrics.isInformative(hash: secondHash) else {
            return false
        }
        return ImageMetrics.hammingDistance(firstHash, secondHash) <= maxDistance
    }

    private static func featurePrint(for item: IndexedItem) -> VNFeaturePrintObservation? {
        featurePrint(for: item, asset: PhotoLibraryService.asset(item.sourceIdentifier))
    }

    private static func featurePrint(for item: IndexedItem, asset: PHAsset?) -> VNFeaturePrintObservation? {
        guard let asset, let image = AnalysisImageLoader.thumbnail(for: asset, maxSide: 360) else {
            return nil
        }
        return ImageAnalyzer.featurePrint(for: image)
    }

    /// Impronte visive di più elementi, calcolate in parallelo e nello stesso ordine.
    private static func featurePrints(for items: [IndexedItem]) -> [VNFeaturePrintObservation?] {
        let assets = assetsByIdentifier(items)
        return concurrentResults(count: items.count) { (index: Int) -> VNFeaturePrintObservation? in
            let item = items[index]
            return featurePrint(for: item, asset: assets[item.sourceIdentifier])
        }
    }

    // MARK: - Scelta dello scatto migliore

    /// Elementi misurati insieme: le anteprime grandi (e, se consentito, scaricate da iCloud)
    /// occupano memoria, quindi i blocchi sono più piccoli di quelli dell'analisi delle anteprime.
    private static let shotChunkSize = 12

    /// Calcola, per i membri dei gruppi di foto simili, le misure che servono a scegliere lo scatto
    /// migliore: nitidezza dell'immagine e del soggetto, qualità dei volti, occhi aperti, giudizio estetico.
    /// Più scatti vengono misurati insieme. Restituisce `false` se l'analisi è stata interrotta.
    func analyzeShots(
        items: [IndexedItem],
        control: ScanControl,
        apply: @Sendable ([AnalysisUpdate]) async -> Void
    ) async -> Bool {
        var start = 0
        while start < items.count {
            let chunk = Array(items[start..<min(start + Self.shotChunkSize, items.count)])
            let allowNetwork = await control.networkAllowed()
            let assets = Self.assetsByIdentifier(chunk)
            let updates = Self.concurrentResults(count: chunk.count) { (index: Int) -> AnalysisUpdate? in
                let item = chunk[index]
                guard let metrics = Self.shotMetrics(
                    for: item,
                    asset: assets[item.sourceIdentifier],
                    allowNetwork: allowNetwork
                ) else {
                    return nil
                }
                var update = AnalysisUpdate(id: item.id)
                update.shot = metrics
                return update
            }
            let measured = updates.compactMap { $0 }
            if !measured.isEmpty {
                await apply(measured)
            }
            start += chunk.count
            await control.progress(start, items.count)
            if !(await control.shouldContinue()) { return false }
        }
        await control.progress(items.count, items.count)
        return true
    }

    /// Misure di uno scatto, lette da un'anteprima abbastanza grande da distinguere due foto simili.
    /// Restituisce `nil` se sul dispositivo è disponibile soltanto una miniatura.
    static func shotMetrics(for item: IndexedItem, allowNetwork: Bool) -> ShotMetrics? {
        guard item.source == .photoLibrary else { return nil }
        return shotMetrics(for: item, asset: PhotoLibraryService.asset(item.sourceIdentifier), allowNetwork: allowNetwork)
    }

    static func shotMetrics(for item: IndexedItem, asset: PHAsset?, allowNetwork: Bool) -> ShotMetrics? {
        guard item.source == .photoLibrary,
              let asset,
              let image = AnalysisImageLoader.thumbnail(
                  for: asset,
                  maxSide: CGFloat(AppConfiguration.Thresholds.shotAnalysisSide),
                  allowNetwork: allowNetwork
              ) else {
            return nil
        }
        return ShotAnalyzer.analyze(image)
    }

    // MARK: - Probabili duplicati (confronto delle anteprime)

    /// Trova immagini visivamente identiche confrontando le anteprime.
    /// Il risultato è "probabile duplicato": la certezza si ha solo con la verifica dell'originale.
    /// Restituisce `nil` se l'analisi è stata interrotta.
    func buildVisualDuplicateGroups(
        items: [IndexedItem],
        excluding excludedIDs: Set<UUID>,
        control: ScanControl
    ) async -> [ItemGroup]? {
        let candidates = items.filter { item in
            guard item.source == .photoLibrary, item.category == .photo, !excludedIDs.contains(item.id),
                  let hash = item.perceptualHash else {
                return false
            }
            return ImageMetrics.isInformative(hash: hash) && item.traits.isDisjoint(with: [.blank, .dark])
        }
        guard candidates.count >= 2 else { return [] }

        let pairs = ImageMetrics.nearPairs(candidates.map { $0.perceptualHash ?? 0 }, maxDistance: 3)
        guard !pairs.isEmpty else { return [] }

        var sets = DisjointSet(count: candidates.count)
        var prints: [Int: VNFeaturePrintObservation] = [:]
        var matched = false
        var checked = 0

        for pair in pairs {
            let first = candidates[pair.0]
            let second = candidates[pair.1]
            // Due copie della stessa immagine hanno le stesse proporzioni.
            if Self.aspectRatiosMatch(first, second) {
                if prints[pair.0] == nil { prints[pair.0] = Self.featurePrint(for: first) }
                if prints[pair.1] == nil { prints[pair.1] = Self.featurePrint(for: second) }
                if let a = prints[pair.0], let b = prints[pair.1],
                   let distance = ImageAnalyzer.distance(a, b),
                   distance < AppConfiguration.Thresholds.duplicateFeatureDistance {
                    sets.union(pair.0, pair.1)
                    matched = true
                }
            }
            checked += 1
            if checked % 20 == 0 {
                await control.progress(checked, pairs.count)
                if !(await control.shouldContinue()) { return nil }
            }
        }
        guard matched else { return [] }

        var groups: [ItemGroup] = []
        for indices in sets.groups() where indices.count >= 2 {
            let members = indices.map { candidates[$0] }
            let suggestion = QualityRanker.suggestion(among: members)
            groups.append(ItemGroup(
                kind: .visualDuplicate,
                scope: .photoLibrary,
                memberIDs: members.map { $0.id },
                suggestedKeepID: suggestion?.keepID,
                suggestionReason: suggestion?.reason
            ))
        }
        return groups
    }

    private static func aspectRatiosMatch(_ first: IndexedItem, _ second: IndexedItem) -> Bool {
        guard first.pixelWidth > 0, first.pixelHeight > 0, second.pixelWidth > 0, second.pixelHeight > 0 else {
            return true
        }
        let firstRatio = Double(first.pixelWidth) / Double(first.pixelHeight)
        let secondRatio = Double(second.pixelWidth) / Double(second.pixelHeight)
        return abs(firstRatio - secondRatio) / max(firstRatio, secondRatio) < 0.03
    }

    // MARK: - Fase C: duplicati esatti

    /// Verifica i duplicati sul contenuto originale. Sono candidati solo gli elementi con identiche
    /// dimensioni in byte e in pixel; l'hash SHA-256 conferma (o smentisce) che siano identici.
    /// Gli originali presenti solo su iCloud vengono scaricati soltanto se la rete è consentita.
    /// Restituisce `nil` se l'analisi è stata interrotta.
    func verifyExactDuplicates(
        items: [IndexedItem],
        control: ScanControl,
        apply: @Sendable ([AnalysisUpdate]) async -> Void
    ) async -> [ItemGroup]? {
        struct Key: Hashable {
            let category: ContentCategory
            let width: Int
            let height: Int
            let bytes: Int64
            let duration: Int
        }

        var buckets: [Key: [IndexedItem]] = [:]
        for item in items where item.source == .photoLibrary && !item.bytesAreEstimated {
            guard let bytes = item.estimatedBytes, bytes > 0 else { continue }
            let key = Key(
                category: item.category,
                width: item.pixelWidth,
                height: item.pixelHeight,
                bytes: bytes,
                duration: Int((item.duration * 10).rounded())
            )
            buckets[key, default: []].append(item)
        }
        let candidates = buckets.values.filter { $0.count >= 2 }
        let total = candidates.reduce(0) { $0 + $1.count }

        var hashes: [UUID: String] = [:]
        var done = 0
        for bucket in candidates {
            for item in bucket {
                done += 1
                if let known = item.contentHash {
                    hashes[item.id] = known
                    continue
                }
                let allowNetwork = await control.networkAllowed()
                var update = AnalysisUpdate(id: item.id)
                if let hash = await Self.hashOriginal(of: item, allowNetwork: allowNetwork) {
                    hashes[item.id] = hash
                    update.contentHash = hash
                    update.status = .deepAnalyzed
                } else {
                    update.status = .unavailableOffline
                }
                await apply([update])
                await control.progress(done, total)
                if !(await control.shouldContinue()) { return nil }
            }
        }

        var byHash: [String: [IndexedItem]] = [:]
        for bucket in candidates {
            for item in bucket {
                if let hash = hashes[item.id] {
                    byHash[hash, default: []].append(item)
                }
            }
        }

        var groups: [ItemGroup] = []
        for members in byHash.values where members.count >= 2 {
            let suggestion = QualityRanker.originalSuggestion(among: members)
            groups.append(ItemGroup(
                kind: .exactDuplicate,
                scope: .photoLibrary,
                memberIDs: members.map { $0.id },
                suggestedKeepID: suggestion?.keepID,
                suggestionReason: suggestion?.reason
            ))
        }
        return groups
    }

    static func hashOriginal(of item: IndexedItem, allowNetwork: Bool) async -> String? {
        guard let asset = PhotoLibraryService.asset(item.sourceIdentifier),
              let resource = PhotoResourceInspector.primaryResource(for: asset) else {
            return nil
        }
        return await FileHasher.sha256(of: resource, allowNetwork: allowNetwork)
    }

    // MARK: - Video simili

    /// Cerca possibili versioni dello stesso video: durata quasi uguale e fotogrammi campione simili.
    /// Restituisce `nil` se l'analisi è stata interrotta.
    func buildSimilarVideoGroups(items: [IndexedItem], control: ScanControl) async -> [ItemGroup]? {
        let videos = items
            .filter { $0.source == .photoLibrary && $0.category == .video && $0.duration > 1 && $0.duplicateGroupID == nil }
            .sorted { $0.duration < $1.duration }
        guard videos.count >= 2 else { return [] }

        var posters: [Int: VNFeaturePrintObservation] = [:]
        var sets = DisjointSet(count: videos.count)
        var matched = false

        func poster(_ index: Int) -> VNFeaturePrintObservation? {
            if let cached = posters[index] { return cached }
            guard let observation = Self.featurePrint(for: videos[index]) else { return nil }
            posters[index] = observation
            return observation
        }

        for first in 0..<(videos.count - 1) {
            let tolerance = max(1.0, videos[first].duration * 0.02)
            var second = first + 1
            while second < videos.count && videos[second].duration - videos[first].duration <= tolerance {
                if let a = poster(first), let b = poster(second),
                   let distance = ImageAnalyzer.distance(a, b),
                   distance < AppConfiguration.Thresholds.similarVideoDistance {
                    if await Self.middleFramesMatch(videos[first], videos[second]) {
                        sets.union(first, second)
                        matched = true
                    }
                }
                second += 1
            }
            if first % 20 == 0 {
                await control.progress(first, videos.count)
                if !(await control.shouldContinue()) { return nil }
            }
        }
        guard matched else { return [] }

        var groups: [ItemGroup] = []
        for indices in sets.groups() where indices.count >= 2 {
            let members = indices.map { videos[$0] }
            let suggestion = QualityRanker.suggestion(among: members)
            groups.append(ItemGroup(
                kind: .similarVideo,
                scope: .photoLibrary,
                memberIDs: members.map { $0.id },
                suggestedKeepID: suggestion?.keepID,
                suggestionReason: suggestion?.reason
            ))
        }
        return groups
    }

    /// Confronta il fotogramma centrale dei due video. Se uno dei due non è disponibile in locale
    /// il confronto non è possibile e resta valido quello sul fotogramma di copertina.
    private static func middleFramesMatch(_ first: IndexedItem, _ second: IndexedItem) async -> Bool {
        guard let firstFrame = await middleFrame(of: first),
              let secondFrame = await middleFrame(of: second),
              let firstPrint = ImageAnalyzer.featurePrint(for: firstFrame),
              let secondPrint = ImageAnalyzer.featurePrint(for: secondFrame),
              let distance = ImageAnalyzer.distance(firstPrint, secondPrint) else {
            return true
        }
        return distance < AppConfiguration.Thresholds.similarVideoDistance
    }

    private static func middleFrame(of item: IndexedItem) async -> CGImage? {
        guard let asset = PhotoLibraryService.asset(item.sourceIdentifier),
              let avAsset = await loadLocalAVAsset(asset) else {
            return nil
        }
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        let time = CMTime(seconds: item.duration / 2, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    /// Carica il video senza usare la rete: restituisce `nil` se l'originale è solo su iCloud.
    private static func loadLocalAVAsset(_ asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { (continuation: CheckedContinuation<AVAsset?, Never>) in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }
}

/// Risultati raccolti da più thread, ciascuno nella propria posizione. Le scritture sono protette
/// da un lucchetto; la lettura finale avviene quando tutti i thread hanno finito.
private final class ConcurrentSlots<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value?]

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    func store(_ value: Value?, at index: Int) {
        lock.lock()
        storage[index] = value
        lock.unlock()
    }

    var values: [Value?] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
