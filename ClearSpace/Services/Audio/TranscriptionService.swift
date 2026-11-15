import Foundation
import Speech

enum TranscriptionError: Error {
    case notAuthorized
    case recognizerUnavailable
    case onDeviceUnavailable
    case failed(String)

    var message: String {
        switch self {
        case .notAuthorized:
            return "Il riconoscimento vocale non è autorizzato. Puoi attivarlo dalle Impostazioni."
        case .recognizerUnavailable:
            return "Il riconoscimento vocale non è disponibile per questa lingua."
        case .onDeviceUnavailable:
            return "La trascrizione sul dispositivo non è disponibile per questa lingua: per riservatezza ClearSpace non usa quella online."
        case .failed(let reason):
            return "Trascrizione non riuscita: \(reason)"
        }
    }
}

/// Trascrizione delle registrazioni eseguita esclusivamente sul dispositivo:
/// l'audio non viene mai inviato a server esterni.
enum TranscriptionService {

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func isOnDeviceAvailable(localeIdentifier: String) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            return false
        }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    static func transcribe(url: URL, localeIdentifier: String) async throws -> String {
        guard await requestAuthorization() else {
            throw TranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let finished = UncheckedBox(false)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard !finished.value else { return }
                if let error {
                    finished.value = true
                    continuation.resume(throwing: TranscriptionError.failed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    finished.value = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
