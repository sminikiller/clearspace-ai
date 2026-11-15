import Foundation

struct TextClassification: Equatable, Sendable {
    var traits: ItemTraits
    var characterCount: Int
}

/// Classifica il testo riconosciuto in un'immagine (OCR) con regole locali in italiano e inglese.
/// Il risultato serve a organizzare gli screenshot e a segnalare i contenuti potenzialmente importanti:
/// è un suggerimento, mai un criterio di eliminazione.
enum TextClassifier {

    private static let receiptKeywords = [
        "totale", "subtotale", "iva", "scontrino", "ricevuta", "fattura", "importo", "pagamento", "pagato",
        "contanti", "cassa", "partita iva", "eur", "euro", "€", "total", "subtotal", "receipt", "invoice",
        "amount", "vat", "paid", "ordine n", "order #"
    ]

    private static let strongTicketKeywords = [
        "biglietto", "imbarco", "boarding", "gate", "pnr", "ticket", "carrozza", "binario", "check-in"
    ]

    private static let weakTicketKeywords = [
        "volo", "flight", "treno", "posto", "seat", "prenotazione", "booking", "partenza", "arrivo",
        "departure", "arrival", "ingresso", "fila"
    ]

    private static let chatKeywords = [
        "online", "sta scrivendo", "ultimo accesso", "scrivi un messaggio", "messaggio", "whatsapp",
        "telegram", "imessage", "consegnato", "letto", "typing", "last seen", "delivered", "message"
    ]

    private static let sensitiveKeywords = [
        "password", "codice fiscale", "iban", "carta d'identita", "carta di identita", "passaporto",
        "patente", "tessera sanitaria", "cvv", "codice di verifica", "otp", "codice di sicurezza",
        "numero carta", "passport", "social security", "verification code", "security code"
    ]

    private static let timePattern = "\\b([01]?\\d|2[0-3])[:.][0-5]\\d\\b"
    private static let pricePattern = "\\b\\d{1,5}[.,]\\d{2}\\b"
    private static let ibanPattern = "\\bit\\d{2}[a-z]\\d{10}[0-9a-z]{12}\\b"
    private static let fiscalCodePattern = "\\b[a-z]{6}\\d{2}[a-z]\\d{2}[a-z]\\d{3}[a-z]\\b"

    static func classify(lines: [String], coverage: Double, isScreenshot: Bool) -> TextClassification {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let joined = cleaned.joined(separator: "\n")
        let folded = joined
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
        let characterCount = folded.unicodeScalars.reduce(0) {
            $0 + (CharacterSet.whitespacesAndNewlines.contains($1) ? 0 : 1)
        }

        var traits: ItemTraits = []
        guard characterCount > 0 else {
            return TextClassification(traits: traits, characterCount: 0)
        }

        if characterCount >= 20 || coverage >= 0.03 {
            traits.insert(.hasText)
        }

        // Le parole singole vengono cercate come parole intere, per evitare falsi positivi
        // ("iva" dentro "arrivato"); le espressioni composte come sottostringhe.
        let words = Set(TextSimilarity.tokens(folded))

        let prices = count(pricePattern, in: folded)
        let receiptHits = hits(receiptKeywords, words: words, text: folded)
        if receiptHits >= 2 || (receiptHits >= 1 && prices >= 2) {
            traits.insert(.receipt)
        }

        let strongTicketHits = hits(strongTicketKeywords, words: words, text: folded)
        let weakTicketHits = hits(weakTicketKeywords, words: words, text: folded)
        if strongTicketHits >= 1 && strongTicketHits + weakTicketHits >= 2 {
            traits.insert(.ticket)
        }

        if isScreenshot && !cleaned.isEmpty {
            let times = count(timePattern, in: folded)
            let shortLines = cleaned.filter { $0.count <= 40 }.count
            let shortRatio = Double(shortLines) / Double(cleaned.count)
            let chatHits = hits(chatKeywords, words: words, text: folded)
            if (times >= 3 && shortRatio > 0.5 && cleaned.count >= 6) || (chatHits >= 1 && times >= 2) {
                traits.insert(.conversation)
            }
        }

        let compact = folded.replacingOccurrences(of: " ", with: "")
        if hits(sensitiveKeywords, words: words, text: folded) >= 1
            || count(ibanPattern, in: compact) > 0
            || count(fiscalCodePattern, in: folded) > 0 {
            traits.insert(.sensitiveText)
        }

        return TextClassification(traits: traits, characterCount: characterCount)
    }

    private static func hits(_ keywords: [String], words: Set<String>, text: String) -> Int {
        var total = 0
        for keyword in keywords {
            let isSingleWord = keyword.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            if isSingleWord ? words.contains(keyword) : text.contains(keyword) {
                total += 1
            }
        }
        return total
    }

    private static func count(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return regex.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }
}
