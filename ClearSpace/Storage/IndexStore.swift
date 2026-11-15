import Foundation
import Observation

private let indexFileName = "index.v1.bin"
private let reviewFileName = "review.v1.bin"
private let indexSchemaVersion = 1

private struct IndexSnapshot: Codable {
    var version: Int
    var items: [IndexedItem]
    var groups: [ItemGroup]
}

/// Decisione dell'utente su un elemento, salvata separatamente dall'indice:
/// è piccola e viene scritta a ogni scelta, così nessuna decisione va persa.
private struct ReviewRecord: Codable {
    let id: UUID
    /// Origine e identificativo dell'elemento: permette di ritrovare la decisione
    /// anche se l'indice viene ricostruito da zero.
    let sourceKey: String
    let status: ReviewStatus
    let isProtected: Bool
    let protectionOverride: Bool
    let decidedAt: Date?
}

/// Indice locale degli elementi: metadati, risultati delle analisi, gruppi e decisioni.
/// Vive in memoria per filtrare velocemente anche decine di migliaia di elementi e viene
/// salvato cifrato su disco. Non contiene mai copie dei file originali.
@MainActor
@Observable
final class IndexStore {

    /// Cambia a ogni modifica dell'indice: le viste la osservano per ricaricare i propri elenchi.
    private(set) var revision = 0
    private(set) var summary = CatalogSummary.empty
    /// Numero di elementi nella lista di revisione delle eliminazioni.
    private(set) var markedCount = 0
    private(set) var isLoaded = false

    @ObservationIgnored private var itemsByID: [UUID: IndexedItem] = [:]
    @ObservationIgnored private var idBySourceKey: [String: UUID] = [:]
    @ObservationIgnored private var groupsByID: [UUID: ItemGroup] = [:]
    @ObservationIgnored private var markedIDs = Set<UUID>()
    /// Decisioni su elementi al momento assenti dall'indice (es. accesso revocato, indice ricostruito):
    /// vengono riapplicate quando l'elemento ricompare.
    @ObservationIgnored private var orphanRecords: [String: ReviewRecord] = [:]

    @ObservationIgnored private var revisionBumpPending = false
    @ObservationIgnored private var summaryRunning = false
    @ObservationIgnored private var summaryDirty = false
    @ObservationIgnored private var summaryPaused = false
    @ObservationIgnored private var indexSaveRunning = false
    @ObservationIgnored private var indexDirty = false
    @ObservationIgnored private var reviewSaveRunning = false
    @ObservationIgnored private var reviewDirty = false

    /// Forniti dall'ambiente dell'app: regole di protezione e parametri correnti.
    @ObservationIgnored var evaluatorProvider: @MainActor () -> ProtectionEvaluator = { ProtectionEvaluator() }
    @ObservationIgnored var contextProvider: @MainActor () -> CollectionContext = { CollectionContext() }

    private let files: SecureFileStore

    init(files: SecureFileStore = SecureFileStore()) {
        self.files = files
    }

    // MARK: - Lettura

    var itemCount: Int { itemsByID.count }
    var isEmpty: Bool { itemsByID.isEmpty }

    func item(_ id: UUID) -> IndexedItem? {
        itemsByID[id]
    }

    /// Restituisce gli elementi nell'ordine richiesto, ignorando quelli non più presenti.
    func items(_ ids: [UUID]) -> [IndexedItem] {
        ids.compactMap { itemsByID[$0] }
    }

    func snapshot() -> [IndexedItem] {
        Array(itemsByID.values)
    }

    func groupsSnapshot() -> [ItemGroup] {
        Array(groupsByID.values)
    }

    func group(_ id: UUID) -> ItemGroup? {
        groupsByID[id]
    }

    func members(of group: ItemGroup) -> [IndexedItem] {
        group.memberIDs.compactMap { itemsByID[$0] }
    }

    func markedItems() -> [IndexedItem] {
        markedIDs
            .compactMap { itemsByID[$0] }
            .sorted { ($0.decidedAt ?? Date.distantPast) > ($1.decidedAt ?? Date.distantPast) }
    }

    /// Elementi di una sorgente, indicizzati per identificativo: serve alle scansioni incrementali.
    func existingItems(source: StorageSource) -> [String: IndexedItem] {
        var result: [String: IndexedItem] = [:]
        for item in itemsByID.values where item.source == source {
            result[item.sourceIdentifier] = item
        }
        return result
    }

    func existingItems(inFolder folderID: UUID) -> [String: IndexedItem] {
        var result: [String: IndexedItem] = [:]
        for item in itemsByID.values where item.folderID == folderID {
            result[item.sourceIdentifier] = item
        }
        return result
    }

    // MARK: - Modifiche dell'indice

