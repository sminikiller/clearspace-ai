import Foundation
import SwiftUI

/// Preferenze dell'utente, salvate in `UserDefaults` a ogni modifica.
@MainActor
@Observable
final class PreferencesStore {

    private(set) var values: UserPreferences

    private let defaults: UserDefaults
    private static let storageKey = "clearspace.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            self.values = decoded
        } else {
            self.values = UserPreferences()
        }
    }

    /// Modifica e salva le preferenze.
    func update(_ change: (inout UserPreferences) -> Void) {
        var copy = values
        change(&copy)
        guard copy != values else { return }
        values = copy
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Collega un controllo dell'interfaccia a una preferenza: ogni modifica viene salvata.
    func binding<Value>(_ keyPath: WritableKeyPath<UserPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { self.values[keyPath: keyPath] },
            set: { newValue in
                self.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
