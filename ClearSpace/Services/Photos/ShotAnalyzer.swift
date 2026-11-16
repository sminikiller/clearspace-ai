import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Misure per confrontare tra loro scatti simili, calcolate sul dispositivo con Vision e Core Image.
///
/// Criteri misurati:
/// - nitidezza dell'intera immagine (varianza del laplaciano);
/// - nitidezza del soggetto: il volto più grande oppure la zona centrale;
/// - qualità dei volti (`VNDetectFaceCaptureQualityRequest`): messa a fuoco, luce, posa, espressione;
/// - occhi chiusi e sorrisi (`CIDetector`);
/// - giudizio estetico complessivo, dove iOS lo mette a disposizione.
enum ShotAnalyzer {

    /// Volto riconosciuto, in coordinate normalizzate con l'origine in basso a sinistra.
    struct DetectedFace: Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var quality: Double?

        var area: Double { width * height }
    }

    /// Analizza un'anteprima. Restituisce `nil` se è troppo piccola per un confronto affidabile:
    /// misurare la nitidezza su una miniatura darebbe valori non paragonabili a quelli delle altre foto.
    static func analyze(_ image: CGImage) -> ShotMetrics? {
        let thresholds = AppConfiguration.Thresholds.self
        guard max(image.width, image.height) >= thresholds.shotAnalysisMinimumSide,
              let gray = ImageAnalyzer.grayImage(from: image, maxSide: thresholds.shotAnalysisSide) else {
            return nil
        }

        let detail = ImageMetrics.detailSharpnessScore(variance: ImageMetrics.laplacianVariance(gray))
        var metrics = ShotMetrics(detailSharpness: detail)

        let faces = detectFaces(in: image)
        metrics.faceCount = faces.count
        // I volti grandi contano di più: sono i soggetti della foto.
        var weightedQuality = 0.0
        var totalArea = 0.0
        for face in faces {
            guard let quality = face.quality else { continue }
            weightedQuality += quality * face.area
            totalArea += face.area
        }
        if totalArea > 0 {
            metrics.faceQuality = weightedQuality / totalArea
        }

        let subjectRegion: PixelRegion
        if let mainFace = faces.max(by: { $0.area < $1.area }) {
            subjectRegion = ImageMetrics.region(
                normalizedX: mainFace.x,
                y: mainFace.y,
                width: mainFace.width,
                height: mainFace.height,
                in: gray
            )
        } else {
            subjectRegion = ImageMetrics.centralRegion(of: gray)
        }
        if subjectRegion.width >= 12 && subjectRegion.height >= 12 {
            let variance = ImageMetrics.laplacianVariance(gray, region: subjectRegion)
            metrics.subjectSharpness = ImageMetrics.detailSharpnessScore(variance: variance)
        }

        if !faces.isEmpty {
            let expressions = FaceExpressionDetector.shared.expressions(in: image)
            if expressions.faceCount > 0 {
                let count = Double(expressions.faceCount)
                metrics.openEyes = 1 - Double(expressions.closedEyes) / count
                metrics.smiles = Double(expressions.smiling) / count
            }
        }

        metrics.aesthetics = aestheticScore(of: image)
        return metrics
    }

    /// Volti con la relativa qualità di ripresa. I volti minuscoli sullo sfondo vengono ignorati:
    /// non devono decidere quale foto conservare.
    static func detectFaces(in image: CGImage) -> [DetectedFace] {
        let request = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        var faces: [DetectedFace] = []
        for observation in request.results ?? [] {
            let box = observation.boundingBox
            var quality: Double?
            if let value = observation.faceCaptureQuality {
                quality = Double(value)
            }
            faces.append(
                DetectedFace(
                    x: Double(box.origin.x),
                    y: Double(box.origin.y),
                    width: Double(box.size.width),
                    height: Double(box.size.height),
                    quality: quality
                )
            )
        }
        let relevant = faces.filter { $0.area >= AppConfiguration.Thresholds.minimumFaceArea }
        if relevant.isEmpty, let largest = faces.max(by: { $0.area < $1.area }) {
            return [largest]
        }
        return relevant
    }

    /// Giudizio estetico di Vision, da −1 a 1. Disponibile da iOS 18; altrove restituisce `nil`.
    static func aestheticScore(of image: CGImage) -> Double? {
        guard #available(iOS 18.0, *) else { return nil }
        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return Double(observation.overallScore)
    }
}

/// Riconosce occhi chiusi e sorrisi con Core Image. Il rilevatore è costoso da creare e non è
/// pensato per l'uso contemporaneo da più thread: viene creato una volta e protetto da un lucchetto.
final class FaceExpressionDetector: @unchecked Sendable {

    static let shared = FaceExpressionDetector()

    struct Expressions: Sendable {
        var faceCount = 0
        /// Volti con entrambi gli occhi chiusi.
        var closedEyes = 0
        var smiling = 0
    }

    private let lock = NSLock()
    private let detector: CIDetector?

    private init() {
        detector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    }

    func expressions(in image: CGImage) -> Expressions {
        guard let detector else { return Expressions() }
        lock.lock()
        defer { lock.unlock() }
        let options: [String: Any] = [CIDetectorEyeBlink: true, CIDetectorSmile: true]
        let features = detector.features(in: CIImage(cgImage: image), options: options)
        var result = Expressions()
        for feature in features {
            guard let face = feature as? CIFaceFeature else { continue }
            result.faceCount += 1
            if face.leftEyeClosed && face.rightEyeClosed {
                result.closedEyes += 1
            }
            if face.hasSmile {
                result.smiling += 1
            }
        }
        return result
    }
}