    private static func sourceKey(_ source: StorageSource, _ identifier: String) -> String {
        source.rawValue + "|" + identifier
    }

    /// Inserisce nuovi elementi o aggiorna i metadati di quelli esistenti, conservandone decisioni e analisi.
    func upsert(_ fresh: [IndexedItem]) {
        guard !fresh.isEmpty else { return }
        var restoredDecisions = false
        for item in fresh {
            let key = Self.sourceKey(item.source, item.sourceIdentifier)
            if let existingID = idBySourceKey[key], var existing = itemsByID[existingID] {
                existing.applyMetadata(from: item)
                itemsByID[existingID] = existing
            } else {
                itemsByID[item.id] = item
                idBySourceKey[key] = item.id
                // Un elemento che ricompare ritrova la decisione presa in precedenza.
                if let orphan = orphanRecords.removeValue(forKey: key) {
                    applyRecord(orphan, to: item.id)
                    restoredDecisions = true
                }
            }
        }
        if restoredDecisions {
            markedCount = markedIDs.count
        }
        didChange(index: true, review: restoredDecisions, immediate: false)
    }

    /// Rimuove dall'indice gli elementi di una sorgente che non risultano più presenti.
    /// Le decisioni prese su di essi vengono conservate, nel caso ricompaiano.
    @discardableResult
    func removeMissing(source: StorageSource, keeping identifiers: Set<String>) -> Int {
        var missing: [UUID] = []
        for (id, item) in itemsByID where item.source == source && !identifiers.contains(item.sourceIdentifier) {
            missing.append(id)
        }
        preserveDecisions(of: missing)
        remove(ids: missing)
        return missing.count
    }

    @discardableResult
    func removeMissing(inFolder folderID: UUID, keeping identifiers: Set<String>) -> Int {
        var missing: [UUID] = []
        for (id, item) in itemsByID where item.folderID == folderID && !identifiers.contains(item.sourceIdentifier) {
            missing.append(id)
        }
        preserveDecisions(of: missing)
        remove(ids: missing)
        return missing.count
    }

    private func preserveDecisions(of ids: [UUID]) {
        for id in ids {
            guard let item = itemsByID[id], let record = reviewRecord(for: item) else { continue }
            orphanRecords[record.sourceKey] = record
        }
    }

