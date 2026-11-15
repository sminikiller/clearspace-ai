import Foundation
import AVFoundation
import Photos
import QuickLookThumbnailing
import UIKit

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
