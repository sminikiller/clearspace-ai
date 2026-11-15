import Foundation
import Photos
import CoreLocation

/// Informazioni ricavate dalle risorse di un asset (file originali, modifiche, video delle Live Photo).
struct ResourceInfo: Sendable {
    var filename: String?
    /// Dimensione complessiva di tutte le risorse dell'asset.
    var totalBytes: Int64?
    /// Parte effettivamente presente sul dispositivo, se nota.
    var localBytes: Int64?
    /// `true` se l'originale è sul dispositivo, `false` se è solo su iCloud, `nil` se non determinabile.
    var originalIsLocal: Bool?
    var isRAW = false
}

enum PhotoResourceInspector {

    static func inspect(_ asset: PHAsset) -> ResourceInfo {
        let resources = PHAssetResource.assetResources(for: asset)
        var info = ResourceInfo()
        guard !resources.isEmpty else { return info }

        let primary = primaryResource(in: resources, mediaType: asset.mediaType)
        info.filename = primary?.originalFilename ?? resources.first?.originalFilename

        var total: Int64 = 0
        var local: Int64 = 0
        var sizeKnown = false
        var localityKnown = true
        for resource in resources {
            let identifier = resource.uniformTypeIdentifier.lowercased()
            if identifier.contains("raw") || identifier.contains("dng") || resource.type == .alternatePhoto {
                info.isRAW = true
            }
            guard let size = int64Value(resource, key: "fileSize") else { continue }
            total += size
            sizeKnown = true
            if let isLocal = boolValue(resource, key: "locallyAvailable") {
                if isLocal { local += size }
            } else {
                localityKnown = false
            }
        }
        if sizeKnown {
            info.totalBytes = total
            if localityKnown { info.localBytes = local }
        }
        if let primary {
            info.originalIsLocal = boolValue(primary, key: "locallyAvailable")
        }
        return info
    }

    /// Risorsa che contiene l'originale: la foto o il video, non le versioni modificate.
    static func primaryResource(in resources: [PHAssetResource], mediaType: PHAssetMediaType) -> PHAssetResource? {
        let wanted: PHAssetResourceType = mediaType == .video ? .video : .photo
        return resources.first { $0.type == wanted } ?? resources.first
    }

    static func primaryResource(for asset: PHAsset) -> PHAssetResource? {
        primaryResource(in: PHAssetResource.assetResources(for: asset), mediaType: asset.mediaType)
    }

    // PhotoKit non offre un'API pubblica per la dimensione su disco e la disponibilità locale
    // delle risorse. Si legge il valore via KVC in modo difensivo: se la chiave non esiste
    // si restituisce `nil` e l'app ripiega su una stima dichiarata come tale.
    private static func rawValue(_ resource: PHAssetResource, key: String) -> Any? {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        let candidates = [key, "is" + capitalized]
        guard candidates.contains(where: { resource.responds(to: NSSelectorFromString($0)) }) else {
            return nil
        }
        return resource.value(forKey: key)
    }

    private static func int64Value(_ resource: PHAssetResource, key: String) -> Int64? {
        (rawValue(resource, key: key) as? NSNumber)?.int64Value
    }

    private static func boolValue(_ resource: PHAssetResource, key: String) -> Bool? {
        (rawValue(resource, key: key) as? NSNumber)?.boolValue
    }

    /// Stima usata quando il sistema non fornisce la dimensione: è approssimativa e viene segnalata come tale.
    static func estimatedBytes(for asset: PHAsset) -> Int64 {
        let pixels = Double(asset.pixelWidth * asset.pixelHeight)
        if asset.mediaType == .video {
            let megabitsPerSecond: Double
            let shortSide = min(asset.pixelWidth, asset.pixelHeight)
            if shortSide >= 2160 {
                megabitsPerSecond = 45
            } else if shortSide >= 1080 {
                megabitsPerSecond = 10
            } else if shortSide >= 720 {
                megabitsPerSecond = 5
            } else {
                megabitsPerSecond = 2
            }
            return Int64(asset.duration * megabitsPerSecond * 125_000)
        }
        var bytesPerPixel = 0.35
        if asset.mediaSubtypes.contains(.photoScreenshot) { bytesPerPixel = 0.25 }
        if asset.mediaSubtypes.contains(.photoLive) { bytesPerPixel += 0.30 }
        return Int64(pixels * bytesPerPixel)
    }
}