    /// Rimuove elementi dall'indice. Non tocca i file: serve dopo un'eliminazione riuscita
    /// o quando un contenuto non esiste più.
    func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let item = itemsByID.removeValue(forKey: id) else { continue }
            idBySourceKey.removeValue(forKey: Self.sourceKey(item.source, item.sourceIdentifier))
            markedIDs.remove(id)
        }
        pruneGroupsSilently()
        markedCount = markedIDs.count
        didChange(index: true, review: true, immediate: true)
    }

    func mutate(_ id: UUID, _ body: (inout IndexedItem) -> Void) {
        guard var item = itemsByID[id] else { return }
        body(&item)
        itemsByID[id] = item
        didChange(index: true, review: false, immediate: true)
    }

    /// Modifica più elementi con un'unica notifica alle viste.
    func mutateEach(_ ids: [UUID], _ body: (inout IndexedItem) -> Void) {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard var item = itemsByID[id] else { continue }
            body(&item)
            itemsByID[id] = item
        }
        didChange(index: true, review: false, immediate: true)
    }

    func apply(_ updates: [AnalysisUpdate]) {
        guard !updates.isEmpty else { return }
        for update in updates {
            guard var item = itemsByID[update.id] else { continue }
            update.apply(to: &item)
            itemsByID[update.id] = item
        }
        didChange(index: true, review: false, immediate: false)
    }

    func addTraits(_ traits: ItemTraits, to ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard var item = itemsByID[id] else { continue }
            item.traits.formUnion(traits)
            itemsByID[id] = item
        }
        didChange(index: true, review: false, immediate: false)
    }

    // MARK: - Gruppi

    /// Sostituisce i gruppi dei tipi indicati. Se `touching` è valorizzato, i gruppi esistenti
    /// che non contengono nessuno di quegli elementi vengono conservati (analisi incrementale).
    func replaceGroups(
        kinds: Set<GroupKind>,
        scope: GroupScope,
        touching processedIDs: Set<UUID>? = nil,
        with newGroups: [ItemGroup]
    ) {
        for (groupID, group) in groupsByID where kinds.contains(group.kind) && group.scope == scope {
            if let processedIDs, group.memberIDs.allSatisfy({ !processedIDs.contains($0) }) {
                continue
            }
            for memberID in group.memberIDs {
                unlink(memberID, from: group)
            }
            groupsByID.removeValue(forKey: groupID)
        }
        for group in newGroups where group.memberIDs.count >= 2 {
            groupsByID[group.id] = group
            for memberID in group.memberIDs {
                link(memberID, to: group)
            }
        }
        pruneGroupsSilently()
        didChange(index: true, review: false, immediate: false)
    }

    /// Elimina i gruppi rimasti con meno di due membri validi.
    func pruneGroups() {
        pruneGroupsSilently()
        didChange(index: true, review: false, immediate: false)
    }

    private func pruneGroupsSilently() {
        for (groupID, group) in groupsByID {
            let valid = group.memberIDs.filter { memberID in
                guard let member = itemsByID[memberID] else { return false }
                return group.kind.isDuplicateKind
                    ? member.duplicateGroupID == groupID
                    : member.similarityGroupID == groupID
            }
            if valid.count == group.memberIDs.count { continue }
            if valid.count < 2 {
                for memberID in valid {
                    unlink(memberID, from: group)
                }
                groupsByID.removeValue(forKey: groupID)
            } else {
                var updated = group
                updated.memberIDs = valid
                if let keepID = updated.suggestedKeepID, !valid.contains(keepID) {
                    updated.suggestedKeepID = nil
                    updated.suggestionReason = nil
                }
                groupsByID[groupID] = updated
            }
        }
    }

    private func link(_ id: UUID, to group: ItemGroup) {
        guard var item = itemsByID[id] else { return }
        if group.kind.isDuplicateKind {
            item.duplicateGroupID = group.id
        } else {
            item.similarityGroupID = group.id
        }
        itemsByID[id] = item
    }

    private func unlink(_ id: UUID, from group: ItemGroup) {
        guard var item = itemsByID[id] else { return }
        if group.kind.isDuplicateKind {
            if item.duplicateGroupID == group.id { item.duplicateGroupID = nil }
        } else if item.similarityGroupID == group.id {
            item.similarityGroupID = nil
        }
        itemsByID[id] = item
    }

    // MARK: - Decisioni dell'utente

    /// Cambia lo stato di revisione. Non elimina nulla: è soltanto un'etichetta sull'elemento.
    func setReviewStatus(_ status: ReviewStatus, for ids: [UUID], at date: Date = Date()) {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard var item = itemsByID[id] else { continue }
            item.reviewStatus = status
            item.decidedAt = status == .unreviewed ? nil : date
            itemsByID[id] = item
            if status.isQueuedForDeletion {
                markedIDs.insert(id)
            } else {
                markedIDs.remove(id)
            }
        }
        markedCount = markedIDs.count
        didChange(index: false, review: true, immediate: true)
    }

    /// Imposta la protezione esplicita o lo sblocco di una protezione automatica.
    /// Un elemento protetto esce sempre dalla lista di revisione delle eliminazioni.
    func setProtection(isProtected: Bool, override: Bool, for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard var item = itemsByID[id] else { continue }
            item.isProtected = isProtected
            item.protectionOverride = isProtected ? false : override
            if isProtected && item.reviewStatus.isQueuedForDeletion {
                item.reviewStatus = .unreviewed
                item.decidedAt = nil
                markedIDs.remove(id)
            }
            itemsByID[id] = item
        }
        markedCount = markedIDs.count
        didChange(index: false, review: true, immediate: true)
    }

    // MARK: - Notifiche e riepilogo

    private func didChange(index: Bool, review: Bool, immediate: Bool) {
        if immediate {
            revision &+= 1
        } else {
            scheduleRevisionBump()
        }
        scheduleSummary()
        if index { scheduleIndexSave() }
        if review { scheduleReviewSave() }
    }

    /// Durante le scansioni le modifiche arrivano a raffica: le viste vengono avvisate al massimo
    /// una volta ogni 700 ms.
    private func scheduleRevisionBump() {
        guard !revisionBumpPending else { return }
        revisionBumpPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self else { return }
            self.revisionBumpPending = false
            self.revision &+= 1
        }
    }

    /// Sospende il ricalcolo del riepilogo mentre l'utente sta scorrendo una sessione:
    /// ogni scelta lo renderebbe subito superato. Alla ripresa viene ricalcolato una volta sola.
    func pauseSummary(_ paused: Bool) {
        summaryPaused = paused
        if !paused && summaryDirty {
            scheduleSummary()
        }
    }

    private func scheduleSummary() {
        if summaryRunning || summaryPaused {
            summaryDirty = true
            return
        }
        summaryRunning = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            await self?.runSummaryLoop()
        }
    }

    private func runSummaryLoop() async {
        repeat {
            summaryDirty = false
            summary = await computeSummary()
        } while summaryDirty
        summaryRunning = false
    }

    private func computeSummary() async -> CatalogSummary {
        let items = Array(itemsByID.values)
        let groups = Array(groupsByID.values)
        let evaluator = evaluatorProvider()
        let context = contextProvider()
        return await Task.detached(priority: .utility) {
            CatalogSummary.compute(items: items, groups: groups, evaluator: evaluator, context: context)
        }.value
    }

    /// Ricalcola subito il riepilogo (es. al termine di una scansione o dopo un cambio di regole).
    func refreshSummaryNow() async {
        summary = await computeSummary()
        revision &+= 1
    }

    // MARK: - Persistenza

    func load() async {
        guard !isLoaded else { return }
        let files = self.files
        let loaded = await Task.detached(priority: .userInitiated) { () -> (IndexSnapshot?, [ReviewRecord]?) in
            let snapshot = files.load(IndexSnapshot.self, from: indexFileName)
            let records = files.load([ReviewRecord].self, from: reviewFileName)
            return (snapshot, records)
        }.value

        if let snapshot = loaded.0, snapshot.version == indexSchemaVersion {
            for var item in snapshot.items {
                // Le decisioni valide sono solo quelle del file dedicato, applicate qui sotto.
                item.reviewStatus = .unreviewed
                item.isProtected = false
                item.protectionOverride = false
                item.decidedAt = nil
                itemsByID[item.id] = item
                idBySourceKey[Self.sourceKey(item.source, item.sourceIdentifier)] = item.id
            }
            for group in snapshot.groups {
                groupsByID[group.id] = group
            }
        }

        if let records = loaded.1 {
            // Le decisioni rimaste senza elemento vengono tenute da parte per tre mesi.
            let cutoff = Date().addingTimeInterval(-90 * 86_400)
            for record in records {
                if itemsByID[record.id] != nil {
                    applyRecord(record, to: record.id)
                } else if let id = idBySourceKey[record.sourceKey] {
                    applyRecord(record, to: id)
                } else if record.isProtected || (record.decidedAt ?? Date()) > cutoff {
                    orphanRecords[record.sourceKey] = record
                }
            }
        }

        markedCount = markedIDs.count
        isLoaded = true
        await refreshSummaryNow()
    }

    private func applyRecord(_ record: ReviewRecord, to id: UUID) {
        guard var item = itemsByID[id] else { return }
        item.reviewStatus = record.status
        item.isProtected = record.isProtected
        item.protectionOverride = record.protectionOverride
        item.decidedAt = record.decidedAt
        itemsByID[id] = item
        if record.status.isQueuedForDeletion {
            markedIDs.insert(id)
        } else {
            markedIDs.remove(id)
        }
    }

    /// Decisione da salvare per un elemento, oppure `nil` se è ancora nello stato iniziale.
    private func reviewRecord(for item: IndexedItem) -> ReviewRecord? {
        let isDefault = item.reviewStatus == .unreviewed && !item.isProtected && !item.protectionOverride
        guard !isDefault else { return nil }
        return ReviewRecord(
            id: item.id,
            sourceKey: Self.sourceKey(item.source, item.sourceIdentifier),
            status: item.reviewStatus,
            isProtected: item.isProtected,
            protectionOverride: item.protectionOverride,
            decidedAt: item.decidedAt
        )
    }

    private func reviewRecords() -> [ReviewRecord] {
        var records = Array(orphanRecords.values)
        for item in itemsByID.values {
            if let record = reviewRecord(for: item) {
                records.append(record)
            }
        }
        return records
    }

    private func scheduleIndexSave() {
        if indexSaveRunning {
            indexDirty = true
            return
        }
        indexSaveRunning = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.runIndexSaveLoop()
        }
    }

    private func runIndexSaveLoop() async {
        repeat {
            indexDirty = false
            await writeIndex()
        } while indexDirty
        indexSaveRunning = false
    }

    private func writeIndex() async {
        let snapshot = IndexSnapshot(
            version: indexSchemaVersion,
            items: Array(itemsByID.values),
            groups: Array(groupsByID.values)
        )
        let files = self.files
        await Task.detached(priority: .utility) {
            try? files.save(snapshot, as: indexFileName)
        }.value
    }

    private func scheduleReviewSave() {
        if reviewSaveRunning {
            reviewDirty = true
            return
        }
        reviewSaveRunning = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.runReviewSaveLoop()
        }
    }

    private func runReviewSaveLoop() async {
        repeat {
            reviewDirty = false
            await writeReview()
        } while reviewDirty
        reviewSaveRunning = false
    }

    private func writeReview() async {
        let records = reviewRecords()
        let files = self.files
        await Task.detached(priority: .userInitiated) {
            try? files.save(records, as: reviewFileName)
        }.value
    }

    /// Salva subito tutto: va chiamato quando l'app passa in background.
    func flush() async {
        await writeReview()
        await writeIndex()
    }
}
