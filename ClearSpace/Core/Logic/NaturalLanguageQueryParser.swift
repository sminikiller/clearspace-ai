import Foundation

/// Risultato dell'interpretazione di una richiesta scritta in linguaggio naturale.
struct ParsedQuery: Equatable, Sendable {
    var filter: ItemFilter
    /// Ciò che è stato capito, in forma leggibile: viene mostrato all'utente come etichette.
    var interpretations: [String]

    var understoodSomething: Bool { !interpretations.isEmpty }
}

/// Traduce richieste come "screenshot più vecchi di un anno che contengono testo" in un `ItemFilter`.
/// Funziona interamente sul dispositivo, con regole in italiano e in inglese: nessun testo viene inviato in rete.
struct NaturalLanguageQueryParser {
    var now: Date
    var calendar: Calendar

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    func parse(_ query: String) -> ParsedQuery {
        var text = " " + Self.normalize(query) + " "
        var filter = ItemFilter()
        var notes: [String] = []

        // Frasi tra virgolette: ricerca testuale letterale.
        while let groups = Self.consume("\"([^\"]+)\"", in: &text) {
            let phrase = groups[1].trimmingCharacters(in: .whitespaces)
            if !phrase.isEmpty {
                filter.textTokens.append(phrase)
                notes.append("Contiene «\(phrase)»")
            }
        }
        text = text.replacingOccurrences(of: "\"", with: " ")

        let number = "(\\d+(?:[.,]\\d+)?)"
        let sizeUnit = "(kb|mb|gb|tb|mega|giga)"
        let countWord = "(un|uno|una|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|one|two|three|\\d+)"
        let timeUnit = "(giorn[oi]|settiman[ae]|mes[ei]|ann[oi]|days?|weeks?|months?|years?)"
        let durationUnit = "(secondi|secondo|sec|minuti|minuto|min|ore|ora|seconds?|minutes?|hours?)"

        // Dimensione
        let largerThan = "(?:oltre i?|piu di|sopra i?|superiori? a|maggiori? di|piu grandi di|piu pesanti di|almeno|larger than|bigger than|more than|over)"
        if let groups = Self.consume("\(largerThan) ?\(number) ?\(sizeUnit)\\b", in: &text),
           let bytes = Self.bytes(groups[1], unit: groups[2]) {
            filter.minBytes = bytes
            notes.append("Oltre \(Format.bytes(bytes))")
        }
        let smallerThan = "(?:meno di|sotto i?|inferiori? a|minori? di|piu piccol[ie] di|smaller than|less than|under)"
        if let groups = Self.consume("\(smallerThan) ?\(number) ?\(sizeUnit)\\b", in: &text),
           let bytes = Self.bytes(groups[1], unit: groups[2]) {
            filter.maxBytes = bytes
            notes.append("Meno di \(Format.bytes(bytes))")
        }

        // Durata
        if let groups = Self.consume("(?:piu lunghi di|oltre i?|piu di|almeno|longer than|over) ?(\\d+) ?\(durationUnit)\\b", in: &text),
           let seconds = Self.seconds(groups[1], unit: groups[2]) {
            filter.minDuration = seconds
            notes.append("Più lunghi di \(Format.duration(seconds))")
        }
        if let groups = Self.consume("(?:piu brevi di|piu corti di|meno di|shorter than|under) ?(\\d+) ?\(durationUnit)\\b", in: &text),
           let seconds = Self.seconds(groups[1], unit: groups[2]) {
            filter.maxDuration = seconds
            notes.append("Più brevi di \(Format.duration(seconds))")
        }

        // Età: "più vecchi di un anno"
        if let groups = Self.consume("(?:piu vecch\\w* di|da piu di|piu di|oltre|older than|more than) ?\(countWord) ?\(timeUnit)(?: fa| ago)?\\b", in: &text),
           let date = dateBySubtracting(groups[1], unit: groups[2]) {
            filter.createdBefore = date
            notes.append("Più vecchi di \(Self.describe(groups[1], unit: groups[2]))")
        }

        // Periodi relativi
        if Self.consume("(?:l )?anno scorso|scorso anno|last year", in: &text) != nil {
            filter.year = calendar.component(.year, from: now) - 1
            notes.append("Anno \(filter.year ?? 0)")
        }
        if Self.consume("quest anno|this year", in: &text) != nil {
            filter.year = calendar.component(.year, from: now)
            notes.append("Anno \(filter.year ?? 0)")
        }
        if Self.consume("(?:il )?mese scorso|scorso mese|last month", in: &text) != nil,
           let previous = calendar.date(byAdding: .month, value: -1, to: now) {
            filter.year = calendar.component(.year, from: previous)
            filter.month = calendar.component(.month, from: previous)
            notes.append(Format.monthYear(previous))
        }
        if Self.consume("questo mese|this month", in: &text) != nil {
            filter.year = calendar.component(.year, from: now)
            filter.month = calendar.component(.month, from: now)
            notes.append(Format.monthYear(now))
        }
        let recent = "(?:negli ultimi|nelle ultime|nell ultim[oa]|dell ultim[oa]|degli ultimi|delle ultime|ultim[oaie]|last|past)"
        if let groups = Self.consume("\(recent) ?\(countWord)? ?\(timeUnit)\\b", in: &text) {
            let amount = groups[1].isEmpty ? "1" : groups[1]
            if let date = dateBySubtracting(amount, unit: groups[2]) {
                filter.createdAfter = date
                notes.append("Recenti: \(Self.describe(amount, unit: groups[2]))")
            }
        }

        // Mese (con anno facoltativo) e anno
        let monthNames = Self.months.map { $0.name }.joined(separator: "|")
        if let groups = Self.consume("\\b(\(monthNames))\\b(?: (?:del |di |of )?((?:19|20)\\d{2}))?", in: &text),
           let month = Self.months.first(where: { $0.name == groups[1] }) {
            filter.month = month.number
            if let year = Int(groups[2]) { filter.year = year }
            let yearText = groups[2].isEmpty ? "" : " \(groups[2])"
            notes.append("Mese: \(month.label)\(yearText)")
        }
        if let groups = Self.consume("(?:\\b(?:del|nel|dal|dell anno|anno|in|from|of)\\b ?)?\\b((?:19|20)\\d{2})\\b", in: &text),
           let year = Int(groups[1]) {
            filter.year = year
            notes.append("Anno \(year)")
        }

        // Numero massimo di risultati: "i 20 video più pesanti"
        if let groups = Self.consume("\\b(?:i|le|gli|primi|prime|top|first) (\\d{1,4})\\b", in: &text),
           let limit = Int(groups[1]), limit > 0 {
            filter.limit = limit
            notes.append("Primi \(limit)")
        }

        func rule(_ pattern: String, _ note: String, _ change: (inout ItemFilter) -> Void) {
            if Self.consume(pattern, in: &text) != nil {
                change(&filter)
                notes.append(note)
            }
        }

        // Tipi di contenuto (le regole più specifiche vengono prima)
        rule("registrazion\\w* (?:dello |di |dell[oa] )?schermo|screen ?record\\w*", "Registrazioni schermo") {
            $0.categories.insert(.video)
            $0.requiredTraits.insert(.screenRecording)
        }
        rule("screenshot\\w*|schermat\\w*|istantane\\w* (?:dello |di )?schermo", "Screenshot") {
            $0.categories.insert(.photo)
            $0.requiredTraits.insert(.screenshot)
        }
        rule("memo vocal\\w*|note vocal\\w*|messagg\\w* vocal\\w*|registrazion\\w*(?: audio)?|\\baudio\\b|\\bvocal[ei]\\b|recording\\w*", "Audio") {
            $0.categories.insert(.audio)
        }
        rule("\\b4k\\b", "4K") {
            $0.categories.insert(.video)
            $0.requiredTraits.insert(.video4K)
        }
        rule("slow ?motion|slo-?mo|rallentator\\w*|moviola", "Slow motion") {
            $0.categories.insert(.video)
            $0.requiredTraits.insert(.slowMotion)
        }
        rule("video\\w*|filmat\\w*", "Video") { $0.categories.insert(.video) }
        rule("selfie\\w*", "Selfie") {
            $0.categories.insert(.photo)
            $0.requiredTraits.insert(.selfie)
        }
        rule("live ?photo\\w*", "Live Photo") {
            $0.categories.insert(.photo)
            $0.requiredTraits.insert(.livePhoto)
        }
        rule("raffic\\w*|burst\\w*", "Raffiche") {
            $0.categories.insert(.photo)
            $0.requiredTraits.insert(.burst)
        }
        rule("panoram\\w*", "Panoramiche") {
            $0.categories.insert(.photo)
            $0.requiredTraits.insert(.panorama)
        }
        rule("ritratt\\w*|portrait\\w*", "Ritratti") {
            $0.categories.insert(.photo)
            $0.requiredTraits.insert(.portrait)
        }
        rule("\\bpdf\\b", "PDF") { $0.categories.insert(.pdf) }
        rule("\\b(?:word|excel|powerpoint|docx?|xlsx?|pptx?|office)\\b", "Documenti Office") {
            $0.categories.insert(.office)
        }
        rule("\\b(?:zip|rar|7z)\\b|archiv\\w*", "Archivi compressi") { $0.categories.insert(.archive) }
        rule("icloud drive", "iCloud Drive") { $0.sources.insert(.iCloudDrive) }
        rule("solo (?:su |in |nel )?(?:icloud|cloud)|non scaricat\\w*|solo online", "Solo online") {
            $0.requiredTraits.insert(.cloudOnly)
        }
        rule("download\\w*|scaricat\\w*", "Download") { $0.requiredTraits.insert(.download) }
        rule("document\\w*", "Documenti") {
            $0.categories.formUnion([.pdf, .office, .otherDocument])
        }
        rule("\\bfiles?\\b", "File") { $0.sources.formUnion([.localFiles, .iCloudDrive]) }

        // Caratteristiche
        rule("duplicat\\w*|doppion\\w*|copie identiche", "Duplicati") { $0.onlyDuplicates = true }
        rule("simil\\w*", "Simili") { $0.onlySimilar = true }
        rule("sfocat\\w*|\\bmoss[ei]\\b|blurry|blurred", "Sfocate") { $0.anyTraits.insert(.blurry) }
        rule("\\bscur[eio]\\b|\\bbui[eo]\\b|\\bdark\\b", "Scure") { $0.anyTraits.formUnion([.dark, .blank]) }
        rule("ricevut\\w*|scontrin\\w*|fattur\\w*|receipt\\w*|invoice\\w*", "Ricevute") {
            $0.anyTraits.insert(.receipt)
        }
        rule("codic\\w* qr|\\bqr\\b", "Codici QR") { $0.requiredTraits.insert(.qrCode) }
        rule("bigliett\\w*|ticket\\w*", "Biglietti") { $0.anyTraits.insert(.ticket) }
        rule("\\bchat\\b|conversazion\\w*|messagg\\w*", "Conversazioni") {
            $0.requiredTraits.insert(.conversation)
        }
        rule("(?:che contengono|che contiene|contenenti|con|with|containing|that contain) (?:del |il |un |some )?(?:testo|scritte|scritta|text)\\b|\\btesto\\b|\\btext\\b", "Con testo") {
            $0.requiredTraits.insert(.hasText)
        }
        rule("preferit\\w*|favou?rite\\w*", "Preferiti") { $0.requiredTraits.insert(.favorite) }
        rule("gia conservat\\w*|conservat\\w*", "Già conservati") { $0.reviewStatuses.insert(.kept) }
        rule("rimandat\\w*", "Rimandati") { $0.reviewStatuses.insert(.postponed) }
        rule("foto\\w*|immagin\\w*|photo\\w*|picture\\w*|scatt[oi]\\b", "Foto") { $0.categories.insert(.photo) }

        // Ordinamento
        rule("piu pesant\\w*|piu grand\\w*|piu ingombrant\\w*|ingombrant\\w*|pesant\\w*|\\bgrandi\\b|largest|biggest|heaviest", "Dal più pesante") {
            $0.sort = .sizeDescending
        }
        rule("piu vecch\\w*|meno recent\\w*|oldest", "Dal più vecchio") { $0.sort = .oldestFirst }
        rule("piu recent\\w*|\\bultim[ei]\\b|newest|latest|most recent", "Dal più recente") { $0.sort = .newestFirst }
        rule("piu lungh\\w*|longest", "Dal più lungo") { $0.sort = .durationDescending }

        // Ciò che resta diventa ricerca testuale su nomi, testo riconosciuto e trascrizioni.
        for token in text.split(separator: " ") {
            let word = String(token)
            guard word.count >= 3, !Self.stopwords.contains(word), Int(word) == nil else { continue }
            filter.textTokens.append(word)
            notes.append("Contiene «\(word)»")
        }

        return ParsedQuery(filter: filter, interpretations: notes)
    }

