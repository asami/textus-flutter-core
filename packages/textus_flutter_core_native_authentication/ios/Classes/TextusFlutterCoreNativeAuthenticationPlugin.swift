import Flutter
import Foundation

/// Inert registration; Security IO is lazy and always off main.
public final class TextusFlutterCoreNativeAuthenticationPlugin: NSObject, FlutterPlugin {
    private let lifetime = CredentialStoreLifetime()
    private let io = DispatchQueue(label: "org.textus.flutter.core.authentication.io")
    private let store = AuthenticationCredentialStore()
    private let channel: FlutterMethodChannel

    private init(channel: FlutterMethodChannel) { self.channel = channel; super.init() }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.textus.flutter.core/authentication_credentials",
                                           binaryMessenger: registrar.messenger())
        let plugin = TextusFlutterCoreNativeAuthenticationPlugin(channel: channel)
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }

    private static func error(_ failure: CredentialStoreFailure) -> FlutterError {
        FlutterError(code: failure.code, message: failure.message, details: nil)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Flutter delivers on main; keep retirement/replies on that same owner.
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.handle(call, result: result) }
            return
        }
        guard CredentialStorePolicy.keys(call.method) != nil else {
            result(FlutterMethodNotImplemented); return
        }
        do {
            guard lifetime.isLive else { throw CredentialStoreFailure.closed }
            var arguments = call.arguments
            if call.method == "replace", var map = arguments as? [String: Any] {
                guard let value = map["value"] as? FlutterStandardTypedData,
                      value.elementSize == 1,
                      (1...CredentialStorePolicy.maximumValue).contains(value.data.count) else {
                    throw CredentialStoreFailure.invalidArguments
                }
                map["value"] = Data([UInt8](value.data))
                arguments = map
            }
            let request = try CredentialStorePolicy.call(call.method, arguments)
            if request.method == "close" {
                lifetime.retire(request.handleId)
                io.async {
                    DispatchQueue.main.async {
                        if self.lifetime.isLive { result(nil) }
                    }
                }
                return
            }
            let operation = try lifetime.accept(request.handleId)
            io.async {
                let outcome: Result<Any?, CredentialStoreFailure>
                do {
                    guard self.lifetime.current(operation) else { throw CredentialStoreFailure.closed }
                    let value = try self.store.execute(request) { try self.lifetime.issue(operation) }
                    outcome = .success(value)
                } catch let failure as CredentialStoreFailure { outcome = .failure(failure) }
                catch { outcome = .failure(.unavailable) }
                DispatchQueue.main.async {
                    guard self.lifetime.complete(operation) else { return }
                    guard self.lifetime.current(operation) else { result(Self.error(.closed)); return }
                    switch outcome {
                    case .failure(let failure): result(Self.error(failure))
                    case .success(let value):
                        if let entry = value as? AuthenticationCredentialEntry {
                            result(["revision": entry.revision, "value": FlutterStandardTypedData(bytes: entry.value)])
                        } else { result(value) }
                    }
                }
            }
        } catch let failure as CredentialStoreFailure { result(Self.error(failure)) }
        catch { result(Self.error(.unavailable)) }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        let retire = {
            self.lifetime.detach()
            self.channel.setMethodCallHandler(nil)
            // The serial queue drains retained closures, each releasing its local
            // snapshots and Security calls. No IO is cancelled or joined on main.
            self.io.async {}
        }
        if Thread.isMainThread { retire() }
        else { DispatchQueue.main.sync(execute: retire) }
    }
}
