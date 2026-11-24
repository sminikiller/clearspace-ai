import Foundation

/// Situazione di un gruppo di simili o di duplicati rispetto alle scelte dell'utente.
struct GroupReviewSummary: Equatable, Sendable {
    /// Elementi ancora da decidere: mai visti o rimandati, e non protetti.
    var pendingCount: Int
    /// Spazio che si libererebbe tenendo solo le migliori: gli elementi da decidere diversi da quelli
    /// da tenere (le stelle dell'utente o, se non ce ne sono, quello consigliato).
    var potentialBytes: Int64

    /// Non resta nulla da decidere: ogni elemento è conservato, proposto oppure protetto.
    var isDecided: Bool { pendingCount == 0 }
}

/// Revisione dei gruppi uno dopo l'altro: quali restano da decidere e in che ordine proporli.
/// Sono solo conteggi e ordinamenti: nessuna di queste funzioni decide o elimina qualcosa.
enum GroupReview {

    static func summary(
        members: [IndexedItem],
        suggestedID: UUID?,
        evaluator: ProtectionEvaluator
    ) -> GroupReviewSummary {
        let keepers = GroupChoice.preferredKeepers(members: members, suggestedID: suggestedID)
        var pending = 0
        var potential: Int64 = 0
        for member in members where evaluator.isReviewable(member) {
            pending += 1
            if !keepers.contains(member.id) {
                potential += member.bytes
            }
        }
        return GroupReviewSummary(pendingCount: pending, potentialBytes: potential)
    }

    /// Ordine dell'elenco: prima i gruppi da decidere, da quello che libera più spazio; poi quelli già
    /// decisi. A parità resta l'ordine di partenza.
    static func ordered<Value>(_ values: [Value], summary: (Value) -> GroupReviewSummary) -> [Value] {
        let indexed = values.enumerated().map { (offset: $0.offset, value: $0.element, summary: summary($0.element)) }
        return indexed.sorted { first, second in
            if first.summary.isDecided != second.summary.isDecided {
                return !first.summary.isDecided
            }
            if first.summary.potentialBytes != second.summary.potentialBytes {
                return first.summary.potentialBytes > second.summary.potentialBytes
            }
            return first.offset < second.offset
        }
        .map { $0.value }
    }

    /// Gruppi da proporre uno dopo l'altro, nell'ordine ricevuto: quelli ancora da decidere oppure,
    /// se sono già tutti decisi, tutti quanti, per ricontrollarli.
    static func sequence<Value>(_ values: [Value], summary: (Value) -> GroupReviewSummary) -> [Value] {
        let pending = values.filter { !summary($0).isDecided }
        return pending.isEmpty ? values : pending
    }

    /// Posizione del prossimo gruppo da mostrare a partire da `start`: salta quelli che nel frattempo
    /// non esistono più (per esempio dopo una nuova analisi). Restituisce `count` se non ne restano.
    static func nextAvailable(from start: Int, count: Int, isAvailable: (Int) -> Bool) -> Int {
        var position = max(0, start)
        while position < count && !isAvailable(position) {
            position += 1
        }
        return min(position, count)
    }
}

/// Scelta in corso nella galleria di un gruppo: quali elementi eliminare e quali tenere.
///
/// All'apertura c'è una proposta: le decisioni già prese restano, si tengono le migliori (le stelle
/// dell'utente o, se non ce ne sono, quella consigliata) e si propongono le altre. Ogni tocco
/// dell'utente cambia un singolo elemento rispetto alla proposta. Nulla di tutto questo viene salvato
/// finché non si conferma una scelta.
enum GroupProposal {

    /// Elementi da eliminare secondo la proposta iniziale.
    /// - Proposti per l'eliminazione (o non riusciti) → da eliminare; conservati → da tenere.
    /// - Stelle ed elementi protetti restano sempre.
    /// - Da decidere o rimandati: si tengono le migliori e si propongono gli altri; senza stelle e senza
    ///   consiglio non si propone nulla.
    static func initialDeletion(
        members: [IndexedItem],
        suggestedID: UUID?,
        isLocked: (IndexedItem) -> Bool
    ) -> Set<UUID> {
        let keepers = GroupChoice.preferredKeepers(members: members, suggestedID: suggestedID)
        var result = Set<UUID>()
        for member in members where !member.isStarred && !isLocked(member) {
            switch member.reviewStatus {
            case .markedForDeletion, .deletionFailed:
                result.insert(member.id)
            case .kept:
                continue
            case .unreviewed, .postponed:
                if !keepers.isEmpty && !keepers.contains(member.id) {
                    result.insert(member.id)
                }
            }
        }
        return result
    }

    /// La proposta con le scelte fatte a mano: `overrides` vale `true` per «elimina», `false` per «tieni».
    /// Gli elementi bloccati non vengono mai eliminati.
    static func deletion(proposal: Set<UUID>, overrides: [UUID: Bool], locked: Set<UUID>) -> Set<UUID> {
        var result = proposal
        for (id, deletes) in overrides {
            if deletes {
                result.insert(id)
            } else {
                result.remove(id)
            }
        }
        return result.subtracting(locked)
    }

    /// Scelte a mano che, applicate alla proposta, danno `deletion`. Gli elementi bloccati restano fuori.
    static func overrides(
        for deletion: Set<UUID>,
        proposal: Set<UUID>,
        memberIDs: [UUID],
        locked: Set<UUID>
    ) -> [UUID: Bool] {
        var result: [UUID: Bool] = [:]
        for id in memberIDs where !locked.contains(id) {
            let deletes = deletion.contains(id)
            if deletes != proposal.contains(id) {
                result[id] = deletes
            }
        }
        return result
    }

    /// Divide i membri, nell'ordine del gruppo, tra quelli da tenere e quelli da eliminare.
    static func split(memberIDs: [UUID], deletion: Set<UUID>) -> (keep: [UUID], delete: [UUID]) {
        var keep: [UUID] = []
        var delete: [UUID] = []
        for id in memberIDs {
            if deletion.contains(id) {
                delete.append(id)
            } else {
                keep.append(id)
            }
        }
        return (keep, delete)
    }
}
