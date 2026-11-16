import Foundation

/// Tutto ciò che serve per costruire una coda di revisione. È un valore: può viaggiare tra thread.
struct PlannerInput: Sendable {
    var items: [IndexedItem]
    var groups: [ItemGroup]
    var evaluator: ProtectionEvaluator
    var scorer: RecoverabilityScorer
    var context: CollectionContext
}

/// Costruisce le code di revisione per le diverse modalità di pulizia.
/// Le code contengono soltanto elementi non protetti e non ancora decisi; comparire in una coda
/// significa "vale la pena guardarlo", non "va eliminato".
enum CleanupPlanner {

    static func reviewableItems(_ input: PlannerInput) -> [IndexedItem] {
        input.items.filter { input.evaluator.isReviewable($0) }
    }

    /// Ordina per punteggio di recuperabilità decrescente.
    static func orderedIDs(_ items: [IndexedItem], scorer: RecoverabilityScorer) -> [UUID] {
        let scored = items.map { (id: $0.id, value: scorer.score($0)) }
        return scored.sorted { $0.value > $1.value }.map { $0.id }
    }

    /// Membri "in più" dei gruppi indicati: tutti tranne il candidato suggerito da conservare.
    static func groupExtras(_ input: PlannerInput, kinds: Set<GroupKind>) -> [IndexedItem] {
        var itemsByID: [UUID: IndexedItem] = [:]
        itemsByID.reserveCapacity(input.items.count)
        for item in input.items { itemsByID[item.id] = item }

        var result: [IndexedItem] = []
        var seen = Set<UUID>()
        for group in input.groups where kinds.contains(group.kind) {
            let members = group.memberIDs.compactMap { itemsByID[$0] }
            guard members.count >= 2 else { continue }
            let keepID = group.suggestedKeepID ?? members.max(by: { $0.bytes < $1.bytes })?.id
            for member in members where member.id != keepID {
                guard input.evaluator.isReviewable(member), seen.insert(member.id).inserted else { continue }
                result.append(member)
            }
        }
        return result
    }

    /// Pulizia rapida: duplicati certi, video grandi e screenshot vecchi, limitati a `limit` elementi.
    static func quickQueue(_ input: PlannerInput, limit: Int) -> [UUID] {
        var candidates = groupExtras(input, kinds: [.exactDuplicate])
        var seen = Set(candidates.map { $0.id })
        for item in input.items {
            guard !seen.contains(item.id), input.evaluator.isReviewable(item) else { continue }
            if SmartCollection.largeVideos.contains(item, context: input.context)
                || SmartCollection.oldScreenshots.contains(item, context: input.context) {
                seen.insert(item.id)
                candidates.append(item)
            }
        }
        return Array(orderedIDs(candidates, scorer: input.scorer).prefix(max(1, limit)))
    }

    static func queue(
        for collection: SmartCollection,
        _ input: PlannerInput,
        sort: ItemSort = .recoverability
    ) -> [UUID] {
        let members = input.items.filter {
            input.evaluator.isReviewable($0) && collection.contains($0, context: input.context)
        }
        return ItemFilter.sorted(members, by: sort, score: { input.scorer.score($0) }).map { $0.id }
    }

    static func queue(for filter: ItemFilter, _ input: PlannerInput) -> [UUID] {
        let reviewable = reviewableItems(input)
        return filter
            .apply(to: reviewable, evaluator: input.evaluator, score: { input.scorer.score($0) })
            .map { $0.id }
    }

