import Foundation
import AVFoundation
import Photos

/// Profili di compressione proposti. La compressione è facoltativa, può ridurre la qualità
/// e non garantisce un risparmio su ogni video.
enum CompressionPreset: String, CaseIterable, Identifiable, Sendable {
    case hevc1080
    case hd720
    case medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hevc1080: return "1080p HEVC"
        case .hd720: return "720p"
        case .medium: return "Qualità media"
        }
    }

    var detail: String {
        switch self {
        case .hevc1080: return "Buona qualità, adatta ai video 4K"
        case .hd720: return "Più leggero, dettaglio ridotto"
        case .medium: return "Massimo risparmio, qualità sensibilmente inferiore"
        }
    }

    var exportPresetName: String {
        switch self {
        case .hevc1080: return AVAssetExportPresetHEVC1920x1080
        case .hd720: return AVAssetExportPreset1280x720
        case .medium: return AVAssetExportPresetMediumQuality
        }
    }
}

/// Versione compressa pronta per il confronto con l'originale. Il file è temporaneo
/// finché l'utente non decide di salvarlo.
struct CompressionResult: Identifiable, Sendable {
    let id = UUID()
    let itemID: UUID
    let outputURL: URL
    let preset: CompressionPreset
    let originalBytes: Int64
    let compressedBytes: Int64
    let duration: Double

    var savedBytes: Int64 { originalBytes - compressedBytes }

    var savedFraction: Double {
        originalBytes > 0 ? Double(savedBytes) / Double(originalBytes) : 0
    }
}

enum CompressionError: Error {
    case assetUnavailable
    case presetUnsupported
    case exportFailed(String)
    case noSavings
    case verificationFailed
    case saveFailed(String)

    var message: String {
        switch self {
        case .assetUnavailable:
            return "Il video non è disponibile sul dispositivo. Se è solo su iCloud, consenti il download dalle impostazioni."
        case .presetUnsupported:
            return "Questo profilo non è compatibile con il video."
        case .exportFailed(let reason):
            return "Compressione non riuscita: \(reason)"
        case .noSavings:
            return "La versione compressa non è più leggera dell'originale: è stata scartata."
        case .verificationFailed:
            return "La nuova copia non ha superato la verifica: l'originale resta al suo posto."
        case .saveFailed(let reason):
            return "Salvataggio non riuscito: \(reason)"
        }
    }
}

/// Compressione facoltativa dei video. L'originale non viene mai toccato da questo servizio:
/// dopo il salvataggio e la verifica della nuova copia può soltanto essere proposto per la revisione.
@MainActor
final class VideoCompressionService {

    func loadAVAsset(identifier: String, allowNetwork: Bool) async -> AVAsset? {
        guard let asset = PhotoLibraryService.asset(identifier) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<AVAsset?, Never>) in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = allowNetwork
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    /// Crea una copia compressa in una posizione temporanea e ne verifica durata e leggibilità.
    func compress(
        item: IndexedItem,
        preset: CompressionPreset,
        allowNetwork: Bool,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws -> CompressionResult {
        guard let source = await loadAVAsset(identifier: item.sourceIdentifier, allowNetwork: allowNetwork) else {
            throw CompressionError.assetUnavailable
        }
        guard AVAssetExportSession.exportPresets(compatibleWith: source).contains(preset.exportPresetName),
              let session = AVAssetExportSession(asset: source, presetName: preset.exportPresetName) else {
            throw CompressionError.presetUnsupported
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearspace-\(UUID().uuidString).mp4")
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                onProgress(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        progressTask.cancel()

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.exportFailed(session.error?.localizedDescription ?? "errore sconosciuto")
        }
        onProgress(1)

        let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let compressedBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard compressedBytes > 0, compressedBytes < item.bytes || item.bytes == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.noSavings
        }

        // Verifica: la copia deve essere riproducibile e durare quanto l'originale.
        let copy = AVURLAsset(url: outputURL)
        let isPlayable = (try? await copy.load(.isPlayable)) ?? false
        let copyDuration = (try? await copy.load(.duration).seconds) ?? 0
        let tolerance = max(1.0, item.duration * 0.02)
        guard isPlayable, abs(copyDuration - item.duration) <= tolerance else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.verificationFailed
        }

        return CompressionResult(
            itemID: item.id,
            outputURL: outputURL,
            preset: preset,
            originalBytes: item.bytes,
            compressedBytes: compressedBytes,
            duration: copyDuration
        )
    }

    /// Salva la copia compressa nella libreria, conservando data e posizione dell'originale,
    /// e verifica che il nuovo elemento esista davvero. Restituisce il suo identificativo.
    func saveToLibrary(_ result: CompressionResult, originalIdentifier: String) async throws -> String {
        let original = PhotoLibraryService.asset(originalIdentifier)
        let creationDate = original?.creationDate
        let location = original?.location
        let isFavorite = original?.isFavorite ?? false
        let outputURL = result.outputURL
        let placeholder = UncheckedBox<String?>(nil)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: outputURL, options: nil)
                request.creationDate = creationDate
                request.location = location
                request.isFavorite = isFavorite
                placeholder.value = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw CompressionError.saveFailed(error.localizedDescription)
        }

        guard let newIdentifier = placeholder.value, let created = PhotoLibraryService.asset(newIdentifier) else {
            throw CompressionError.verificationFailed
        }
        let tolerance = max(1.0, result.duration * 0.02)
        guard abs(created.duration - result.duration) <= tolerance else {
            throw CompressionError.verificationFailed
        }
        discard(result)
        return newIdentifier
    }

    /// Elimina il file temporaneo di una compressione scartata.
    func discard(_ result: CompressionResult) {
        try? FileManager.default.removeItem(at: result.outputURL)
    }
}
