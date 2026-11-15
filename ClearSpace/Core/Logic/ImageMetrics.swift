import Foundation

/// Immagine in scala di grigi a 8 bit, usata per le misure di qualità.
struct GrayImage: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// Misure tecniche calcolate sulle anteprime: nitidezza, luminosità, hash percettivo.
/// Sono funzioni pure, indipendenti dai framework grafici.
enum ImageMetrics {

    /// Varianza del laplaciano: valori bassi indicano un'immagine probabilmente sfocata.
    static func laplacianVariance(_ image: GrayImage) -> Double {
        let width = image.width
        let height = image.height
        guard width >= 3, height >= 3 else { return 0 }

        var sum = 0.0
        var sumOfSquares = 0.0
        image.pixels.withUnsafeBufferPointer { pixels in
            for y in 1..<(height - 1) {
                let row = y * width
                for x in 1..<(width - 1) {
                    let index = row + x
                    let neighbours = Int(pixels[index - width]) + Int(pixels[index + width])
                        + Int(pixels[index - 1]) + Int(pixels[index + 1])
                    let value = Double(neighbours - 4 * Int(pixels[index]))
                    sum += value
                    sumOfSquares += value * value
                }
            }
        }
        let count = Double((width - 2) * (height - 2))
        let mean = sum / count
        return max(0, sumOfSquares / count - mean * mean)
    }

    /// Luminosità media e contrasto (deviazione standard), entrambi tra 0 e 1.
    static func luminance(_ image: GrayImage) -> (mean: Double, deviation: Double) {
        guard !image.pixels.isEmpty else { return (0, 0) }
        var sum = 0.0
        var sumOfSquares = 0.0
        for pixel in image.pixels {
            let value = Double(pixel) / 255
            sum += value
            sumOfSquares += value * value
        }
        let count = Double(image.pixels.count)
        let mean = sum / count
        let variance = max(0, sumOfSquares / count - mean * mean)
        return (mean, variance.squareRoot())
    }

    /// Nitidezza normalizzata tra 0 e 1.
    static func sharpnessScore(variance: Double) -> Double {
        let ratio = max(0, variance) / AppConfiguration.Thresholds.sharpVariance
        return min(1, ratio.squareRoot())
    }

    /// Hash percettivo "difference hash" a 64 bit. Richiede un'immagine 9×8.
    static func differenceHash(_ image: GrayImage) -> UInt64? {
        guard image.width == 9, image.height == 8 else { return nil }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                let left = image.pixels[y * 9 + x]
                let right = image.pixels[y * 9 + x + 1]
                if left > right {
                    hash |= (UInt64(1) << bit)
                }
                bit += 1
            }
        }
        return hash
    }

    static func hammingDistance(_ first: UInt64, _ second: UInt64) -> Int {
        (first ^ second).nonzeroBitCount
    }

    /// Gli hash con pochissimi o moltissimi bit attivi provengono da immagini uniformi
    /// e produrrebbero falsi duplicati.
    static func isInformative(hash: UInt64) -> Bool {
        let bits = hash.nonzeroBitCount
        return bits >= 8 && bits <= 56
    }

    /// Coppie di indici i cui hash differiscono al più di `maxDistance` bit (fino a 3).
    /// Usa quattro bande da 16 bit: due hash così vicini ne condividono per forza almeno una,
    /// quindi non serve confrontare ogni elemento con tutti gli altri.
    static func nearPairs(_ hashes: [UInt64], maxDistance: Int = 3) -> [(Int, Int)] {
        let distance = min(max(maxDistance, 0), 3)
        var buckets: [UInt32: [Int]] = [:]
        for (index, hash) in hashes.enumerated() {
            for band in 0..<4 {
                let value = UInt32((hash >> UInt64(band * 16)) & 0xFFFF)
                let key = (UInt32(band) << 16) | value
                buckets[key, default: []].append(index)
            }
        }

        var seen = Set<UInt64>()
        var pairs: [(Int, Int)] = []
        // I gruppi enormi nascono da bande poco significative (zone uniformi): vengono saltati,
        // le coppie reali emergono comunque dalle altre bande.
        for members in buckets.values where members.count >= 2 && members.count <= 400 {
            for first in 0..<(members.count - 1) {
                for second in (first + 1)..<members.count {
                    let low = min(members[first], members[second])
                    let high = max(members[first], members[second])
                    guard hammingDistance(hashes[low], hashes[high]) <= distance else { continue }
                    let key = (UInt64(low) << 32) | UInt64(high)
                    if seen.insert(key).inserted {
                        pairs.append((low, high))
                    }
                }
            }
        }
        return pairs
    }

    /// Qualità dell'esposizione: massima a metà scala, nulla agli estremi.
    static func exposureQuality(brightness: Double) -> Double {
        max(0, 1 - abs(brightness - 0.45) / 0.45)
    }
}
