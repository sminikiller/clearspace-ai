import Foundation

/// Sceglie, in un gruppo di elementi simili, quale conviene conservare e spiega perché.
/// È una proposta: l'utente può sempre conservare tutto o scegliere diversamente.
///
/// Il giudizio combina più criteri, ciascuno tra 0 e 1:
/// nitidezza dell'immagine, nitidezza del soggetto, qualità dei volti, occhi aperti,
/// esposizione, giudizio estetico e risoluzione. Preferiti e foto modificate hanno un peso a parte,
/// perché sono scelte già espresse dall'utente.
enum QualityRanker {

    struct Suggestion: Equatable, Sendable {
        let keepID: UUID
        /// Motivo in forma di frase, es. "è più nitida e ha una risoluzione superiore".
        let reason: String
    }

    /// Criteri utilizzabili per un gruppo. Due scatti si possono confrontare solo sugli stessi criteri:
    /// se a un membro manca una misura, quel criterio viene ignorato per tutti.
    struct Criteria: Equatable, Sendable {
        /// Tutti i membri hanno le misure del confronto approfondito.
        var usesShotMetrics: Bool
        /// La maggior parte dei membri ritrae dei volti.
        var usesFaces: Bool
        var usesAesthetics: Bool

        init(usesShotMetrics: Bool, usesFaces: Bool, usesAesthetics: Bool) {
            self.usesShotMetrics = usesShotMetrics
            self.usesFaces = usesFaces
            self.usesAesthetics = usesAesthetics
        }

        init(members: [IndexedItem]) {
            let shots = members.compactMap { $0.shot }
            let complete = !members.isEmpty && shots.count == members.count
            let withFaces = shots.filter { $0.hasFaces }.count
            usesShotMetrics = complete
            usesFaces = complete && withFaces * 2 > members.count
            usesAesthetics = complete && shots.allSatisfy { $0.aesthetics != nil }
        }
    }

    /// Valutazione di uno scatto, criterio per criterio. I criteri non applicabili sono `nil`.
    struct Breakdown: Equatable, Sendable {
        var sharpness: Double
        var subject: Double?
        var faces: Double?
        var openEyes: Double?
        var exposure: Double
        var aesthetics: Double?
        var resolution: Double
        /// Media pesata dei criteri (0…1).
        var quality: Double
        /// Scelte già espresse dall'utente (preferito, modificata) e difetti evidenti.
        var adjustment: Double

        var score: Double { quality + adjustment }

        /// Voto da 0 a 100 mostrato nell'interfaccia.
        var grade: Int {
            Int((min(1, max(0, quality)) * 100).rounded())
        }
    }

    // MARK: - Valutazione

    static func breakdown(_ item: IndexedItem, criteria: Criteria) -> Breakdown {
        let megapixels = Double(item.pixelCount) / 1_000_000
        let resolution = min(1, megapixels / 12)
        let exposure = item.brightness.map { ImageMetrics.exposureQuality(brightness: $0) } ?? 0.5

        var sharpness = item.sharpness ?? 0.5
        var subject: Double?
        var faces: Double?
        var openEyes: Double?
        var aesthetics: Double?
        var weighted: [(value: Double, weight: Double)]

        if criteria.usesShotMetrics, let shot = item.shot {
            sharpness = shot.detailSharpness
            let subjectValue = shot.subjectSharpness ?? shot.detailSharpness
            subject = subjectValue
            if criteria.usesAesthetics, let value = shot.aesthetics {
                aesthetics = min(1, max(0, (value + 1) / 2))
            }
            if criteria.usesFaces {
                // Un volto non riconosciuto, in un gruppo di ritratti, è quasi sempre un volto venuto male.
                let facesValue = shot.hasFaces ? (shot.faceQuality ?? 0.25) : 0.25
                let eyesValue = shot.openEyes ?? 0.6
                faces = facesValue
                openEyes = eyesValue
                weighted = [
                    (facesValue, 0.26), (eyesValue, 0.14), (subjectValue, 0.20),
                    (sharpness, 0.14), (exposure, 0.08), (resolution, 0.08)
                ]
            } else {
                weighted = [
                    (sharpness, 0.34), (subjectValue, 0.20), (exposure, 0.16), (resolution, 0.18)
                ]
            }
            if let aesthetics {
                weighted.append((aesthetics, criteria.usesFaces ? 0.10 : 0.20))
            }
        } else {
            weighted = [(sharpness, 0.45), (resolution, 0.30), (exposure, 0.15)]
        }

        var totalWeight = 0.0
        var weightedSum = 0.0
        for entry in weighted {
            totalWeight += entry.weight
            weightedSum += entry.value * entry.weight
        }
        let quality = totalWeight > 0 ? weightedSum / totalWeight : 0

        var adjustment = 0.0
        if item.traits.contains(.favorite) { adjustment += 0.30 }
        if item.traits.contains(.edited) { adjustment += 0.10 }
        if item.isLowQuality { adjustment -= 0.20 }

        return Breakdown(
            sharpness: sharpness,
            subject: subject,
            faces: faces,
            openEyes: openEyes,
            exposure: exposure,
            aesthetics: aesthetics,
            resolution: resolution,
            quality: quality,
            adjustment: adjustment
        )
    }