    /// Coda di un passo della pulizia guidata.
    static func guidedQueue(_ step: GuidedStepKind, _ input: PlannerInput, limit: Int? = nil) -> [UUID] {
        var ids: [UUID]
        switch step {
        case .screenshots:
            ids = queue(for: .screenshots, input, sort: .oldestFirst)
        case .similarPhotos:
            let extras = groupExtras(input, kinds: [.exactDuplicate, .visualDuplicate, .similar, .burst])
                .filter { $0.category == .photo }
            ids = orderedIDs(extras, scorer: input.scorer)
        case .videos:
            let videos = input.items.filter { item in
                input.evaluator.isReviewable(item)
                    && (SmartCollection.largeVideos.contains(item, context: input.context)
                        || SmartCollection.screenRecordings.contains(item, context: input.context)
                        || SmartCollection.duplicateVideos.contains(item, context: input.context))
            }
            ids = ItemFilter.sorted(videos, by: .sizeDescending).map { $0.id }
        case .documents:
            let documents = input.items.filter { item in
                input.evaluator.isReviewable(item)
                    && (SmartCollection.duplicateFiles.contains(item, context: input.context)
                        || SmartCollection.largeFiles.contains(item, context: input.context)
                        || SmartCollection.downloads.contains(item, context: input.context))
            }
            ids = orderedIDs(documents, scorer: input.scorer)
        case .audio:
            ids = queue(for: .allAudio, input, sort: .sizeDescending)
        case .otherApps, .iCloud:
            ids = []
        }
        if let limit, limit > 0, ids.count > limit {
            ids = Array(ids.prefix(limit))
        }
        return ids
    }

    /// Pulizia annuale: tutti i contenuti dell'anno, in ordine cronologico.
    static func annualQueue(year: Int, _ input: PlannerInput, calendar: Calendar = .current) -> [UUID] {
        let members = input.items.filter { item in
            guard input.evaluator.isReviewable(item), let date = item.createdAt else { return false }
            return calendar.component(.year, from: date) == year
        }
        return ItemFilter.sorted(members, by: .oldestFirst).map { $0.id }
    }

    /// Pulizia per obiettivo: gli elementi più promettenti, fino a coprire con margine lo spazio richiesto
    /// (l'utente ne conserverà una parte).
    static func goalQueue(targetBytes: Int64, _ input: PlannerInput) -> [UUID] {
        let reviewable = reviewableItems(input)
        var itemsByID: [UUID: IndexedItem] = [:]
        for item in reviewable { itemsByID[item.id] = item }

        let budget = targetBytes > Int64.max / 2 ? Int64.max : targetBytes * 2
        var accumulated: Int64 = 0
        var result: [UUID] = []
        for id in orderedIDs(reviewable, scorer: input.scorer) {
            guard let item = itemsByID[id], item.bytes > 0 else { continue }
            result.append(id)
            accumulated += item.bytes
            if accumulated >= budget { break }
        }
        return result
    }

    /// Riordina una coda in modo che gli scatti di uno stesso gruppo siano vicini, con quello
    /// consigliato per primo: così un gruppo di foto simili si decide in un colpo solo invece di
    /// ritrovarne i membri sparsi nella sessione. I gruppi restano nell'ordine in cui compare il loro
    /// primo membro; gli elementi senza gruppo non si spostano rispetto agli altri.
    static func clusteredByGroup(_ queue: [UUID], groupOf: (UUID) -> ItemGroup?) -> [UUID] {
        let inQueue = Set(queue)
        var placed = Set<UUID>()
        var result: [UUID] = []
        result.reserveCapacity(queue.count)

        for id in queue {
            if placed.contains(id) { continue }
            guard let group = groupOf(id) else {
                placed.insert(id)
                result.append(id)
                continue
            }
            var members = group.memberIDs.filter { inQueue.contains($0) && !placed.contains($0) }
            if let keepID = group.suggestedKeepID, let index = members.firstIndex(of: keepID) {
                members.remove(at: index)
                members.insert(keepID, at: 0)
            }
            if !members.contains(id) {
                members.append(id)
            }
            for member in members where placed.insert(member).inserted {
                result.append(member)
            }
        }
        return result
    }

    /// Spazio potenziale complessivo degli elementi indicati.
    static func potentialBytes(of ids: [UUID], _ input: PlannerInput) -> Int64 {
        let wanted = Set(ids)
        return input.items.reduce(0) { $0 + (wanted.contains($1.id) ? $1.bytes : 0) }
    }
}
