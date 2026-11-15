import Foundation
import CoreGraphics
import ImageIO
import Photos
import UIKit
import Vision

struct TextRecognitionResult: Sendable {
    var lines: [String]
    /// Quota dell'immagine coperta dal testo riconosciuto (0…1).
    var coverage: Double

    var text: String { lines.joined(separator: "\n") }
}

/// Analisi delle immagini eseguite interamente sul dispositivo con Vision e Core Graphics.
enum ImageAnalyzer {

    // MARK: - Scala di grigi

    static func grayImage(from image: CGImage, width: Int, height: Int) -> GrayImage? {
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// Versione in scala di grigi con il lato lungo limitato a `maxSide`, mantenendo le proporzioni.
    static func grayImage(from image: CGImage, maxSide: Int) -> GrayImage? {
        let longSide = max(image.width, image.height)
        guard longSide > 0 else { return nil }
        let scale = min(1, Double(maxSide) / Double(longSide))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        return grayImage(from: image, width: width, height: height)
    }

    static func perceptualHash(of image: CGImage) -> UInt64? {
        guard let tiny = grayImage(from: image, width: 9, height: 8) else { return nil }
        return ImageMetrics.differenceHash(tiny)
    }

    // MARK: - Somiglianza visiva

    /// Rappresentazione numerica dell'immagine (feature print) confrontabile con altre.
    static func featurePrint(for image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    /// Distanza tra due feature print: 0 = identiche, valori maggiori = più diverse.
    static func distance(_ first: VNFeaturePrintObservation, _ second: VNFeaturePrintObservation) -> Float? {
        var distance = Float(0)
        do {
            try first.computeDistance(&distance, to: second)
            return distance
        } catch {
            return nil
        }
    }

    // MARK: - Testo, codici e documenti

    static func recognizeText(in image: CGImage, accurate: Bool = false) -> TextRecognitionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.recognitionLanguages = ["it-IT", "en-US"]
        request.usesLanguageCorrection = accurate
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return TextRecognitionResult(lines: [], coverage: 0)
        }
        var lines: [String] = []
        var coverage = 0.0
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            lines.append(candidate.string)
            coverage += Double(observation.boundingBox.width * observation.boundingBox.height)
        }
        return TextRecognitionResult(lines: lines, coverage: min(1, coverage))
    }

    static func containsQRCode(_ image: CGImage) -> Bool {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return !(request.results ?? []).isEmpty
        } catch {
            return false
        }
    }

    /// Confidenza (0…1) che l'immagine ritragga un documento, ad esempio un foglio fotografato.
    static func documentConfidence(_ image: CGImage) -> Float {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return 0 }
            // Un documento deve occupare una parte consistente dell'inquadratura.
            let box = observation.boundingBox
            guard box.width * box.height > 0.25 else { return 0 }
            return observation.confidence
        } catch {
            return 0
        }
    }

    // MARK: - File immagine

    /// Miniatura di un file immagine letta con Image I/O, senza caricare l'intero file in memoria.
    static func thumbnail(ofImageAt url: URL, maxSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Caricamento sincrono delle anteprime per le analisi in background.
enum AnalysisImageLoader {

    /// Restituisce un'anteprima dell'asset senza usare la rete, salvo richiesta esplicita.
    /// Va chiamato fuori dal thread principale.
    static func thumbnail(for asset: PHAsset, maxSide: CGFloat, allowNetwork: Bool = false) -> CGImage? {
        if let image = request(asset, maxSide: maxSide, delivery: .highQualityFormat, allowNetwork: allowNetwork) {
            return image
        }
        // Se l'anteprima di qualità non è disponibile in locale si ripiega su quella rapida.
        return request(asset, maxSide: maxSide, delivery: .fastFormat, allowNetwork: false)
    }

    private static func request(
        _ asset: PHAsset,
        maxSide: CGFloat,
        delivery: PHImageRequestOptionsDeliveryMode,
        allowNetwork: Bool
    ) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = delivery
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        let box = UncheckedBox<CGImage?>(nil)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: maxSide, height: maxSide),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            box.value = image?.cgImage
        }
        return box.value
    }
}
