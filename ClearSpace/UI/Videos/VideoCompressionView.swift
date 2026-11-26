import AVKit
import SwiftUI

/// Compressione facoltativa di un video, con confronto tra originale e versione compressa.
/// L'originale non viene mai eliminato da qui: dopo aver salvato e verificato la nuova copia
/// si può soltanto proporlo per la revisione, con una scelta esplicita.
struct VideoCompressionView: View {
    let itemID: UUID

    @Environment(AppEnvironment.self) private var env
    @State private var preset: CompressionPreset = .hevc1080
    @State private var isCompressing = false
    @State private var progress = 0.0
    @State private var result: CompressionResult?
    @State private var comparisonPlayer: AVPlayer?
    @State private var isSaving = false
    @State private var savedIdentifier: String?
    @State private var errorMessage: String?
    @State private var showsOriginal = false
    @State private var toast: String?

    var body: some View {
        Group {
            if env.plan.isUnlocked(.videoCompression) {
                content
            } else {
                LockedFeatureView(feature: .videoCompression)
            }
        }
        .navigationTitle("Comprimi video")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsOriginal) {
            ItemPreviewScreen(itemID: itemID, showsActions: false)
        }
        .onDisappear {
            comparisonPlayer?.pause()
            // Una compressione non salvata viene scartata insieme al suo file temporaneo.
            if let result, savedIdentifier == nil {
                env.compression.discard(result)
            }
        }
        .toast($toast)
    }

    @ViewBuilder
    private var content: some View {
        if let item = env.store.item(itemID) {
            ReadableList {
                Section {
                    InfoBanner(
                        text: "La compressione è facoltativa e può ridurre la qualità. Non garantisce un risparmio su ogni video: confronta il risultato prima di salvarlo.",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: Theme.later
                    )
                }

                Section("Originale") {
                    DetailRow(label: "Dimensione", value: Format.bytesOrUnknown(item.estimatedBytes))
                    DetailRow(label: "Risoluzione", value: "\(item.pixelWidth) × \(item.pixelHeight)")
                    DetailRow(label: "Durata", value: Format.duration(item.duration))
                }

                if savedIdentifier != nil {
                    savedSection(for: item)
                } else if let result {
                    comparisonSection(result)
                } else {
                    presetSection(for: item)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon")
                            .foregroundStyle(Theme.remove)
                    }
                }
            }
        } else {
            ContentUnavailableView("Video non più disponibile", systemImage: "video.slash")
        }
    }

    // MARK: - Scelta del profilo

    private func presetSection(for item: IndexedItem) -> some View {
        Section {
            Picker("Profilo", selection: $preset) {
                ForEach(CompressionPreset.allCases) { option in
                    VStack(alignment: .leading) {
                        Text(option.title)
                        Text(option.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.inline)
            .disabled(isCompressing)

            if isCompressing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                    Text("Creazione della versione compressa: \(Format.percent(progress))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Crea la versione compressa") {
                    compress(item)
                }
            }
        } header: {
            Text("Profilo di compressione")
        } footer: {
            Text("Viene creata una copia temporanea. L'originale resta al suo posto finché non decidi diversamente.")
        }
    }

    // MARK: - Confronto

    private func comparisonSection(_ result: CompressionResult) -> some View {
        Section {
            DetailRow(label: "Versione compressa", value: Format.bytes(result.compressedBytes))
            DetailRow(
                label: "Risparmio",
                value: "\(Format.bytes(result.savedBytes)) (\(Format.percent(result.savedFraction)))"
            )
            if let comparisonPlayer {
                VideoPlayer(player: comparisonPlayer)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }
            Button("Rivedi l'originale") {
                comparisonPlayer?.pause()
                showsOriginal = true
            }

            Button {
                save(result)
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Salva la versione compressa nella libreria")
                }
            }
            .disabled(isSaving)

            Button("Scarta", role: .destructive) {
                discard(result)
            }
            .disabled(isSaving)
        } header: {
            Text("Anteprima della versione compressa")
        } footer: {
            Text("Guarda l'anteprima e confrontala con l'originale: se la qualità non ti convince, scartala.")
        }
    }

    // MARK: - Dopo il salvataggio

    private func savedSection(for item: IndexedItem) -> some View {
        Section {
            Label("La nuova copia è stata salvata e verificata.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Theme.keep)
            if item.reviewStatus.isQueuedForDeletion {
                Label("L'originale è nella lista di revisione.", systemImage: "checklist")
            } else {
                Button("Proponi l'originale per l'eliminazione") {
                    let outcome = env.safety.apply(.delete, to: item.id)
                    if case .blocked(let reason) = outcome {
                        toast = reason.message
                    } else {
                        toast = "Originale aggiunto alla revisione: verrà eliminato solo dopo la tua conferma."
                    }
                }
            }
        } header: {
            Text("Copia salvata")
        } footer: {
            Text("L'originale non viene eliminato automaticamente. Se lo proponi, lo ritrovi nella scheda Revisione insieme agli altri elementi da confermare.")
        }
    }

    // MARK: - Azioni

    private func compress(_ item: IndexedItem) {
        env.recordTutorial(.compressVideo)
        isCompressing = true
        progress = 0
        errorMessage = nil
        let chosen = preset
        Task {
            do {
                let output = try await env.compression.compress(
                    item: item,
                    preset: chosen,
                    allowNetwork: env.canDownloadForViewing
                ) { value in
                    progress = value
                }
                result = output
                comparisonPlayer = AVPlayer(url: output.outputURL)
            } catch let error as CompressionError {
                errorMessage = error.message
            } catch {
                errorMessage = "Compressione non riuscita."
            }
            isCompressing = false
        }
    }

    private func save(_ output: CompressionResult) {
        guard let item = env.store.item(itemID) else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                savedIdentifier = try await env.compression.saveToLibrary(output, originalIdentifier: item.sourceIdentifier)
                comparisonPlayer?.pause()
                comparisonPlayer = nil
                // La nuova copia entra nell'indice con una scansione leggera.
                if !env.scan.isRunning {
                    env.scan.start(deep: false)
                }
            } catch let error as CompressionError {
                errorMessage = error.message
            } catch {
                errorMessage = "Salvataggio non riuscito."
            }
            isSaving = false
        }
    }

    private func discard(_ output: CompressionResult) {
        comparisonPlayer?.pause()
        comparisonPlayer = nil
        env.compression.discard(output)
        result = nil
    }
}
