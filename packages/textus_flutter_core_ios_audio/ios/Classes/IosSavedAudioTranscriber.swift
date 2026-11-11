import Foundation
import Speech

/// A URL request over the saved original, constrained to on-device recognition.
final class IosSavedAudioTranscriber {
    struct Capability {
        let available: Bool
        let reason: String?
    }

    static func capability(locale: String) -> Capability {
        let supported = SFSpeechRecognizer.supportedLocales().contains {
            $0.identifier.replacingOccurrences(of: "_", with: "-") == locale
        }
        guard supported, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            return Capability(available: false, reason: "The exact speech locale is unsupported")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return Capability(available: false, reason: "On-device recognition is unsupported for this locale")
        }
        guard recognizer.isAvailable else {
            return Capability(available: false, reason: "Local speech recognition is currently unavailable")
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return Capability(available: true, reason: nil)
        case .notDetermined:
            return Capability(available: true, reason: "Speech permission is requested on explicit use")
        case .denied:
            return Capability(available: false, reason: "Speech permission was denied")
        case .restricted:
            return Capability(available: false, reason: "Speech permission is restricted")
        @unknown default:
            return Capability(available: false, reason: "Speech permission status is unavailable")
        }
    }

    private let url: URL
    private let recognizer: SFSpeechRecognizer
    private var task: SFSpeechRecognitionTask?
    private var timer: DispatchSourceTimer?
    private var finished = false
    private let completion: (Result<String, Error>) -> Void

    init(bytes: Data, locale: String, completion: @escaping (Result<String, Error>) -> Void) throws {
        try CanonicalPcmWaveAudio.validate(bytes)
        let capability = Self.capability(locale: locale)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized, capability.available,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            throw NativeAudioFailure("unavailable", capability.reason ?? "Speech authorization is required")
        }
        self.recognizer = recognizer
        self.completion = completion
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            try? cleanup()
            throw error
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        self.timer = timer
        timer.schedule(deadline: .now() + 60)
        timer.setEventHandler { [weak self] in
            self?.publish(.failure(NativeAudioFailure("timeout", "Saved-audio recognition timed out")))
        }
        timer.resume()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, !self.finished else { return }
                if let error = error {
                    self.publish(.failure(error))
                } else if let result = result {
                    guard result.isFinal else { return }
                    let text = result.bestTranscription.formattedString
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.publish(.failure(NativeAudioFailure("missingFinalResult", "Final speech text is blank")))
                        return
                    }
                    self.publish(.success(text))
                } else {
                    self.publish(.failure(NativeAudioFailure("missingFinalResult", "No final speech result was returned")))
                }
            }
        }
    }

    func cleanup() throws {
        finished = true
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        task?.cancel()
        task = nil
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func publish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        completion(result)
    }
}
