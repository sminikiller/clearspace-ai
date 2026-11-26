import Foundation
import CryptoKit
import Security

enum SecureStoreError: Error {
    case keychain(OSStatus)
    case encryptionFailed
}

/// Chiave simmetrica dell'archivio locale, conservata nel Portachiavi e mai sincronizzata.
enum KeychainKeyStore {

    private static let service = "ClearSpace.datastore"
    private static let account = "index-key-v1"

    static func loadOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw SecureStoreError.keychain(status)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            // Disponibile dopo il primo sblocco (serve alle analisi in background) e solo su questo dispositivo.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureStoreError.keychain(addStatus)
        }
        return key
    }
}

/// Mette in ordine i salvataggi di uno stesso file. Ogni istantanea prende un numero quando viene
/// fatta; la scrittura avviene solo se nessuna istantanea più recente è già stata scritta, e una alla
/// volta. Così il salvataggio periodico e quello di quando l'app va in background, partiti quasi
/// insieme, non possono lasciare sul disco la copia più vecchia al posto della più recente.
final class OrderedSaves: @unchecked Sendable {
    private let lock = NSLock()
    private var issued: UInt64 = 0
    private var written: UInt64 = 0

    /// Numero d'ordine dell'istantanea: va preso nel momento in cui la si fa.
    func ticket() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        issued &+= 1
        return issued
    }

    /// Esegue `write` se l'istantanea è più recente dell'ultima scritta. Restituisce `false` se è stata
    /// saltata perché superata.
    @discardableResult
    func perform(ticket: UInt64, _ write: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ticket > written else { return false }
        write()
        written = ticket
        return true
    }
}

/// Persistenza locale cifrata: JSON → AES-GCM → file protetto da Data Protection.
/// L'archivio contiene solo riferimenti e metadati, mai i contenuti originali, ed è escluso dai backup
/// (un'app che libera spazio non deve occuparne su iCloud).
struct SecureFileStore: Sendable {
    let directory: URL
    private let keyProvider: @Sendable () throws -> SymmetricKey

    init(
        directoryName: String = "ClearSpaceData",
        keyProvider: @escaping @Sendable () throws -> SymmetricKey = { try KeychainKeyStore.loadOrCreateKey() }
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var folder = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        self.directory = folder
        self.keyProvider = keyProvider
    }

    func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func save<Value: Encodable>(_ value: Value, as name: String) throws {
        let plain = try JSONEncoder().encode(value)
        let key = try keyProvider()
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else {
            throw SecureStoreError.encryptionFailed
        }
        try combined.write(
            to: url(for: name),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Restituisce `nil` se il file non esiste, non è decifrabile o ha un formato non più compatibile:
    /// in quel caso l'app riparte da un archivio vuoto.
    func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let combined = try? Data(contentsOf: url(for: name)) else { return nil }
        do {
            let key = try keyProvider()
            let box = try AES.GCM.SealedBox(combined: combined)
            let plain = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode(type, from: plain)
        } catch {
            // Il file esiste ma non è leggibile: se ne conserva una copia prima che venga sovrascritto.
            let backup = url(for: name + ".unreadable")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url(for: name), to: backup)
            return nil
        }
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
