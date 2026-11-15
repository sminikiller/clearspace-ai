import Foundation
import CryptoKit
import Photos

/// Hash SHA-256 dei contenuti: è il criterio con cui due file vengono dichiarati identici.
enum FileHasher {

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Hash di un file, letto a blocchi in modo coordinato (adatto anche a iCloud Drive).
    static func sha256(ofFileAt url: URL) throws -> String {
        var coordinationError: NSError?
        var outcome: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readableURL in
            outcome = Result { try hashContents(of: readableURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        return try outcome.get()
    }

    private static func hashContents(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 1 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    /// Hash dell'originale di un asset della libreria Foto.
    /// Restituisce `nil` se il contenuto non è disponibile (ad esempio è solo su iCloud e la rete non è consentita).
    static func sha256(of resource: PHAssetResource, allowNetwork: Bool) async -> String? {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        let hasher = UncheckedBox(SHA256())
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    hasher.value.update(data: data)
                },
                completionHandler: { error in
                    if error != nil {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: hex(hasher.value.finalize()))
                    }
                }
            )
        }
    }
}
