import Flutter
import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A separate transient-input channel; no Material, file or network client.
final class IosVoiceTextCleanupPlugin: NSObject, FlutterPlugin {
    private final class Work {
        var task: Task<Void, Never>?
        let result: FlutterResult
        var cancellations: [FlutterResult] = []
        init(_ result: @escaping FlutterResult) { self.result = result }
    }
    private var work: [String: Work] = [:]
    private var background: NSObjectProtocol?
    private var detached = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "org.textus.flutter.core/voice_cleanup", binaryMessenger: registrar.messenger())
        let instance = IosVoiceTextCleanupPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.background = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak instance] _ in instance?.cancelAll() }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.handle(call, result: result) }
            return
        }
        guard !detached else {
            result(FlutterError(code: "detached", message: "Cleanup engine detached", details: nil)); return
        }
        switch call.method {
        case "probe": result(capability())
        case "probeVoiceCleanup":
            guard emptyArguments(call.arguments) else { invalid(result); return }
            result(capability())
        case "prepare", "prepareVoiceCleanup":
            if call.method == "prepareVoiceCleanup" && !emptyArguments(call.arguments) {
                invalid(result); return
            }
            // Apple manages model preparation in system settings, never a cloud fallback.
            let status = capability()
            if status["state"] as? String == "available" { result(nil) }
            else { result(FlutterError(code: "unavailable", message: status["reason"] as? String, details: nil)) }
        case "cancelDraft":
            guard let arguments = call.arguments as? [String: Any],
                  Set(arguments.keys) == ["requestId"], let id = arguments["requestId"] as? String else {
                invalid(result); return
            }
            guard let active = work[id] else { result(false); return }
            active.cancellations.append(result)
            active.task?.cancel()
        case "generateDraft":
            guard let arguments = call.arguments as? [String: Any],
                  let id = arguments["requestId"] as? String,
                  !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines), !id.contains("\0"),
                  arguments["language"] as? String == "ja" else {
                invalid(result); return
            }
            let instructions: String?
            let prompt: String
            switch arguments["operation"] as? String {
            case "voiceTextCleanup":
                guard Set(arguments.keys) == ["requestId", "operation", "language", "bytes", "prompt", "expectedModelName"],
                      arguments["bytes"] is NSNull, arguments["expectedModelName"] is NSNull,
                      let legacy = arguments["prompt"] as? String, !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    invalid(result); return
                }
                instructions = nil
                prompt = legacy
            case "voiceTextCleanupV2":
                guard Set(arguments.keys) == ["requestId", "operation", "language", "instructions", "source", "expectedModelName"],
                      let rules = arguments["instructions"] as? String, !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let source = arguments["source"] as? String, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let data = try? JSONEncoder().encode(source),
                      let sourceJSON = String(data: data, encoding: .utf8) else {
                    invalid(result); return
                }
                if !(arguments["expectedModelName"] is NSNull) {
                    guard let expected = arguments["expectedModelName"] as? String,
                          !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        invalid(result); return
                    }
                    guard expected == "SystemLanguageModel.default" else {
                        result(FlutterError(code: "modelChanged", message: "Selected system model changed", details: nil)); return
                    }
                }
                instructions = rules
                prompt = sourceJSON
            default: invalid(result); return
            }
            guard work[id] == nil else {
                result(FlutterError(code: "busy", message: "Duplicate cleanup request", details: nil)); return
            }
            guard UIApplication.shared.applicationState == .active else {
                result(FlutterError(code: "background", message: "Cleanup requires an active app", details: nil)); return
            }
            let status = capability()
            guard status["state"] as? String == "available" else {
                result(FlutterError(code: "unavailable", message: status["reason"] as? String, details: nil)); return
            }
            let active = Work(result)
            work[id] = active
            active.task = Task { @MainActor [weak self, weak active] in
                guard let self = self, let active = active else { return }
                let value: Any
                do {
                    let text = try await self.generate(prompt, instructions: instructions)
                    try Task.checkCancellation()
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw NativeAudioFailure("emptyResponse", "Local model returned blank text")
                    }
                    value = ["requestId": id, "text": text,
                        "modelName": "SystemLanguageModel.default", "cleanupFailures": [String]()] as [String: Any]
                } catch {
                    let code = Task.isCancelled ? "canceled" : (error as? NativeAudioFailure)?.code ?? "inferenceFailed"
                    value = FlutterError(code: code, message: String(describing: error), details: nil)
                }
                self.work.removeValue(forKey: id)
                active.result(value)
                for cancel in active.cancellations { cancel(true) }
            }
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func capability() -> [String: Any] {
        var reason = "Foundation Models requires iOS 26 or later"
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                if model.supportsLocale(Locale(identifier: "ja-JP")) {
                    return ["state": "available", "modelName": "SystemLanguageModel.default", "reason": NSNull()]
                }
                reason = "System model does not support Japanese"
            case .unavailable(let unavailable):
                reason = "Apple Intelligence unavailable: \(unavailable). Check Apple Intelligence in Settings."
            @unknown default: reason = "Unknown system model availability"
            }
        }
        #endif
        return ["state": "unavailable", "modelName": NSNull(), "reason": reason]
    }

    @MainActor private func generate(_ prompt: String, instructions: String?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            // A fresh session prevents previous fields or accounts entering context.
            // Native context/guardrail failures propagate; input is never shortened.
            return try await session.respond(to: prompt).content
        }
        #endif
        throw NativeAudioFailure("unsupported", "On-device cleanup unavailable")
    }

    private func invalid(_ result: FlutterResult) {
        result(FlutterError(code: "invalidArguments", message: "Invalid voice cleanup request", details: nil))
    }
    private func emptyArguments(_ arguments: Any?) -> Bool {
        arguments == nil || (arguments as? [String: Any])?.isEmpty == true
    }
    private func cancelAll() { for active in work.values { active.task?.cancel() } }
    func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        detached = true
        if let background = background { NotificationCenter.default.removeObserver(background) }
        cancelAll()
    }
}
