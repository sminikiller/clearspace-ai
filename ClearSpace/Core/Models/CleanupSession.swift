import Foundation

/// Scelta espressa con uno swipe (o con il pulsante equivalente).
enum SwipeChoice: String, Codable, Sendable {
    case keep
    case delete
    case postpone
}

/// Passi della pulizia guidata, nell'ordine in cui vengono proposti.
enum GuidedStepKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case screenshots
    case similarPhotos
    case videos
    case documents
    case audio
    case otherApps
    case iCloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots: return "Screenshot"
        case .similarPhotos: return "Foto simili e duplicate"
        case .videos: return "Video"
        case .documents: return "Documenti e download"
        case .audio: return "Audio e registrazioni"
        case .otherApps: return "Altre app"
        case .iCloud: return "iCloud"
        }
    }

    var subtitle: String {
        switch self {
        case .screenshots: return "Schermate vecchie, ricevute e conversazioni"
        case .similarPhotos: return "Raffiche, scatti consecutivi e copie"
        case .videos: return "Video grandi e registrazioni dello schermo"
        case .documents: return "File duplicati, pesanti e scaricati"
        case .audio: return "Registrazioni lunghe o ripetute"
        case .otherApps: return "Consigli per WhatsApp, Telegram, streaming e altre app"
        case .iCloud: return "Backup, dati delle app e copie locali"
        }
    }

    var systemImage: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .similarPhotos: return "square.on.square"
        case .videos: return "video"
        case .documents: return "doc.on.doc"
        case .audio: return "waveform"
        case .otherApps: return "square.grid.2x2"
        case .iCloud: return "icloud"
        }
    }

    /// I passi finali sono consigli guidati, non sessioni di swipe.
    var usesSwipe: Bool {
        self != .otherApps && self != .iCloud
    }
}

/// Modalità con cui è stata avviata una sessione.
enum CleanupMode: Codable, Hashable, Sendable {
    case quick
    case guided(step: GuidedStepKind)
    case advanced
    case annual(year: Int)
    case collection(id: String)
    case goal(targetBytes: Int64)
    case group
    case search(query: String)
    case custom

    var label: String {
        switch self {
        case .quick: return "Pulizia rapida"
        case .guided: return "Pulizia guidata"
        case .advanced: return "Pulizia avanzata"
        case .annual(let year): return "Pulizia annuale \(year)"
        case .collection: return "Categoria"
        case .goal: return "Pulizia per obiettivo"
        case .group: return "Gruppo"
        case .search: return "Ricerca"
        case .custom: return "Selezione"
        }
    }
}

/// Decisione registrata in una sessione; conserva lo stato precedente per poterla annullare.
struct SwipeDecision: Codable, Hashable, Sendable {
    let itemID: UUID
    let choice: SwipeChoice
    let previousStatus: ReviewStatus
    let bytes: Int64
    let date: Date
    /// Decisioni prese insieme (es. "tieni solo la migliore" su un gruppo di foto simili):
    /// condividono lo stesso identificativo e si annullano con un solo gesto.
    var batchID: UUID?

    init(
        itemID: UUID,
        choice: SwipeChoice,
        previousStatus: ReviewStatus,
        bytes: Int64,
        date: Date,
        batchID: UUID? = nil
    ) {
        self.itemID = itemID
        self.choice = choice
        self.previousStatus = previousStatus
        self.bytes = bytes
        self.date = date
        self.batchID = batchID
    }
}

/// Scelta su un elemento, da registrare in blocco insieme ad altre.
struct BatchChoice: Equatable, Sendable {
    let itemID: UUID
    let choice: SwipeChoice
    let previousStatus: ReviewStatus
    let bytes: Int64
}