    // MARK: - Supporto

    /// Minuscolo, senza accenti e senza punteggiatura (tranne virgolette e separatori decimali).
    static func normalize(_ text: String) -> String {
        var result = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for quote in ["“", "”", "«", "»", "„"] {
            result = result.replacingOccurrences(of: quote, with: "\"")
        }
        result = replace("[^a-z0-9\"\\s.,-]", in: result, with: " ")
        result = replace("(?<![0-9])[.,]|[.,](?![0-9])", in: result, with: " ")
        result = replace("\\s+", in: result, with: " ")
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    /// Cerca la prima corrispondenza, la rimuove dal testo e restituisce i gruppi catturati
    /// (l'indice 0 è l'intera corrispondenza; i gruppi assenti sono stringhe vuote).
    private static func consume(_ pattern: String, in text: inout String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            if let groupRange = Range(match.range(at: index), in: text) {
                groups.append(String(text[groupRange]))
            } else {
                groups.append("")
            }
        }
        if let whole = Range(match.range, in: text) {
            text.replaceSubrange(whole, with: " ")
        }
        return groups
    }

    private static func bytes(_ value: String, unit: String) -> Int64? {
        guard let amount = Double(value.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let multiplier: Double
        switch unit {
        case "kb": multiplier = 1_000
        case "mb", "mega": multiplier = 1_000_000
        case "gb", "giga": multiplier = 1_000_000_000
        case "tb": multiplier = 1_000_000_000_000
        default: return nil
        }
        return Int64(amount * multiplier)
    }

    private static func seconds(_ value: String, unit: String) -> Double? {
        guard let amount = Double(value) else { return nil }
        if unit.hasPrefix("sec") { return amount }
        if unit.hasPrefix("min") { return amount * 60 }
        if unit.hasPrefix("or") || unit.hasPrefix("hour") { return amount * 3_600 }
        return nil
    }

    private static func amount(_ word: String) -> Int? {
        switch word {
        case "un", "uno", "una", "one": return 1
        case "due", "two": return 2
        case "tre", "three": return 3
        case "quattro": return 4
        case "cinque": return 5
        case "sei": return 6
        case "sette": return 7
        case "otto": return 8
        case "nove": return 9
        case "dieci": return 10
        default: return Int(word)
        }
    }

    private static func component(for unit: String) -> Calendar.Component? {
        if unit.hasPrefix("giorn") || unit.hasPrefix("day") { return .day }
        if unit.hasPrefix("settiman") || unit.hasPrefix("week") { return .weekOfYear }
        if unit.hasPrefix("mes") || unit.hasPrefix("month") { return .month }
        if unit.hasPrefix("ann") || unit.hasPrefix("year") { return .year }
        return nil
    }

    private func dateBySubtracting(_ word: String, unit: String) -> Date? {
        guard let amount = Self.amount(word), amount > 0, let component = Self.component(for: unit) else {
            return nil
        }
        return calendar.date(byAdding: component, value: -amount, to: now)
    }

    private static func describe(_ word: String, unit: String) -> String {
        let value = Self.amount(word) ?? 1
        guard let unitComponent = Self.component(for: unit) else { return "\(value)" }
        switch unitComponent {
        case .day: return value == 1 ? "1 giorno" : "\(value) giorni"
        case .weekOfYear: return value == 1 ? "1 settimana" : "\(value) settimane"
        case .month: return value == 1 ? "1 mese" : "\(value) mesi"
        default: return value == 1 ? "1 anno" : "\(value) anni"
        }
    }

    private struct Month {
        let name: String
        let number: Int
        let label: String
    }

    private static let months: [Month] = [
        Month(name: "gennaio", number: 1, label: "gennaio"), Month(name: "january", number: 1, label: "gennaio"),
        Month(name: "febbraio", number: 2, label: "febbraio"), Month(name: "february", number: 2, label: "febbraio"),
        Month(name: "marzo", number: 3, label: "marzo"), Month(name: "march", number: 3, label: "marzo"),
        Month(name: "aprile", number: 4, label: "aprile"), Month(name: "april", number: 4, label: "aprile"),
        Month(name: "maggio", number: 5, label: "maggio"),
        Month(name: "giugno", number: 6, label: "giugno"), Month(name: "june", number: 6, label: "giugno"),
        Month(name: "luglio", number: 7, label: "luglio"), Month(name: "july", number: 7, label: "luglio"),
        Month(name: "agosto", number: 8, label: "agosto"), Month(name: "august", number: 8, label: "agosto"),
        Month(name: "settembre", number: 9, label: "settembre"), Month(name: "september", number: 9, label: "settembre"),
        Month(name: "ottobre", number: 10, label: "ottobre"), Month(name: "october", number: 10, label: "ottobre"),
        Month(name: "novembre", number: 11, label: "novembre"), Month(name: "november", number: 11, label: "novembre"),
        Month(name: "dicembre", number: 12, label: "dicembre"), Month(name: "december", number: 12, label: "dicembre")
    ]

    private static let stopwords: Set<String> = [
        "mostrami", "mostra", "mostrare", "trova", "trovami", "cerca", "cercami", "vedere", "vedi", "elenca",
        "dammi", "voglio", "vorrei", "tutti", "tutte", "tutto", "tutta", "gli", "del", "della", "dei", "degli",
        "delle", "dello", "dell", "dal", "dalla", "dai", "nel", "nella", "nei", "nelle", "sul", "sulla", "per",
        "con", "che", "alla", "miei", "mie", "mio", "mia", "quelli", "quelle", "quello", "quella", "sono",
        "stati", "state", "stato", "piu", "meno", "molto", "contengono", "contiene", "contenenti", "girati",
        "girate", "girato", "fatti", "fatte", "fatto", "scattati", "scattate", "salvati", "salvate",
        "registrati", "registrate", "creati", "create", "ricevuti", "ricevute", "elementi", "contenuti",
        "solo", "anche", "quali", "dove", "hanno", "show", "find", "search", "all", "the", "that", "with",
        "from", "and", "are", "were", "taken", "have", "has", "una", "uno", "tra", "fra", "alle", "agli",
        "sui", "sugli", "sulle", "negli", "ogni", "quanti", "quante", "come", "quando", "ecco", "fammi",
        "lista", "elenco", "than", "older", "larger", "bigger", "anno", "anni", "mese", "mesi"
    ]
}
