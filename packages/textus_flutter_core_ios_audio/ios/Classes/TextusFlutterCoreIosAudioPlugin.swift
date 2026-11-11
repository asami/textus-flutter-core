import AVFoundation
import CoreFoundation
import Flutter
import Foundation
import Speech
import UIKit

struct NativeAudioFailure: Error {
    let code: String
    let message: String
    init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

private final class OnceAudioResult {
    private var result: FlutterResult?
    init(_ result: @escaping FlutterResult) { self.result = result }
    func settle(_ value: Any?) {
        guard let result = result else { return }
        self.result = nil
        result(value)
    }
}

/// iOS registration is inert apart from lifecycle observation.
public final class TextusFlutterCoreIosAudioPlugin: NSObject, FlutterPlugin {
    private enum Kind { case availability, preparation, recording, playback, transcription }
    private final class Operation {
        let token: AudioOperationOwner.Token
        let kind: Kind
        var pending: OnceAudioResult?
        var deferred: (() -> Void)?
        var recording: IosAudioRecording?
        var playback: IosAudioPlayback?
        var transcriber: IosSavedAudioTranscriber?
        var recordingAccepted = false
        var audioSessionActive = false
        init(_ token: AudioOperationOwner.Token, _ kind: Kind, _ result: OnceAudioResult) {
            self.token = token
            self.kind = kind
            pending = result
        }
    }