    /// Valutazione di un elemento considerato da solo.
    static func breakdown(_ item: IndexedItem) -> Breakdown {
        breakdown(item, criteria: Criteria(members: [item]))
    }

    static func score(_ item: IndexedItem) -> Double {
        breakdown(item).score
    }

    /// Valutazioni dei membri di un gruppo, confrontabili tra loro.
    static func breakdowns(among members: [IndexedItem]) -> [UUID: Breakdown] {
        let criteria = Criteria(members: members)
        var result: [UUID: Breakdown] = [:]
        for member in members {
            result[member.id] = breakdown(member, criteria: criteria)
        }
        return result
    }

    // MARK: - Suggerimento

    /// Suggerimento per gruppi di contenuti simili (non identici).
    static func suggestion(among members: [IndexedItem]) -> Suggestion? {
        guard members.count >= 2 else { return nil }
        let criteria = Criteria(members: members)
        let rated = members.map { (item: $0, rating: breakdown($0, criteria: criteria)) }
        let ranked = rated.sorted { first, second in
            if first.rating.score != second.rating.score { return first.rating.score > second.rating.score }
            if first.item.bytes != second.item.bytes { return first.item.bytes > second.item.bytes }
            return (first.item.createdAt ?? Date.distantFuture) < (second.item.createdAt ?? Date.distantFuture)
        }
        guard let best = ranked.first else { return nil }
        let others = Array(ranked.dropFirst())

        var reasons: [String] = []
        if best.item.traits.contains(.favorite) && !others.contains(where: { $0.item.traits.contains(.favorite) }) {
            reasons.append("è tra i preferiti")
        }
        if let eyes = best.rating.openEyes, eyes >= 0.99,
           others.contains(where: { ($0.rating.openEyes ?? 1) < 0.99 }) {
            reasons.append("ha gli occhi aperti")
        }
        if let faces = best.rating.faces {
            let otherBest = others.compactMap { $0.rating.faces }.max() ?? 0
            if faces > otherBest + 0.06 {
                reasons.append("i volti sono venuti meglio")
            }
        }
        if let subject = best.rating.subject {
            let otherBest = others.compactMap { $0.rating.subject }.max() ?? 0
            if subject > otherBest * 1.10 + 0.01 {
                reasons.append("ha il soggetto più a fuoco")
            }
        }
        let otherSharpness = others.map { $0.rating.sharpness }.max() ?? 0
        let sharpnessIsKnown = criteria.usesShotMetrics || best.item.sharpness != nil
        if sharpnessIsKnown && best.rating.sharpness > otherSharpness * 1.10 + 0.01 {
            reasons.append("è più nitida")
        }
        let otherPixels = others.map { $0.item.pixelCount }.max() ?? 0
        if best.item.pixelCount > 0 && Double(best.item.pixelCount) > Double(otherPixels) * 1.05 {
            reasons.append("ha una risoluzione superiore")
        }
        if best.item.brightness != nil {
            let otherExposure = others
                .filter { $0.item.brightness != nil }
                .map { $0.rating.exposure }
                .max() ?? 0
            if best.rating.exposure > otherExposure + 0.15 {
                reasons.append("ha un'esposizione migliore")
            }
        }
        if let aesthetics = best.rating.aesthetics {
            let otherBest = others.compactMap { $0.rating.aesthetics }.max() ?? 0
            if aesthetics > otherBest + 0.08 {
                reasons.append("è più riuscita nel complesso")
            }
        }
        if best.item.traits.contains(.edited) && !others.contains(where: { $0.item.traits.contains(.edited) }) {
            reasons.append("è stata modificata da te")
        }
        if best.item.isVideo {
            let otherDuration = others.map { $0.item.duration }.max() ?? 0
            if best.item.duration > otherDuration + 1 {
                reasons.append("dura di più")
            }
        }

        // Tre motivi bastano: una frase più lunga non aiuta a decidere.
        let reason = reasons.isEmpty
            ? "le versioni sono equivalenti per qualità"
            : join(Array(reasons.prefix(3)))
        return Suggestion(keepID: best.item.id, reason: reason)
    }

