import SwiftUI

/// Stato e controllo della scansione progressiva: fasi, pause, condizioni del dispositivo.
struct AnalyzeView: View {
    @Environment(AppEnvironment.self) private var env

    private var scan: ScanCoordinator { env.scan }
    private var summary: CatalogSummary { env.store.summary }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                phasesSection
                indexedSection
                conditionsSection
                optionsSection
                Section {
                    NavigationLink("Cosa può fare ClearSpace su iPhone") {
                        CapabilitiesInfoView()
                    }
                }
            }
            .navigationTitle("Analizza")
        }
    }

    // MARK: - Stato

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: statusSymbol)
                        .font(.title2)
                        .foregroundStyle(statusTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(.headline)
                        if !scan.activity.isEmpty {
                            Text(scan.activity)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let reason = scan.pauseReason {
                    InfoBanner(text: reason.message, systemImage: "pause.circle.fill", tint: Theme.later)
                }
                if scan.needsRescan && !scan.isRunning {
                    InfoBanner(text: "La libreria è cambiata dall'ultima analisi: aggiornala per vedere i nuovi contenuti.")
                }
                controls
            }
            .padding(.vertical, 4)
        } footer: {
            if let last = env.preferences.values.lastScanCompletedAt {
                Text("Ultima analisi completata: \(Format.dateTime(last)). Le analisi successive riesaminano solo ciò che è nuovo o modificato.")
            } else {
                Text("L'analisi legge prima i metadati, poi le anteprime e solo alla fine, per i candidati, il contenuto originale. Nulla viene eliminato.")
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if scan.isRunning {
            HStack {
                if scan.isPaused {
                    Button {
                        scan.resume()
                    } label: {
                        Label("Riprendi", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        scan.pause()
                    } label: {
                        Label("Pausa", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) {
                    scan.cancel()
                } label: {
                    Label("Interrompi", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        } else {
            HStack {
                Button {
                    scan.start(deep: true)
                } label: {
                    Label("Analisi completa", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    scan.start(deep: false)
                } label: {
                    Label("Rapida", systemImage: "hare")
                }
                .buttonStyle(.bordered)
            }
            .disabled(!env.photos.canRead && env.folders.folders.isEmpty)
        }
    }

    private var statusTitle: String {
        switch scan.state {
        case .idle: return summary.totalCount == 0 ? "Nessuna analisi eseguita" : "Analisi non in corso"
        case .running(let phase): return "Fase \(phase.letter) · \(phase.title)"
        case .paused: return "Analisi in pausa"
        case .completed: return "Analisi completata"
        case .cancelled: return "Analisi interrotta"
        }
    }

    private var statusSymbol: String {
        switch scan.state {
        case .idle: return "circle.dashed"
        case .running: return "arrow.triangle.2.circlepath"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private var statusTint: Color {
        switch scan.state {
        case .completed: return Theme.keep
        case .paused: return Theme.later
        case .cancelled: return .secondary
        case .idle, .running: return .accentColor
        }
    }

    // MARK: - Fasi

    private var phasesSection: some View {
        Section("Fasi dell'analisi") {
            ForEach(ScanPhase.allCases) { phase in
                let progress = scan.phaseProgress(phase)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(phase.letter) · \(phase.title)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        phaseBadge(phase, progress: progress)
                    }
                    Text(phase.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if scan.currentPhase == phase && progress.total > 0 {
                        ProgressView(value: progress.fraction)
                    }
                }
                .padding(.vertical, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("E · Esecuzione")
                    .font(.subheadline.weight(.semibold))
                Text("Avviene solo dalla scheda Revisione, dopo la tua conferma, ed è seguita dalla verifica dei risultati.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func phaseBadge(_ phase: ScanPhase, progress: PhaseProgress) -> some View {
        if scan.currentPhase == phase {
            Text(progress.total > 0 ? Format.percent(progress.fraction) : "In corso")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
        } else if progress.total > 0 && progress.completed >= progress.total {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.keep)
                .accessibilityLabel("Completata")
        }
    }

    // MARK: - Contenuti indicizzati

    private var indexedSection: some View {
        Section {
            ForEach(StorageSource.allCases, id: \.self) { source in
                let stat = summary.stat(source)
                HStack {
                    Label(source.title, systemImage: source.systemImage)
                    Spacer()
                    Text("\(Format.count(stat.count)) · \(Format.bytes(stat.bytes))")
                        .foregroundStyle(.secondary)
                }
            }
            DetailRow(label: "Anteprime analizzate", value: Format.percent(summary.analysisProgress))
            DetailRow(label: "Solo online, non scaricati", value: Format.count(summary.analysis[.unavailableOffline] ?? 0))
            DetailRow(label: "Elementi protetti", value: Format.count(summary.protectedCount))
        } header: {
            Text("Contenuti indicizzati")
        } footer: {
            Text("L'indice contiene solo riferimenti e metadati, cifrati sul dispositivo. I file originali non vengono mai copiati.")
        }
    }

    // MARK: - Dispositivo

    private var conditionsSection: some View {
        Section("Condizioni del dispositivo") {
            DetailRow(label: "Accesso a Foto", value: env.photos.statusDescription)
            DetailRow(label: "Rete", value: env.conditions.networkDescription)
            DetailRow(
                label: "Batteria",
                value: "\(Format.percent(Double(env.conditions.batteryLevel)))\(env.conditions.isCharging ? " · in carica" : "")"
            )
            DetailRow(label: "Temperatura", value: thermalDescription)
        }
    }

    private var thermalDescription: String {
        switch env.conditions.thermalState {
        case .nominal: return "Normale"
        case .fair: return "Tiepido"
        case .serious: return "Caldo"
        case .critical: return "Molto caldo"
        @unknown default: return "Sconosciuta"
        }
    }

    // MARK: - Opzioni

    private var optionsSection: some View {
        Section {
            Toggle("Scarica da iCloud solo con Wi‑Fi", isOn: env.preferences.binding(\.wifiOnlyDownloads))
            Toggle("Consenti il download degli originali per verificare i duplicati", isOn: env.preferences.binding(\.allowCloudDownloadsForAnalysis))
            Toggle("Pausa con batteria scarica o dispositivo caldo", isOn: env.preferences.binding(\.pauseOnLowBattery))
        } header: {
            Text("Opzioni")
        } footer: {
            Text("Senza il consenso al download, i contenuti presenti solo su iCloud vengono confrontati tramite le anteprime e non sono mai dichiarati duplicati esatti.")
        }
    }
}
