import Foundation
import AVFoundation
import Photos
import QuickLookThumbnailing
import UIKit

/// Stato del caricamento di un'immagine mostrata in grande.
enum ImageLoadEvent {
    /// Immagine disponibile. `isFinal` è `false` per la versione provvisoria a bassa qualità,
    /// quella che iOS tiene sul dispositivo quando l'originale è su iCloud.
    case image(UIImage, isFinal: Bool)
    /// Avanzamento del download da iCloud (0…1).
    case downloading(Double)
    /// La versione nitida è solo su iCloud e la rete non è consentita.
    case needsNetwork
    case failed
}

/// Fornisce le immagini mostrate nell'interfaccia: anteprime della libreria Foto tramite PhotoKit
/// e anteprime dei file tramite Quick Look. Non conserva copie su disco.
@MainActor
final class ThumbnailProvider {

    private let imageManager = PHCachingImageManager()
    private let assetCache = NSCache<NSString, PHAsset>()
    private let fileCache = NSCache<NSString, UIImage>()
    private let folders: FolderAccessService

    init(folders: FolderAccessService) {
        self.folders = folders
        assetCache.countLimit = 3_000
        fileCache.countLimit = 400
    }

    func asset(for identifier: String) -> PHAsset? {
        let key = identifier as NSString
        if let cached = assetCache.object(forKey: key) {
            return cached
        }
        guard let asset = PhotoLibraryService.asset(identifier) else { return nil }
        assetCache.setObject(asset, forKey: key)
        return asset
    }

    /// Dimentica gli asset eliminati, così non vengono più proposti dalla cache.
    func forget(identifiers: [String]) {
        for identifier in identifiers {
            assetCache.removeObject(forKey: identifier as NSString)
        }
    }

    /// Flusso di immagini per un elemento: prima una versione rapida, poi quella definitiva.
    /// `allowNetwork` va attivato solo quando è consentito scaricare l'originale da iCloud.
    func images(for item: IndexedItem, pixelSide: CGFloat, fill: Bool, allowNetwork: Bool) -> AsyncStream<UIImage> {
        switch item.source {
        case .photoLibrary:
            guard let libraryAsset = self.asset(for: item.sourceIdentifier) else {
                return AsyncStream { $0.finish() }
            }
            return libraryImages(asset: libraryAsset, pixelSide: pixelSide, fill: fill, allowNetwork: allowNetwork)
        case .localFiles, .iCloudDrive, .appImports:
            guard let url = folders.url(for: item) else {
                return AsyncStream { $0.finish() }
            }
            return fileImages(url: url, key: item.id.uuidString, pixelSide: pixelSide)
        }
    }

    private func libraryImages(
        asset: PHAsset,
        pixelSide: CGFloat,
        fill: Bool,
        allowNetwork: Bool
    ) -> AsyncStream<UIImage> {
        let manager = imageManager
        return AsyncStream { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetwork
            let requestID = manager.requestImage(
                for: asset,
                targetSize: CGSize(width: pixelSide, height: pixelSide),
                contentMode: fill ? .aspectFill : .aspectFit,
                options: options
            ) { image, info in
                if let image {
                    continuation.yield(image)
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil
                if !isDegraded || isCancelled || hasError {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                manager.cancelImageRequest(requestID)
            }
        }
    }

    // MARK: - Immagini mostrate in grande

    /// Flusso per le immagini mostrate in grande (carta dello swipe, confronto): oltre alle immagini
    /// segnala l'avanzamento del download e quando, per la versione nitida, servirebbe la rete.
    /// Così l'interfaccia non resta con un'anteprima sfocata senza spiegare perché.
    func displayEvents(for item: IndexedItem, pixelSide: CGFloat, allowNetwork: Bool) -> AsyncStream<ImageLoadEvent> {
        if item.source == .photoLibrary {
            guard let libraryAsset = self.asset(for: item.sourceIdentifier) else {
                return AsyncStream { continuation in
                    continuation.yield(.failed)
                    continuation.finish()
                }
            }
            return libraryDisplayEvents(asset: libraryAsset, pixelSide: pixelSide, allowNetwork: allowNetwork)
        }
        // File: l'anteprima di Quick Look è già quella definitiva.
        let source = images(for: item, pixelSide: pixelSide, fill: false, allowNetwork: allowNetwork)
        return AsyncStream { continuation in
            let task = Task {
                var delivered = false
                for await image in source {
                    delivered = true
                    continuation.yield(.image(image, isFinal: true))
                }
                if !delivered {
                    continuation.yield(.failed)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func displayOptions(allowNetwork: Bool) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        return options
    }

    private func libraryDisplayEvents(
        asset: PHAsset,
        pixelSide: CGFloat,
        allowNetwork: Bool
    ) -> AsyncStream<ImageLoadEvent> {
        let manager = imageManager
        let options = Self.displayOptions(allowNetwork: allowNetwork)
        return AsyncStream { continuation in
            options.progressHandler = { progress, _, _, _ in
                continuation.yield(.downloading(progress))
            }
            let requestID = manager.requestImage(
                for: asset,
                targetSize: CGSize(width: pixelSide, height: pixelSide),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil
                if let image {
                    continuation.yield(.image(image, isFinal: !isDegraded))
                }
                if isCancelled {
                    continuation.finish()
                } else if !isDegraded {
                    // Ultima risposta: senza immagine significa che la versione nitida non è arrivata.
                    if image == nil {
                        continuation.yield(isInCloud && !allowNetwork ? .needsNetwork : .failed)
                    }
                    continuation.finish()
                } else if hasError {
                    continuation.yield(.failed)
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                manager.cancelImageRequest(requestID)
            }
        }
    }

    /// Prepara in anticipo le immagini dei prossimi elementi, così compaiono subito al cambio di carta.
    func preheat(_ items: [IndexedItem], pixelSide: CGFloat, allowNetwork: Bool) {
        var assets: [PHAsset] = []
        for item in items where item.source == .photoLibrary {
            if let libraryAsset = asset(for: item.sourceIdentifier) {
                assets.append(libraryAsset)
            }
        }
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: CGSize(width: pixelSide, height: pixelSide),
            contentMode: .aspectFit,
            options: Self.displayOptions(allowNetwork: allowNetwork)
        )
    }

    func stopPreheating() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - File

    private func fileImages(url: URL, key: String, pixelSide: CGFloat) -> AsyncStream<UIImage> {
        let cacheKey = "\(key)-\(Int(pixelSide))" as NSString
        if let cached = fileCache.object(forKey: cacheKey) {
            return AsyncStream { continuation in
                continuation.yield(cached)
                continuation.finish()
            }
        }
        let cache = fileCache
        return AsyncStream { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: pixelSide, height: pixelSide),
                scale: 1,
                representationTypes: .thumbnail
            )
            let task = Task {
                if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    let image = representation.uiImage
                    cache.setObject(image, forKey: cacheKey)
                    continuation.yield(image)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Elemento video pronto per la riproduzione. Restituisce `nil` se il video è solo su iCloud
    /// e la rete non è consentita.
    func playerItem(for item: IndexedItem, allowNetwork: Bool) async -> AVPlayerItem? {
        if item.source == .photoLibrary {
            guard let libraryAsset = self.asset(for: item.sourceIdentifier) else { return nil }
            let manager = imageManager
            return await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = allowNetwork
                options.deliveryMode = .automatic
                manager.requestPlayerItem(forVideo: libraryAsset, options: options) { playerItem, _ in
                    continuation.resume(returning: playerItem)
                }
            }
        }
        guard let url = folders.url(for: item) else { return nil }
        return AVPlayerItem(url: url)
    }
}