/// Fase A della scansione: legge i metadati di tutti gli asset della libreria.
/// È economica (nessun contenuto viene scaricato) e incrementale: per gli asset non modificati
/// riusa le informazioni già note.
actor PhotoIndexer {

    /// Indicizza la libreria a lotti. Restituisce gli identificativi incontrati,
    /// oppure `nil` se la scansione è stata interrotta.
    func indexLibrary(
        existing: [String: IndexedItem],
        includeHidden: Bool,
        control: ScanControl,
        onBatch: @Sendable ([IndexedItem]) async -> Void
    ) async -> Set<String>? {
        let options = PHFetchOptions()
        options.includeHiddenAssets = includeHidden
        options.includeAllBurstAssets = true
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        let total = result.count

        let selfies = Self.identifiers(inSmartAlbum: .smartAlbumSelfPortraits)
        var seen = Set<String>()
        seen.reserveCapacity(total)

        var position = 0
        while position < total {
            let upper = min(position + 300, total)
            let range = position..<upper
            let batch: [IndexedItem] = autoreleasepool {
                var items: [IndexedItem] = []
                items.reserveCapacity(range.count)
                for index in range {
                    let asset = result.object(at: index)
                    guard asset.mediaType == .image || asset.mediaType == .video else { continue }
                    let identifier = asset.localIdentifier
                    items.append(Self.makeItem(
                        asset,
                        existing: existing[identifier],
                        isSelfie: selfies.contains(identifier)
                    ))
                }
                return items
            }
            for item in batch {
                seen.insert(item.sourceIdentifier)
            }
            position = upper
            await onBatch(batch)
            await control.progress(position, total)
            if !(await control.shouldContinue()) { return nil }
        }
        return seen
    }

    private static func identifiers(inSmartAlbum subtype: PHAssetCollectionSubtype) -> Set<String> {
        var result = Set<String>()
        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
        for index in 0..<collections.count {
            let assets = PHAsset.fetchAssets(in: collections.object(at: index), options: nil)
            for assetIndex in 0..<assets.count {
                result.insert(assets.object(at: assetIndex).localIdentifier)
            }
        }
        return result
    }

    private static let resourceDerivedTraits: ItemTraits = [
        .cloudOnly, .screenRecording, .fromOtherApp, .raw, .heavyForResolution
    ]

    static func makeItem(_ asset: PHAsset, existing: IndexedItem?, isSelfie: Bool) -> IndexedItem {
        let isVideo = asset.mediaType == .video
        let subtypes = asset.mediaSubtypes
        var traits: ItemTraits = []

        if subtypes.contains(.photoScreenshot) { traits.insert(.screenshot) }
        if subtypes.contains(.photoLive) { traits.insert(.livePhoto) }
        if subtypes.contains(.photoPanorama) { traits.insert(.panorama) }
        if subtypes.contains(.photoHDR) { traits.insert(.hdr) }
        if subtypes.contains(.photoDepthEffect) { traits.insert(.portrait) }
        if subtypes.contains(.videoHighFrameRate) { traits.formUnion([.slowMotion, .highFrameRate]) }
        if subtypes.contains(.videoTimelapse) { traits.insert(.timelapse) }
        if subtypes.contains(.videoCinematic) { traits.insert(.cinematic) }
        if asset.burstIdentifier != nil { traits.insert(.burst) }
        if asset.isFavorite { traits.insert(.favorite) }
        if asset.isHidden { traits.insert(.hidden) }
        if asset.hasAdjustments { traits.insert(.edited) }
        if isSelfie { traits.insert(.selfie) }
        if isVideo && min(asset.pixelWidth, asset.pixelHeight) >= 2160 { traits.insert(.video4K) }

        let pixels = asset.pixelWidth * asset.pixelHeight
        if !isVideo && pixels > 0 && pixels < AppConfiguration.Thresholds.lowResolutionPixels {
            traits.insert(.lowResolution)
        }

        var item = IndexedItem(
            sourceIdentifier: asset.localIdentifier,
            source: .photoLibrary,
            category: isVideo ? .video : .photo,
            createdAt: asset.creationDate,
            modifiedAt: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration
        )
        if let coordinate = asset.location?.coordinate {
            item.latitude = coordinate.latitude
            item.longitude = coordinate.longitude
        }
        item.burstIdentifier = asset.burstIdentifier

        // Le risorse sono la parte più costosa da leggere: se l'asset non è cambiato si riusano i dati noti.
        if let existing, existing.modifiedAt == asset.modificationDate, existing.estimatedBytes != nil {
            item.filename = existing.filename
            item.estimatedBytes = existing.estimatedBytes
            item.bytesAreEstimated = existing.bytesAreEstimated
            item.localBytes = existing.localBytes
            traits.formUnion(existing.traits.intersection(resourceDerivedTraits))
        } else {
            let info = PhotoResourceInspector.inspect(asset)
            item.filename = info.filename
            if let total = info.totalBytes, total > 0 {
                item.estimatedBytes = total
                item.bytesAreEstimated = false
                item.localBytes = info.localBytes
            } else {
                item.estimatedBytes = PhotoResourceInspector.estimatedBytes(for: asset)
                item.bytesAreEstimated = true
            }
            if info.originalIsLocal == false { traits.insert(.cloudOnly) }
            if info.isRAW { traits.insert(.raw) }

            let name = (info.filename ?? "").lowercased()
            if isVideo && (name.hasPrefix("rpreplay") || name.hasPrefix("screenrecording")) {
                traits.insert(.screenRecording)
            }
            // Stima dell'origine: le foto scattate con la fotocamera hanno nomi del tipo IMG_1234.
            if !name.isEmpty && !name.hasPrefix("img_") && !traits.contains(.screenshot)
                && !traits.contains(.screenRecording) {
                traits.insert(.fromOtherApp)
            }
            if !isVideo && pixels > 0, let bytes = item.estimatedBytes, !item.bytesAreEstimated {
                let limit = traits.contains(.livePhoto)
                    ? AppConfiguration.Thresholds.heavyBytesPerPixelLive
                    : AppConfiguration.Thresholds.heavyBytesPerPixel
                if Double(bytes) / Double(pixels) > limit {
                    traits.insert(.heavyForResolution)
                }
            }
        }

        item.traits = traits
        return item
    }
}