    /// Suggerimento per copie identiche: si conserva il preferito oppure la copia meno recente.
    static func originalSuggestion(among members: [IndexedItem]) -> Suggestion? {
        guard members.count >= 2 else { return nil }
        if let favorite = members.first(where: { $0.traits.contains(.favorite) }) {
            return Suggestion(keepID: favorite.id, reason: "è tra i preferiti")
        }
        let oldest = members.min {
            ($0.createdAt ?? Date.distantFuture) < ($1.createdAt ?? Date.distantFuture)
        }
        guard let oldest else { return nil }
        return Suggestion(keepID: oldest.id, reason: "è la copia meno recente, probabilmente l'originale")
    }

    // MARK: - Testi

    /// "a", "a e b", "a, b e c".
    static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) e \(parts[1])"
        default:
            let head = parts.dropLast().joined(separator: ", ")
            return "\(head) e \(parts[parts.count - 1])"
        }
    }

    /// Frase completa mostrata nel confronto, es. "Conserva la foto 3: è più nitida…".
    static func sentence(position: Int, noun: String, reason: String) -> String {
        "Conserva \(noun) \(position): \(reason)."
    }

    /// Punti di forza e difetti di uno scatto, in poche parole, da mostrare accanto all'anteprima.
    static func highlights(for item: IndexedItem, rating: Breakdown) -> [Highlight] {
        var result: [Highlight] = []
        if item.traits.contains(.favorite) {
            result.append(Highlight(text: "Preferita", kind: .good))
        }
        if let shot = item.shot {
            if shot.hasClosedEyes {
                result.append(Highlight(text: "Occhi chiusi", kind: .warning))
            } else if shot.hasFaces, shot.openEyes != nil {
                result.append(Highlight(text: "Occhi aperti", kind: .good))
            }
            if let faces = rating.faces, shot.hasFaces {
                result.append(Highlight(text: "Volti \(percent(faces))", kind: faces < 0.35 ? .warning : .neutral))
            }
            if let smiles = shot.smiles, smiles >= 0.5 {
                result.append(Highlight(text: "Sorriso", kind: .good))
            }
        }
        if item.traits.contains(.blurry) {
            result.append(Highlight(text: "Forse sfocata", kind: .warning))
        } else if item.shot != nil || item.sharpness != nil {
            result.append(Highlight(text: "Nitidezza \(percent(rating.sharpness))", kind: .neutral))
        }
        if item.traits.contains(.dark) {
            result.append(Highlight(text: "Molto scura", kind: .warning))
        }
        if item.traits.contains(.edited) {
            result.append(Highlight(text: "Modificata", kind: .neutral))
        }
        return result
    }

    /// Il difetto più evidente, da mostrare sull'anteprima di una foto: occhi chiusi, forse sfocata,
    /// molto scura. Dice a colpo d'occhio perché una foto è peggiore delle altre. La quota di volti
    /// riconosciuti non conta: da sola non è un difetto che si vede.
    static func mainWarning(for item: IndexedItem, rating: Breakdown) -> String? {
        highlights(for: item, rating: rating)
            .first { $0.kind == .warning && !$0.text.hasPrefix("Volti") }?
            .text
    }

    struct Highlight: Equatable, Sendable {
        enum Kind: Sendable {
            case good
            case neutral
            case warning
        }

        let text: String
        let kind: Kind
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))"
    }
}