/// Sessione di pulizia. Viene salvata a ogni decisione, quindi può essere ripresa in qualsiasi momento.
struct CleanupSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var mode: CleanupMode
    var queue: [UUID]
    var cursor: Int
    var decisions: [SwipeDecision]
    var goalBytes: Int64?
    var createdAt: Date
    var updatedAt: Date
    var isCompleted: Bool
    /// Elemento che l'utente ha portato in primo piano, ad esempio toccando uno dei video simili
    /// mostrati sotto la carta. Resta visibile anche se è già stato deciso, finché non si prende
    /// una nuova decisione: serve a riguardarlo e, se si vuole, a cambiare idea.
    var focusedItemID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        mode: CleanupMode,
        queue: [UUID],
        goalBytes: Int64? = nil,
        now: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.queue = queue
        self.cursor = 0
        self.decisions = []
        self.goalBytes = goalBytes
        self.createdAt = now
        self.updatedAt = now
        self.isCompleted = false
    }

    var currentItemID: UUID? {
        itemID(atOffset: 0)
    }

    func itemID(atOffset offset: Int) -> UUID? {
        let index = cursor + offset
        guard index >= 0, index < queue.count else { return nil }
        return queue[index]
    }

    var isFinished: Bool { cursor >= queue.count }
    var remainingCount: Int { max(0, queue.count - cursor) }

    var progress: Double {
        guard !queue.isEmpty else { return 1 }
        return min(1, Double(cursor) / Double(queue.count))
    }

    /// Decisione in vigore per ciascun elemento, in ordine di tempo. Un elemento riconsiderato
    /// (prima scartato, poi tenuto) conta una volta sola, con l'ultima scelta.
    var standingDecisions: [SwipeDecision] {
        var seen = Set<UUID>()
        var latestFirst: [SwipeDecision] = []
        for decision in decisions.reversed() where seen.insert(decision.itemID).inserted {
            latestFirst.append(decision)
        }
        return Array(latestFirst.reversed())
    }

    /// Elementi su cui è stata presa una decisione in questa sessione.
    var examinedCount: Int { standingDecisions.count }

    var keptCount: Int { count(of: .keep) }
    var markedCount: Int { count(of: .delete) }
    var postponedCount: Int { count(of: .postpone) }

    /// Spazio potenziale degli elementi proposti per l'eliminazione in questa sessione.
    var markedBytes: Int64 {
        standingDecisions.reduce(0) { $0 + ($1.choice == .delete ? $1.bytes : 0) }
    }

    var postponedIDs: [UUID] {
        standingDecisions.filter { $0.choice == .postpone }.map { $0.itemID }
    }

    var goalProgress: Double? {
        guard let goalBytes, goalBytes > 0 else { return nil }
        return min(1, Double(markedBytes) / Double(goalBytes))
    }

    var goalReached: Bool {
        guard let goalBytes, goalBytes > 0 else { return false }
        return markedBytes >= goalBytes
    }

    private func count(of choice: SwipeChoice) -> Int {
        standingDecisions.reduce(0) { $0 + ($1.choice == choice ? 1 : 0) }
    }

    /// Registra la decisione sull'elemento corrente e passa al successivo.
    mutating func record(_ choice: SwipeChoice, previousStatus: ReviewStatus, bytes: Int64, at date: Date = Date()) {
        guard let itemID = currentItemID else { return }
        decisions.append(
            SwipeDecision(itemID: itemID, choice: choice, previousStatus: previousStatus, bytes: bytes, date: date)
        )
        cursor += 1
        focusedItemID = nil
        updatedAt = date
    }

    /// Porta in primo piano un elemento scelto dall'utente: diventa quello corrente, pronto per essere
    /// guardato e deciso. Se è più avanti nella coda viene anticipato; se non c'è, o è già stato
    /// superato, viene inserito nella posizione corrente (le posizioni passate restano dove sono,
    /// perché servono all'annullamento).
    mutating func bringToFront(_ itemID: UUID, at date: Date = Date()) {
        focusedItemID = itemID
        isCompleted = false
        updatedAt = date
        guard currentItemID != itemID else { return }
        let position = min(cursor, queue.count)
        if let ahead = queue[position...].firstIndex(of: itemID) {
            queue.remove(at: ahead)
        }
        queue.insert(itemID, at: position)
        cursor = position
    }

    /// Salta l'elemento corrente senza registrare decisioni (es. file non più disponibile).
    mutating func skipCurrent(at date: Date = Date()) {
        guard !isFinished else { return }
        cursor += 1
        updatedAt = date
    }

    /// Annulla l'ultima decisione e riporta il cursore su quell'elemento.
    mutating func undoLast(at date: Date = Date()) -> SwipeDecision? {
        guard let last = decisions.popLast() else { return nil }
        let upperBound = min(cursor, queue.count)
        if let index = queue[..<upperBound].lastIndex(of: last.itemID) {
            cursor = index
        } else {
            cursor = max(0, cursor - 1)
        }
        focusedItemID = nil
        isCompleted = false
        updatedAt = date
        return last
    }

    /// Registra più decisioni prese insieme, ad esempio su un gruppo di foto simili.
    /// Il cursore non si sposta: gli elementi già decisi vengono saltati quando arriva il loro turno
    /// (vedi `SessionManager`). Le decisioni condividono `batchID` e si annullano insieme.
    mutating func recordBatch(_ choices: [BatchChoice], batchID: UUID = UUID(), at date: Date = Date()) {
        guard !choices.isEmpty else { return }
        for entry in choices {
            decisions.append(
                SwipeDecision(
                    itemID: entry.itemID,
                    choice: entry.choice,
                    previousStatus: entry.previousStatus,
                    bytes: entry.bytes,
                    date: date,
                    batchID: batchID
                )
            )
        }
        // Dopo una scelta sull'intero gruppo si prosegue: l'elemento in primo piano non va trattenuto.
        focusedItemID = nil
        updatedAt = date
    }

    /// Annulla l'ultima mossa: una decisione singola oppure tutte quelle prese in blocco.
    /// Il cursore torna sul primo degli elementi annullati già superati; quelli ancora da raggiungere
    /// non lo spostano. Restituisce le decisioni annullate, dalla più recente.
    mutating func undoLastMove(at date: Date = Date()) -> [SwipeDecision] {
        guard let last = decisions.last else { return [] }
        guard let batchID = last.batchID else {
            if let single = undoLast(at: date) { return [single] }
            return []
        }
        var undone: [SwipeDecision] = []
        while let candidate = decisions.last, candidate.batchID == batchID {
            decisions.removeLast()
            undone.append(candidate)
        }
        let upperBound = min(cursor, queue.count)
        let passed = undone.compactMap { queue[..<upperBound].lastIndex(of: $0.itemID) }
        if let earliest = passed.min() {
            cursor = earliest
        }
        focusedItemID = nil
        isCompleted = false
        updatedAt = date
        return undone
    }

    /// Rimette in coda gli elementi rimandati, per rivederli alla fine.
    mutating func requeuePostponed(at date: Date = Date()) {
        let postponed = postponedIDs
        guard !postponed.isEmpty else { return }
        decisions.removeAll { $0.choice == .postpone }
        queue.append(contentsOf: postponed)
        isCompleted = false
        updatedAt = date
    }
}
