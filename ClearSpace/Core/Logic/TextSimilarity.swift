import Foundation

/// Confronto testuale tra documenti: normalizzazione, shingle, Jaccard e MinHash.
/// Serve a riconoscere versioni dello stesso documento anche se rinominate o scansionate diversamente.
enum TextSimilarity {

    /// Parole in minuscolo, senza accenti né punteggiatura: le differenze di impaginazione spariscono.
    static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var result: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Hash FNV-1a a 64 bit: deterministico tra un avvio e l'altro, a differenza di `Hasher`.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Sequenze sovrapposte di `size` parole, rappresentate dal loro hash.
    static func shingles(_ tokens: [String], size: Int = 3) -> Set<UInt64> {
        guard !tokens.isEmpty, size > 0 else { return [] }
        guard tokens.count >= size else {
            return [fnv1a(tokens.joined(separator: " "))]
        }
        var result = Set<UInt64>()
        for index in 0...(tokens.count - size) {
            result.insert(fnv1a(tokens[index..<(index + size)].joined(separator: " ")))
        }
        return result
    }

    static func jaccard(_ first: Set<UInt64>, _ second: Set<UInt64>) -> Double {
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        let intersection = first.intersection(second).count
        let union = first.count + second.count - intersection
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    /// Somiglianza testuale tra 0 e 1.
    static func similarity(_ first: String, _ second: String) -> Double {
        jaccard(shingles(tokens(first)), shingles(tokens(second)))
    }

    // MARK: - MinHash

    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9e37_79b9_7f4a_7c15
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    private static let signatureSeeds: [UInt64] = (0..<64).map { mix(UInt64($0) &* 0x2545_f491_4f6c_dd1d) }

    /// Firma compatta di un insieme di shingle: permette di confrontare molti documenti velocemente.
    static func minHashSignature(_ shingles: Set<UInt64>) -> [UInt64] {
        var signature = [UInt64](repeating: UInt64.max, count: signatureSeeds.count)
        for shingle in shingles {
            for (index, seed) in signatureSeeds.enumerated() {
                let value = mix(shingle ^ seed)
                if value < signature[index] { signature[index] = value }
            }
        }
        return signature
    }

    /// Stima della somiglianza di Jaccard a partire da due firme.
    static func estimatedSimilarity(_ first: [UInt64], _ second: [UInt64]) -> Double {
        guard first.count == second.count, !first.isEmpty else { return 0 }
        var matches = 0
        for index in first.indices where first[index] == second[index] && first[index] != UInt64.max {
            matches += 1
        }
        return Double(matches) / Double(first.count)
    }

    // MARK: - Nomi dei file

    /// Nome senza estensione e senza suffissi di versione: "Contratto (1).pdf" e "contratto_v2.pdf" → "contratto".
    static func normalizedBaseName(_ filename: String) -> String {
        var name = (filename as NSString).deletingPathExtension
        name = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let patterns = [
            "\\s*\\(\\d+\\)$",
            "[\\s_-]*(copia|copy|kopie)(\\s*\\d+)?$",
            "[\\s_-]+(v|ver|versione|version|rev)[\\s._-]*\\d+$",
            "[\\s_-]+(final|finale|definitivo|definitiva|def|bozza|draft|nuovo|nuova|new|ok)$",
            "[\\s_-]+\\d{1,2}$"
        ]
        for _ in 0..<3 {
            let before = name
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(name.startIndex..., in: name)
                name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
            }
            if name == before { break }
        }
        let parts = tokens(name)
        return parts.joined(separator: " ")
    }

    // MARK: - Differenze tra documenti

    /// Pagine (numerate da 1) il cui testo differisce tra due documenti, limitatamente alle pagine comuni.
    static func differingPages(_ first: [String], _ second: [String], threshold: Double = 0.85) -> [Int] {
        var result: [Int] = []
        for index in 0..<min(first.count, second.count) {
            let left = tokens(first[index])
            let right = tokens(second[index])
            if left.isEmpty && right.isEmpty { continue }
            if left == right { continue }
            if jaccard(shingles(left), shingles(right)) < threshold {
                result.append(index + 1)
            }
        }
        return result
    }

    /// Descrive in italiano la differenza tra due versioni, es. "Uno dei due ha 1 pagina in più."
    static func describeDifference(
        pagesOfFirst first: [String],
        pagesOfSecond second: [String],
        firstPageCount: Int? = nil,
        secondPageCount: Int? = nil
    ) -> String {
        var parts: [String] = []
        // Il testo può essere stato letto solo per le prime pagine: il numero reale, se noto, ha la precedenza.
        let delta = abs((firstPageCount ?? first.count) - (secondPageCount ?? second.count))
        if delta == 1 {
            parts.append("Uno dei due ha 1 pagina in più.")
        } else if delta > 1 {
            parts.append("Uno dei due ha \(delta) pagine in più.")
        }
        let different = differingPages(first, second)
        if different.count == 1 {
            parts.append("La pagina \(different[0]) è diversa.")
        } else if different.count > 1 {
            let listed = different.prefix(6).map { String($0) }.joined(separator: ", ")
            let suffix = different.count > 6 ? " e altre" : ""
            parts.append("Le pagine \(listed)\(suffix) sono diverse.")
        }
        if parts.isEmpty {
            return "Il testo delle pagine coincide."
        }
        return parts.joined(separator: " ")
    }
}
