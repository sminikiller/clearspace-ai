import Foundation

/// Sceglie, in un gruppo di elementi simili, quale conviene conservare e spiega perché.
/// È una proposta: l'utente può sempre conservare tutto o scegliere diversamente.
enum QualityRanker {

    struct Suggestion: Equatable, Sendable {
        let keepID: UUID
        /// Motivo in forma di frase, es. "è più nitida e ha una risoluzione superiore".
        let reason: String
    }

    static func score(_ item: IndexedItem) -> Double {
        var score = 0.45 * (item.sharpness ?? 0.5)
        let megapixels = Double(item.pixelCount) / 1_000_000
        score += 0.30 * min(1, megapixels / 12)
        if let brightness = item.brightness {
            score += 0.15 * ImageMetrics.exposureQuality(brightness: brightness)
        } else {
            score += 0.075
        }
        if item.traits.contains(.favorite) { score += 0.30 }
        if item.traits.contains(.edited) { score += 0.10 }
        if item.isLowQuality { score -= 0.20 }
        return score
    }

    /// Suggerimento per gruppi di contenuti simili (non identici).
    static func suggestion(among members: [IndexedItem]) -> Suggestion? {
        guard members.count >= 2 else { return nil }
        let ranked = members.sorted { first, second in
            let firstScore = score(first)
            let secondScore = score(second)
            if firstScore != secondScore { return firstScore > secondScore }
            if first.bytes != second.bytes { return first.bytes > second.bytes }
            return (first.createdAt ?? Date.distantFuture) < (second.createdAt ?? Date.distantFuture)
        }
        guard let best = ranked.first else { return nil }
        let others = Array(ranked.dropFirst())

        var reasons: [String] = []
        if best.traits.contains(.favorite) && !others.contains(where: { $0.traits.contains(.favorite) }) {
            reasons.append("è tra i preferiti")
        }
        if let sharpness = best.sharpness {
            let otherBest = others.compactMap { $0.sharpness }.max() ?? 0
            if sharpness > otherBest * 1.10 + 0.01 {
                reasons.append("è più nitida")
            }
        }
        let otherPixels = others.map { $0.pixelCount }.max() ?? 0
        if best.pixelCount > 0 && Double(best.pixelCount) > Double(otherPixels) * 1.05 {
            reasons.append("ha una risoluzione superiore")
        }
        if let brightness = best.brightness {
            let quality = ImageMetrics.exposureQuality(brightness: brightness)
            let otherQuality = others
                .compactMap { $0.brightness }
                .map { ImageMetrics.exposureQuality(brightness: $0) }
                .max() ?? 0
            if quality > otherQuality + 0.15 {
                reasons.append("ha un'esposizione migliore")
            }
        }
        if best.traits.contains(.edited) && !others.contains(where: { $0.traits.contains(.edited) }) {
            reasons.append("è stata modificata da te")
        }
        if best.isVideo {
            let otherDuration = others.map { $0.duration }.max() ?? 0
            if best.duration > otherDuration + 1 {
                reasons.append("dura di più")
            }
        }

        let reason = reasons.isEmpty ? "le versioni sono equivalenti per qualità" : join(reasons)
        return Suggestion(keepID: best.id, reason: reason)
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
}
