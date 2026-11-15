import SwiftUI

@main
struct ClearSpaceApp: App {

    /// L'ambiente vive quanto l'app: viene creato una sola volta, prima che termini l'avvio.
    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        // Le attività in background vanno registrate prima della fine del lancio.
        environment.background.register()
        self.environment = environment
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}