    private let owner = AudioOperationOwner()
    private var sessions: [String: Operation] = [:]
    private var observers: [NSObjectProtocol] = []
    private var detached = false
    private let channel: FlutterMethodChannel
    private static let providerID = "ios-on-device-speech"

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            for operation in Array(self.sessions.values) {
                _ = self.cancel(operation, reason: "Audio operation cancelled in background")
            }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.detached else { return }
            for operation in Array(self.sessions.values) where self.current(operation) {
                let resume = operation.deferred
                operation.deferred = nil
                self.foreground(operation) { resume?() }
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
                  type.uintValue == AVAudioSession.InterruptionType.began.rawValue else { return }
            for operation in Array(self.sessions.values) where self.owner.ownsMedia(operation.token) {
                _ = self.cancel(operation, reason: "Audio operation cancelled by interruption")
            }
        })
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        IosVoiceTextCleanupPlugin.register(with: registrar)
        let channel = FlutterMethodChannel(
            name: "org.textus.flutter.core/ios_audio", binaryMessenger: registrar.messenger()
        )
        let instance = TextusFlutterCoreIosAudioPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let once = OnceAudioResult(result)
        if Thread.isMainThread {
            handleOnMain(call, result: once)
        } else {
            DispatchQueue.main.async { self.handleOnMain(call, result: once) }
        }
    }

    private func handleOnMain(_ call: FlutterMethodCall, result: OnceAudioResult) {
        let extras: Set<String>
        switch call.method {
        case "availability", "prepare": extras = ["locale"]
        case "startRecording": extras = ["maxDurationSeconds"]
        case "play": extras = ["bytes"]
        case "transcribe": extras = ["bytes", "locale"]
        case "stopRecording", "cancelRecording", "stopPlayback", "cancelTranscription", "dispose": extras = []
        default: result.settle(FlutterMethodNotImplemented); return
        }
        do {
            guard !detached else { throw NativeAudioFailure("disposed", "Audio plugin is detached") }
            guard let arguments = call.arguments as? [String: Any],
                  Set(arguments.keys) == extras.union(["sessionId"]),
                  let sessionID = arguments["sessionId"] as? String,
                  matches(sessionID, "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$") else {
                throw NativeAudioFailure("invalidArguments", "Expected exact audio arguments and a safe sessionId")
            }
            if call.method == "dispose" {
                let error = sessions[sessionID].flatMap { cancel($0, reason: "Audio session disposed") }
                owner.dispose(sessionID: sessionID)
                result.settle(error.map { flutterError($0) })
                return
            }
            guard !owner.isDisposed(sessionID: sessionID) else {
                throw NativeAudioFailure("disposed", "Audio session is disposed")
            }
            switch call.method {
            case "availability":
                let locale = try exactLocale(arguments)
                let operation = try begin(sessionID, .availability, result)
                finish(operation, value: availability(locale))
            case "prepare":
                let locale = try exactLocale(arguments)
                let operation = try begin(sessionID, .preparation, result)
                foreground(operation) { [weak self, weak operation] in
                    guard let self = self, let operation = operation else { return }
                    self.authorizeSpeech(operation) {
                        self.finish(operation, value: self.availability(locale))
                    }
                }
            case "startRecording":
                let duration = try recordingDuration(arguments["maxDurationSeconds"])
                let operation = try begin(sessionID, .recording, result, media: true)
                foreground(operation) { [weak self, weak operation] in
                    guard let self = self, let operation = operation else { return }
                    self.authorizeMicrophone(operation) {
                        self.startRecording(operation, duration: duration)
                    }
                }
            case "stopRecording":
                guard let operation = sessions[sessionID], operation.kind == .recording,
                      operation.recordingAccepted, let recording = operation.recording else {
                    throw NativeAudioFailure("invalidState", "Recording start must be accepted before stop")
                }
                operation.pending = result
                do {
                    let bytes = try recording.stop()
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.calendar = Calendar(identifier: .gregorian)
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                    finish(operation, value: [
                        "bytes": FlutterStandardTypedData(bytes: bytes),
                        "capturedAt": formatter.string(from: recording.capturedAt),
                        "originalName": "recording.wav"
                    ])
                } catch { finish(operation, error: error) }
            case "play":
                let bytes = try savedBytes(arguments)
                let operation = try begin(sessionID, .playback, result, media: true)
                foreground(operation) { [weak self, weak operation] in
                    guard let self = self, let operation = operation else { return }
                    do {
                        try self.activate(operation, category: .playback)
                        operation.playback = try IosAudioPlayback(bytes: bytes) { [weak self, weak operation] outcome in
                            guard let self = self, let operation = operation, self.current(operation) else { return }
                            switch outcome {
                            case .success: self.finish(operation)
                            case .failure(let error): self.finish(operation, error: error)
                            }
                        }
                    } catch { self.finish(operation, error: error) }
                }
            case "transcribe":
                let bytes = try savedBytes(arguments)
                let locale = try exactLocale(arguments)
                let operation = try begin(sessionID, .transcription, result, media: true)
                foreground(operation) { [weak self, weak operation] in
                    guard let self = self, let operation = operation else { return }
                    self.authorizeSpeech(operation) {
                        do {
                            let capability = IosSavedAudioTranscriber.capability(locale: locale)
                            guard capability.available else {
                                throw NativeAudioFailure("unavailable", capability.reason ?? "Local speech is unavailable")
                            }
                            operation.transcriber = try IosSavedAudioTranscriber(bytes: bytes, locale: locale) {
                                [weak self, weak operation] outcome in
                                guard let self = self, let operation = operation, self.current(operation) else { return }
                                switch outcome {
                                case .success(let text):
                                    self.finish(operation, value: [
                                        "text": text,
                                        "extensions": [
                                            "providerId": Self.providerID, "locale": locale, "onDevice": true
                                        ]
                                    ])
                                case .failure(let error): self.finish(operation, error: error)
                                }
                            }
                        } catch { self.finish(operation, error: error) }
                    }
                }
            case "cancelRecording":
                try cleanup(sessionID, kinds: [.recording], result: result)
            case "stopPlayback":
                try cleanup(sessionID, kinds: [.playback], result: result)
            case "cancelTranscription":
                try cleanup(sessionID, kinds: [.preparation, .transcription], result: result)
            default: break
            }
        } catch { result.settle(flutterError(error)) }
    }

    private func begin(
        _ sessionID: String, _ kind: Kind, _ result: OnceAudioResult, media: Bool = false
    ) throws -> Operation {
        let token = try owner.acquire(sessionID: sessionID)
        do {
            if media { try owner.acquireMedia(token) }
        } catch {
            owner.retire(token)
            throw error
        }
        let operation = Operation(token, kind, result)
        sessions[sessionID] = operation
        return operation
    }

    private func current(_ operation: Operation) -> Bool {
        !detached && owner.isCurrent(operation.token)
            && sessions[operation.token.sessionID] === operation
    }

    private func foreground(_ operation: Operation, _ action: @escaping () -> Void) {
        guard current(operation) else { return }
        switch UIApplication.shared.applicationState {
        case .active:
            action()
        case .inactive:
            operation.deferred = action
        case .background:
            _ = cancel(operation, reason: "Audio operation requires the foreground")
        @unknown default:
            _ = cancel(operation, reason: "Application foreground state is unavailable")
        }
    }

    private func authorizeMicrophone(_ operation: Operation, _ granted: @escaping () -> Void) {
        guard current(operation) else { return }
        guard usageDescription("NSMicrophoneUsageDescription") else {
            finish(operation, error: NativeAudioFailure("configuration", "NSMicrophoneUsageDescription is required"))
            return
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: foreground(operation, granted)
        case .denied:
            finish(operation, error: NativeAudioFailure("permissionDenied", "Microphone permission was denied"))
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self, weak operation] allowed in
                DispatchQueue.main.async {
                    guard let self = self, let operation = operation, self.current(operation) else { return }
                    if allowed { self.foreground(operation, granted) }
                    else {
                        self.finish(operation, error: NativeAudioFailure("permissionDenied", "Microphone permission was denied"))
                    }
                }
            }
        @unknown default:
            finish(operation, error: NativeAudioFailure("unavailable", "Microphone permission status is unavailable"))
        }
    }

    private func authorizeSpeech(_ operation: Operation, _ granted: @escaping () -> Void) {
        guard current(operation) else { return }
        guard usageDescription("NSSpeechRecognitionUsageDescription") else {
            finish(operation, error: NativeAudioFailure("configuration", "NSSpeechRecognitionUsageDescription is required"))
            return
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self, weak operation] status in
                DispatchQueue.main.async {
                    guard let self = self, let operation = operation, self.current(operation) else { return }
                    self.speechAuthorized(operation, status: status, granted: granted)
                }
            }
        } else {
            speechAuthorized(operation, status: SFSpeechRecognizer.authorizationStatus(), granted: granted)
        }
    }

    private func speechAuthorized(
        _ operation: Operation, status: SFSpeechRecognizerAuthorizationStatus, granted: @escaping () -> Void
    ) {
        guard current(operation) else { return }
        guard status == .authorized else {
            // prepare returns actual unavailable readiness after explicit authorization;
            // transcription cannot produce text without authorization.
            if operation.kind == .preparation {
                foreground(operation, granted)
            } else {
                finish(operation, error: NativeAudioFailure("unavailable", "Speech permission was denied or restricted"))
            }
            return
        }
        foreground(operation, granted)
    }

    private func startRecording(_ operation: Operation, duration: Int) {
        guard current(operation) else { return }
        do {
            try activate(operation, category: .playAndRecord)
            operation.recording = try IosAudioRecording(maxDurationSeconds: duration) {
                [weak self, weak operation] error in
                guard let self = self, let operation = operation, self.current(operation) else { return }
                self.finish(operation, error: error)
            }
            operation.recordingAccepted = true
            operation.pending?.settle(nil)
            operation.pending = nil // Hold the recording lease through explicit stop/cancel.
        } catch { finish(operation, error: error) }
    }

    private func activate(_ operation: Operation, category: AVAudioSession.Category) throws {
        guard current(operation), owner.ownsMedia(operation.token) else {
            throw NativeAudioFailure("cancelled", "Audio operation is no longer current")
        }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(category, mode: .default, options: category == .playAndRecord ? [.defaultToSpeaker] : [])
        try audio.setActive(true)
        operation.audioSessionActive = true
    }

    private func availability(_ locale: String) -> [String: Any] {
        let capability = IosSavedAudioTranscriber.capability(locale: locale)
        return [
            "providerId": Self.providerID, "locale": locale,
            "state": capability.available ? "available" : "unavailable",
            "reason": capability.reason as Any? ?? NSNull()
        ]
    }

    private func cleanup(_ sessionID: String, kinds: [Kind], result: OnceAudioResult) throws {
        guard let operation = sessions[sessionID] else { result.settle(nil); return }
        guard kinds.contains(operation.kind) else {
            throw NativeAudioFailure("invalidState", "Cleanup does not match the active audio operation")
        }
        let error = cancel(operation, reason: "Audio operation cancelled")
        result.settle(error.map { flutterError($0) })
    }

    private func retire(_ operation: Operation) -> Bool {
        let owned = owner.retire(operation.token)
        if sessions[operation.token.sessionID] === operation {
            sessions.removeValue(forKey: operation.token.sessionID)
        }
        operation.deferred = nil
        return owned
    }

    private func cancel(_ operation: Operation, reason: String) -> Error? {
        guard owner.isCurrent(operation.token) else { return nil }
        let owned = retire(operation) // Fence callbacks before result publication or cleanup.
        operation.pending?.settle(flutterError(NativeAudioFailure("cancelled", reason)))
        operation.pending = nil
        return release(operation, owned: owned)
    }

    private func finish(_ operation: Operation, value: Any? = nil, error: Error? = nil) {
        guard current(operation) else { return }
        let owned = retire(operation)
        let cleanupError = release(operation, owned: owned)
        if let error = error ?? cleanupError { operation.pending?.settle(flutterError(error)) }
        else { operation.pending?.settle(value) }
        operation.pending = nil
    }

    private func release(_ operation: Operation, owned: Bool) -> Error? {
        var failure: Error?
        do { try operation.recording?.cleanup() } catch { failure = error }
        operation.recording = nil
        operation.playback?.cleanup()
        operation.playback = nil
        do { try operation.transcriber?.cleanup() } catch { if failure == nil { failure = error } }
        operation.transcriber = nil
        if owned && operation.audioSessionActive {
            do { try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) }
            catch { if failure == nil { failure = error } }
        }
        operation.audioSessionActive = false
        return failure
    }

    private func exactLocale(_ arguments: [String: Any]) throws -> String {
        guard let locale = arguments["locale"] as? String,
              matches(locale, "^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$") else {
            throw NativeAudioFailure("invalidArguments", "Expected an exact nonempty speech locale")
        }
        return locale
    }

    private func savedBytes(_ arguments: [String: Any]) throws -> Data {
        guard let bytes = arguments["bytes"] as? FlutterStandardTypedData, bytes.elementSize == 1 else {
            throw NativeAudioFailure("invalidArguments", "Expected Uint8List saved WAV bytes")
        }
        try CanonicalPcmWaveAudio.validate(bytes.data)
        return bytes.data
    }

    private func recordingDuration(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)),
              number.int64Value >= 1, number.int64Value <= 120 else {
            throw NativeAudioFailure("invalidArguments", "Expected integer maxDurationSeconds in 1...120")
        }
        return number.intValue
    }

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression)?.lowerBound == value.startIndex
            && value.range(of: pattern, options: .regularExpression)?.upperBound == value.endIndex
    }

    private func usageDescription(_ key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func flutterError(_ error: Error) -> FlutterError {
        if let failure = error as? NativeAudioFailure {
            return FlutterError(code: failure.code, message: failure.message, details: nil)
        }
        if let failure = error as? AudioOperationOwner.Failure {
            let code: String
            switch failure {
            case .busy: code = "busy"
            case .disposed: code = "disposed"
            case .retired: code = "cancelled"
            }
            return FlutterError(code: code, message: "Audio operation \(code)", details: nil)
        }
        if error is CanonicalPcmWaveAudio.Failure {
            return FlutterError(code: "invalidAudio", message: "Expected canonical 16 kHz mono PCM16 WAV", details: nil)
        }
        return FlutterError(code: "nativeAudioError", message: error.localizedDescription, details: nil)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        let detach = {
            guard !self.detached else { return }
            for operation in Array(self.sessions.values) {
                _ = self.cancel(operation, reason: "Audio plugin detached")
                self.owner.dispose(sessionID: operation.token.sessionID)
            }
            self.detached = true
            for observer in self.observers { NotificationCenter.default.removeObserver(observer) }
            self.observers.removeAll()
            self.channel.setMethodCallHandler(nil)
        }
        if Thread.isMainThread { detach() }
        else { DispatchQueue.main.sync(execute: detach) }
    }
}
