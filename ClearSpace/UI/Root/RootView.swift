import SwiftUI

/// Radice dell'interfaccia: cinque schede, presentazione della modalità swipe e ciclo di vita.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = env.router
        @Bindable var sessions = env.sessions
        @Bindable var environment = env

        Group {
            if env.isReady {
                TabView(selection: $router.selectedTab) {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(AppTab.home)
                    AnalyzeView()
                        .tabItem { Label("Analizza", systemImage: "waveform.and.magnifyingglass") }
                        .tag(AppTab.analyze)
                    ExploreView()
                        .tabItem { Label("Esplora", systemImage: "square.grid.2x2.fill") }
                        .tag(AppTab.explore)
                    ReviewView()
                        .tabItem { Label("Revisione", systemImage: "checklist") }
                        .tag(AppTab.review)
                        .badge(env.store.markedCount)
                    ResultsView()
                        .tabItem { Label("Risultati", systemImage: "chart.bar.fill") }
                        .tag(AppTab.results)
                }
            } else {
                ProgressView("Caricamento dei dati…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task {
            await env.bootstrap()
            env.didBecomeActive()
        }
        .fullScreenCover(isPresented: $sessions.isPresentingSwipe) {
            SwipeSessionView()
                .environment(env)
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
                .environment(env)
        }
        .sheet(isPresented: whatsNewBinding) {
            NavigationStack {
                WhatsNewView(showsCloseButton: true) {
                    markWhatsNewSeen()
                }
            }
            .environment(env)
        }
        .alert(
            "Importazione",
            isPresented: Binding(
                get: { environment.importMessage != nil },
                set: { if !$0 { environment.importMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(env.importMessage ?? "")
        }
        .onOpenURL { url in
            env.handleIncomingFile(url)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                env.didBecomeActive()
            case .background:
                env.didEnterBackground()
            default:
                break
            }
        }
        .onChange(of: env.photos.libraryChangeCount) { _, _ in
            env.scan.noteLibraryChanged()
        }
        .onChange(of: env.sessions.isPresentingSwipe) { _, isPresenting in
            // Durante lo swipe il riepilogo non viene ricalcolato a ogni scelta.
            env.store.pauseSummary(isPresenting)
        }
    }

    /// L'introduzione compare finché non è stata completata una prima volta.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { env.isReady && !env.preferences.values.hasCompletedOnboarding },
            set: { isPresented in
                if !isPresented {
                    env.preferences.update {
                        $0.hasCompletedOnboarding = true
                        $0.lastSeenBuild = AppInfo.build
                    }
                }
            }
        )
    }

    /// Le novità compaiono una volta dopo un aggiornamento, mai al primo avvio (c'è già l'introduzione)
    /// e mai sopra una sessione di pulizia.
    private var whatsNewBinding: Binding<Bool> {
        Binding(
            get: {
                let values = env.preferences.values
                return env.isReady && AppInfo.shouldShowWhatsNew(
                    hasCompletedOnboarding: values.hasCompletedOnboarding,
                    lastSeenBuild: values.lastSeenBuild,
                    currentBuild: AppInfo.build,
                    isBusy: env.sessions.isPresentingSwipe
                )
            },
            set: { isPresented in
                if !isPresented {
                    markWhatsNewSeen()
                }
            }
        )
    }

    private func markWhatsNewSeen() {
        env.preferences.update { $0.lastSeenBuild = AppInfo.build }
    }
}
