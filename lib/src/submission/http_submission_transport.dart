import 'dart:convert';

import 'package:http/http.dart' as http;

import 'submission_adapters.dart';
import 'registered_material_submission.dart';
import 'registered_material_submission_codec.dart';
import 'submission_codec.dart';
import 'submission_connections.dart';
import 'submission_http.dart';
import 'submission_json.dart' as j;
import 'submission_record.dart';

/// Exact configured HTTPS packet transport with strict server acknowledgements.
///
/// Client/credentials are borrowed, never closed. Construction does no IO and
/// adds no scheduler/platform defaults. HTTP support and secure account grant
/// belong to supplied ports on each platform. A Drive receipt or generic HTTP
/// success never implies server acceptance.
final class HttpSubmissionTransport
    implements SubmissionTransport, RegisteredMaterialSubmissionTransport {
  /// Requires a total positive deadline at most 45s (including credentials).
  /// Cancellation completion/error immediately aborts active IO. A false or
  /// throwing run predicate retires the operation; sent remote effects may finish.
  HttpSubmissionTransport({
    required this.connection,
    required http.Client client,
    required SubmissionCredentialProvider credentials,
    this.isRunCurrent,
    this.cancellation,
    this.operationTimeout = const Duration(seconds: 45),
    // Public named parameters feed private borrowed fields.
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // Public named parameters feed private borrowed fields.
       // ignore: prefer_initializing_formals
       _credentials = credentials {
    validateHttpTimeout(operationTimeout);
  }

  /// Immutable endpoint/authorization definition, without credentials.
  @override
  final HttpSubmissionConnection connection;
  final http.Client _client;
  final SubmissionCredentialProvider _credentials;

  /// Borrowed predicate checked at entry, after awaits and before send.
  final bool Function()? isRunCurrent;

  /// Borrowed future whose completion/error retires active operations.
  final Future<void>? cancellation;

  /// Total monotonic deadline, including reading the bounded response body.
  final Duration operationTimeout;

  @override
  String get providerId => 'http';

  /// Sends the unchanged accepted packet schema, excluding the local document.
  /// Auth is requested only when explicitly configured. Requires JSON 200/201
  /// with a strict acknowledgement matching both request and subject. All safe
  /// failures use [SubmissionAdapterException]; there is no internal retry.
  /// Before potential send they report notSent; afterwards only explicit 401/403
  /// authorization refusal is rejected. Every other failed result stays unknown.
  @override
  Future<SubmissionAcknowledgement> submit(SubmissionPacket packet) => _submit(
    requestId: packet.request.id, subjectId: packet.request.subjectId,
    targetMatches: packet.request.transportConnectionId == connection.id,
    encode: () => SubmissionCodec.packetToJson(packet),
  );

  /// Sends only the typed v2 packet to its exact pinned Studio target.
  @override
  Future<SubmissionAcknowledgement> submitRegisteredMaterial(
    RegisteredMaterialSubmissionPacket packet,
  ) => _submit(
    requestId: packet.sourceRequest.id, subjectId: packet.sourceRequest.subjectId,
    targetMatches: sameRegisteredMaterialTarget(packet.target, connection),
    encode: () => RegisteredMaterialSubmissionCodec.packetToJson(packet),
  );

  Future<SubmissionAcknowledgement> _submit({
    required String requestId, required String subjectId,
    required bool targetMatches, required Map<String, Object?> Function() encode,
  }) async {
    final operation = SubmissionHttpOperation(
      stage: SubmissionFailureStage.transport,
      timeout: operationTimeout,
      isRunCurrent: isRunCurrent,
      cancellation: cancellation,
    );
    var potentiallyDispatched = false;
    int? responseStatus;
    try {
      operation.check();
      if (!targetMatches) {
        throw httpFailure(
          SubmissionFailureStage.configuration,
          'connectionMismatch',
        );
      }
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Idempotency-Key': requestId,
      };
      if (connection.requiresBearerToken) {
        final token = await operation.token(_credentials, connection.id);
        headers['Authorization'] = 'Bearer $token';
      }
      operation.check();
      final body = utf8.encode(
        jsonEncode(encode()),
      );
      operation.check();
      potentiallyDispatched = true;
      final response = await operation.send(
        _client,
        'POST',
        connection.endpoint,
        headers: headers,
        body: body,
      );
      responseStatus = response.statusCode;
      operation.check();
      if (response.statusCode != 200 && response.statusCode != 201) {
        if (response.statusCode >= 200 && response.statusCode <= 299) {
          throw httpFailure(
            SubmissionFailureStage.transport,
            'acknowledgementMissing',
          );
        }
        rejectHttpStatus(response, SubmissionFailureStage.transport);
      }
      SubmissionAcknowledgement acknowledgement;
      try {
        final contentType = response.headers['content-type'];
        if (contentType == null ||
            !RegExp(
              r'^application/json(?:\s*;\s*charset\s*=\s*(?:[A-Za-z0-9_-]+|"[A-Za-z0-9_-]+"))?\s*$',
              caseSensitive: false,
            ).hasMatch(contentType.trim())) {
          throw const FormatException('Invalid acknowledgement content type');
        }
        acknowledgement = SubmissionCodec.acknowledgementFromJson(
          j.object(response.json()),
        );
        if (acknowledgement.requestId != requestId ||
            acknowledgement.subjectId != subjectId) {
          throw const FormatException('Mismatched acknowledgement');
        }
      } catch (_) {
        throw httpFailure(
          SubmissionFailureStage.transport,
          'invalidAcknowledgement',
        );
      }
      operation.check();
      return acknowledgement;
    } on SubmissionAdapterException catch (error) {
      final refused =
          responseStatus == 401 && error.code == 'authRequired' ||
          responseStatus == 403 && error.code == 'permissionDenied';
      throw SubmissionAdapterException(
        stage: error.stage,
        code: error.code,
        message: error.message,
        retryable: error.retryable,
        transportFailureOutcome: !potentiallyDispatched
            ? SubmissionTransportFailureOutcome.notSent
            : refused
            ? SubmissionTransportFailureOutcome.rejected
            : SubmissionTransportFailureOutcome.unknown,
      );
    } finally {
      operation.dispose();
    }
  }
}
