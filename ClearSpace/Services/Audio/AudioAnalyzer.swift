import Foundation
import AVFoundation
import Observation

/// Risultato dell'analisi di una registrazione.
struct AudioAnalysis: Sendable {
    var duration: Double
    /// Volume (RMS) per ogni decimo di secondo.
    var envelope: [Float]
    /// Intervalli di silenzio prolungato, in secondi dall'inizio.
    var silences: [ClosedRange<Double>]
    /// Impronta compatta dell'andamento sonoro (64 valori normalizzati).
    var fingerprint: [Float]

    var longestSilence: Double {
        silences.map { $0.upperBound - $0.lowerBound }.max() ?? 0
    }
}

enum AudioAnalysisError: Error {
    case unreadable
}

/// Analisi locale dei file audio: durata, forma d'onda, silenzi e impronta per il confronto.
enum AudioAnalyzer {

    static let windowsPerSecond = 10.0
    static let fingerprintLength = 64

    /// Legge l'intero file a blocchi. Va chiamato fuori dal thread principale.
    static func analyze(url: URL, maximumDuration: Double = 6 * 3_600) throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            throw AudioAnalysisError.unreadable
        }

        let windowFrames = max(1, Int(sampleRate / windowsPerSecond))
        var envelope: [Float] = []
        var sumOfSquares: Float = 0
        var framesInWindow = 0

        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }
            let samples = channels[0]
            for index in 0..<frames {
                let sample = samples[index]
                sumOfSquares += sample * sample
                framesInWindow += 1
                if framesInWindow == windowFrames {
                    envelope.append((sumOfSquares / Float(windowFrames)).squareRoot())
                    sumOfSquares = 0
                    framesInWindow = 0
                }
            }
            if Double(envelope.count) / windowsPerSecond > maximumDuration { break }
        }

        let duration = Double(file.length) / sampleRate
        return AudioAnalysis(
            duration: duration,
            envelope: envelope,
            silences: silences(in: envelope),
            fingerprint: fingerprint(of: envelope)
        )
    }

    /// Intervalli in cui il volume resta sotto soglia per almeno `minimumDuration` secondi.
    static func silences(
        in envelope: [Float],
        level: Float = AppConfiguration.Thresholds.silenceLevel,
        minimumDuration: Double = AppConfiguration.Thresholds.longSilence
    ) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var start: Int?
        for (index, value) in envelope.enumerated() {
            if value < level {
                if start == nil { start = index }
            } else if let begin = start {
                appendSilence(from: begin, to: index, minimumDuration: minimumDuration, into: &result)
                start = nil
            }
        }
        if let begin = start {
            appendSilence(from: begin, to: envelope.count, minimumDuration: minimumDuration, into: &result)
        }
        return result
    }

    private static func appendSilence(
        from begin: Int,
        to end: Int,
        minimumDuration: Double,
        into result: inout [ClosedRange<Double>]
    ) {
        let startTime = Double(begin) / windowsPerSecond
        let endTime = Double(end) / windowsPerSecond
        if endTime - startTime >= minimumDuration {
            result.append(startTime...endTime)
        }
    }

    /// Riduce l'andamento del volume a `count` valori tra 0 e 1, per disegnare la forma d'onda.
    static func waveform(from envelope: [Float], bars count: Int) -> [Float] {
        guard count > 0, !envelope.isEmpty else { return [] }
        var bars = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let lower = index * envelope.count / count
            let upper = max(lower + 1, (index + 1) * envelope.count / count)
            var peak: Float = 0
            for position in lower..<min(upper, envelope.count) {
                peak = max(peak, envelope[position])
            }
            bars[index] = peak
        }
        let maximum = bars.max() ?? 0
        guard maximum > 0 else { return bars }
        return bars.map { $0 / maximum }
    }

    static func fingerprint(of envelope: [Float]) -> [Float] {
        waveform(from: envelope, bars: fingerprintLength)
    }

    /// Somiglianza tra due impronte: 1 = andamento identico.
    static func similarity(_ first: [Float], _ second: [Float]) -> Double {
        guard first.count == second.count, !first.isEmpty else { return 0 }
        var difference: Float = 0
        for index in first.indices {
            difference += abs(first[index] - second[index])
        }
        return Double(max(0, 1 - difference / Float(first.count)))
    }
}

/// Riproduzione di un file audio con avanzamento osservabile dall'interfaccia.
@MainActor
@Observable
final class AudioPlayerController {

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var progress: Double {
        duration > 0 ? min(1, currentTime / duration) : 0
    }

    func load(url: URL) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = 0
            errorMessage = nil
        } catch {
            player = nil
            errorMessage = "Impossibile riprodurre questo file."
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            startTicker()
        }
    }

    func seek(toFraction fraction: Double) {
        guard let player else { return }
        let target = min(max(fraction, 0), 1) * player.duration
        player.currentTime = target
        currentTime = target
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    if player.currentTime == 0 { self.currentTime = 0 }
                    return
                }
            }
        }
    }
}
