import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'submission_adapters.dart';
import 'submission_background_resources.dart';
import 'submission_background_runner.dart';
import 'submission_configuration.dart';
import 'submission_json.dart' as j;
import 'submission_run_lifetime.dart';

/// Owned foreground wake facade; its optional channel is borrowed.
/// Closing this facade never cancels durable WorkManager work or configuration.
final class AndroidSubmissionBackgroundScheduler
    implements SubmissionWakeScheduler {
  /// Creates a wrapper without IO. Only Android supports native scheduling.
  AndroidSubmissionBackgroundScheduler({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('org.textus.flutter.core/submission');

  final MethodChannel _channel;
  Future<void>? _initialization;
  bool _closed = false;

  void _guard() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Android submission scheduling is unsupported here',
      );
    }
    if (_closed) throw StateError('Submission scheduler is closed');
  }

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, arguments);
      if (result != null) throw StateError('Invalid scheduler result');
    } catch (_) {
      throw SubmissionConfigurationException.safe('configurationUnavailable');
    }
  }

  /// Persists only Core's top-level callback handle before any wake. Concurrent
  /// calls join initialization; a failed initialization permits a later retry.
  Future<void> initialize() {
    _guard();
    final existing = _initialization;
    if (existing != null) return existing;
    final initialization = _register();
    _initialization = initialization;
    unawaited(
      initialization.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_initialization, initialization)) {
            _initialization = null;
          }
        },
      ),
    );
    return initialization;
  }

  Future<void> _register() async {
    try {
      final callback = ui.PluginUtilities.getCallbackHandle(
        submissionBackgroundCallback,
      );
      if (callback == null || callback.toRawHandle() <= 0) {
        throw StateError('Submission callback is unavailable');
      }
      await _invoke('initializeBackground', {
        'callbackHandle': callback.toRawHandle(),
      });
    } catch (_) {
      throw SubmissionConfigurationException.safe('configurationUnavailable');
    }
  }

  @override
  Future<void> requestRun() async {
    _guard();
    await initialize();
    _guard();
    await _invoke('scheduleBackground', {'delayMs': 0});
  }

  /// Retires only this facade. Already accepted scheduling remains durable.
  Future<void> close() async {
    _closed = true;
  }
}

/// Core-only headless root-isolate entry. Native owns the engine and total
/// timeout. Installs start/stop before ready; a matching stop immediately retires
/// adapter/queue ownership even while default resources are opening. Late errors
/// are consumed into a safe terminal value and all owned resources are closed.
@pragma('vm:entry-point')
void submissionBackgroundCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'org.textus.flutter.core/submission-background',
  );
  SubmissionRunLifetime? active;
  var started = false;
  channel.setMethodCallHandler((call) async {
    if (call.method == 'stop') {
      final args = j.exact(call.arguments, {'runId'});
      final id = j.token(j.string(args['runId']));
      if (active?.id == id) active!.retire();
      return null;
    }
    if (call.method != 'start') throw MissingPluginException();
    final args = j.exact(call.arguments, {'runId', 'networkAllowed'});
    final id = j.token(j.string(args['runId']));
    final allowed = j.boolean(args['networkAllowed']);
    if (started) {
      return SubmissionBackgroundRunResult(
        outcome: SubmissionBackgroundOutcome.cancelled,
      ).toJson();
    }
    started = true;
    final lifetime = SubmissionRunLifetime(id: id);
    active = lifetime;
    SubmissionBackgroundResources? resources;
    var result = SubmissionBackgroundRunResult(
      outcome: SubmissionBackgroundOutcome.failure,
      nextDelay: const Duration(seconds: 30),
    );
    try {
      if (!allowed) {
        result = SubmissionBackgroundRunResult(
          outcome: SubmissionBackgroundOutcome.offline,
        );
      } else {
        resources = await openDefaultAndroidSubmissionResources(
          lifetime: lifetime,
        );
        result = lifetime.isCurrent
            ? await SubmissionBackgroundRunner(
                resources: resources,
                lifetime: lifetime,
              ).run(networkAllowed: true)
            : SubmissionBackgroundRunResult(
                outcome: SubmissionBackgroundOutcome.cancelled,
              );
      }
    } catch (_) {
      result = SubmissionBackgroundRunResult(
        outcome: lifetime.isCurrent
            ? SubmissionBackgroundOutcome.failure
            : SubmissionBackgroundOutcome.cancelled,
        nextDelay: lifetime.isCurrent ? const Duration(seconds: 30) : null,
      );
    } finally {
      final wasCurrent = lifetime.isCurrent;
      lifetime.retire();
      try {
        await resources?.close();
      } catch (_) {
        // A cleanup failure cannot leak native details through the terminal value.
        if (wasCurrent) {
          result = SubmissionBackgroundRunResult(
            outcome: SubmissionBackgroundOutcome.failure,
            nextDelay: const Duration(seconds: 30),
          );
        }
      }
    }
    return result.toJson();
  });
  unawaited(
    channel.invokeMethod<void>('ready', <String, Object?>{}).catchError((
      Object _,
    ) {
      active?.retire();
    }),
  );
}
