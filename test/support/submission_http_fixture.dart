import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/textus_flutter_core.dart';

/// Controlled HTTP evidence only; never connects to Drive or a real server.
final class CapturedSubmissionHttpRequest {
  CapturedSubmissionHttpRequest(http.AbortableRequest request)
    : method = request.method,
      uri = request.url,
      headers = {
        for (final entry in request.headers.entries)
          entry.key.toLowerCase(): entry.value,
      },
      bytes = Uint8List.fromList(request.bodyBytes),
      followsRedirects = request.followRedirects,
      abort = request.abortTrigger!;
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List bytes;
  final bool followsRedirects;
  final Future<void> abort;

  Map<String, Object?> get json =>
      Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
}

/// Test owns this client and closes it; adapters only borrow it.
final class ControlledSubmissionHttpClient extends http.BaseClient {
  final List<CapturedSubmissionHttpRequest> requests = [];
  FutureOr<http.StreamedResponse> Function(CapturedSubmissionHttpRequest)?
  handler;
  bool closed = false;

  void respond(http.StreamedResponse response) {
    // Given an explicit controlled HTTP response prepared by the scenario.
    final supplied = response;
    // When the public adapter sends its actual request to this borrowed client.
    handler = (_) {
      // Given this request has been captured by send before the callback.
      final selected = supplied;
      // When the controlled response is selected without a network operation.
      final result = selected;
      // Then the adapter observes this actual stream/status under its deadline.
      return result;
    };
    // Then each scenario asserts the resulting public success/failure and IO count.
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Given a real abortable request built through the public adapter operation.
    final captured = CapturedSubmissionHttpRequest(
      request as http.AbortableRequest,
    );
    requests.add(captured);
    // When the controlled callback handles that captured HTTP request.
    final response = Future<http.StreamedResponse>.sync(() {
      // Given this request's explicit callback and no real network connection.
      final callback = handler;
      // When the test has configured a response, execute its actual behavior.
      if (callback == null) throw StateError('No controlled HTTP response');
      final response = callback(captured);
      // Then the adapter observes precisely this controlled stream/status.
      return response;
    });
    // Then scenarios observe method, headers, bytes and abort via requests.
    return response;
  }

  @override
  void close() {
    // Given the test-owned client whose close is observable by borrowing tests.
    final owned = this;
    // When the owning test closes it, retain an idempotent lifetime marker.
    owned.closed = true;
    // Then a repeated owner close has no additional behavior.
    // The marker is asserted by teardown and client-borrowing scenarios.
  }
}

/// Ephemeral controlled credentials, with observable exact connection selection.
final class ControlledSubmissionCredentials
    implements SubmissionCredentialProvider {
  static const secret = 'sensitive.token-DO_NOT_PERSIST';
  final List<String> calls = [];
  FutureOr<String?> Function(String)? handler;

  @override
  Future<String?> bearerToken(String connectionId) {
    // Given the adapter's explicitly bound configuration identity.
    calls.add(connectionId);
    // When a test controls a held grant, malformed token or provider failure.
    final callback = handler;
    final result = Future<String?>.sync(
      () => callback == null ? secret : callback(connectionId),
    );
    // Then the credential response remains a separate ephemeral borrowed port.
    return result;
  }
}

final class SubmissionHttpFixture {
  final client = ControlledSubmissionHttpClient();
  final credentials = ControlledSubmissionCredentials();
  final driveConnection = DriveSubmissionConnection(
    id: 'drive',
    accountId: 'account@example.test',
    folderId: 'Folder_1',
  );
  final httpConnection = HttpSubmissionConnection(
    id: 'server',
    endpoint: Uri.parse('https://example.test:8443/v1/submit%2Fmaterial'),
  );
  static const createdTime = '2026-10-10T10:00:00.123456789+09:00';
  static const uploadLocation =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=private-session&opaque=a%2Fb';

  DriveSubmissionStorageAdapter drive({
    bool Function()? isRunCurrent,
    Future<void>? cancellation,
    Duration operationTimeout = const Duration(seconds: 45),
  }) {
    // Given explicit test-owned ports and a frozen configured account/folder.
    final configured = driveConnection;
    // When the public adapter is constructed with the selected lifetime controls.
    final adapter = DriveSubmissionStorageAdapter(
      connection: configured,
      client: client,
      credentials: credentials,
      isRunCurrent: isRunCurrent,
      cancellation: cancellation,
      operationTimeout: operationTimeout,
    );
    // Then scenarios assert its public behavior without implicit IO/default auth.
    return adapter;
  }

  HttpSubmissionTransport transport({
    bool anonymous = false,
    bool Function()? isRunCurrent,
    Future<void>? cancellation,
    Duration operationTimeout = const Duration(seconds: 45),
  }) {
    // Given an explicit test choice of authenticated or anonymous configuration.
    final configured = anonymous
        ? HttpSubmissionConnection(
            id: httpConnection.id,
            endpoint: httpConnection.endpoint,
            requiresBearerToken: false,
          )
        : httpConnection;
    // When the public transport borrows the configured endpoint and test ports.
    final transport = HttpSubmissionTransport(
      connection: configured,
      client: client,
      credentials: credentials,
      isRunCurrent: isRunCurrent,
      cancellation: cancellation,
      operationTimeout: operationTimeout,
    );
    // Then scenarios observe exact endpoint/auth behavior through public submit.
    return transport;
  }

  SubmissionRequest request({
    int length = 6,
    String mediaType = 'image/jpeg',
    String id = 'commit1',
    String key = 'photo',
    String originalId = 'original1',
    String storageId = 'drive',
    String transportId = 'server',
    bool withMaterial = true,
  }) {
    // Given a complete immutable original reference and opaque consumer data.
    final materials = withMaterial
        ? [
            SubmissionMaterial(
              key: key,
              original: CaptureMaterialReference(
                id: originalId,
                mediaType: mediaType,
                byteLength: length,
                capturedAt: DateTime.utc(2026, 10, 10),
                extensions: {
                  'capture': [
                    null,
                    {'unchanged': true},
                  ],
                },
              ),
              provenance: {
                'namespace/photo': {'confidence': 0.5, 'manual': false},
              },
            ),
          ]
        : <SubmissionMaterial>[];
    // When a public request snapshots the document/payload/opaque context.
    final request = SubmissionRequest(
      id: id,
      kind: 'bookMaterial',
      subjectId: 'subject1',
      createdAt: DateTime.utc(2026, 10, 10),
      document: {'localOnly': '/private/editor/draft'},
      payload: {'title': '  title\n ', 'transcript': '  手入力\n原文  '},
      materials: materials,
      storageConnectionId: withMaterial ? storageId : null,
      transportConnectionId: transportId,
      extensions: {
        'arm': {
          'opaque/namespace': [null, true, 'arm/1'],
        },
        'execution': {'locale': 'ja', 'context': '  opaque\n '},
      },
    );
    // Then scenarios exercise the actual public binding and wire codec values.
    return request;
  }

  SubmissionStorageReservation reservation(
    SubmissionRequest request, {
    String fileId = 'File_1',
  }) {
    // Given the exact public Drive reservation contract for this material.
    final material = request.materials.single;
    // When the durable value is serialized and rehydrated through the A codec.
    final reservation = SubmissionCodec.reservationFromJson({
      'key': material.key,
      'providerId': 'googleDrive',
      'data': {
        'version': 1,
        'fileId': fileId,
        'connectionId': driveConnection.id,
        'accountId': driveConnection.accountId,
        'folderId': driveConnection.folderId,
        'requestId': request.id,
        'materialKey': material.key,
        'originalId': material.original.id,
        'mediaType': material.original.mediaType,
        'byteLength': material.original.byteLength,
      },
    });
    // Then direct upload calls receive the same durable identity after restart.
    return reservation;
  }

  Map<String, Object?> file(
    SubmissionRequest request,
    SubmissionMaterial material,
    String fileId,
  ) {
    // Given safe request/material/original identities, including long tokens.
    final properties = <String, String>{};
    for (final entry in {
      'request': request.id,
      'material': material.key,
      'original': material.original.id,
    }.entries) {
      // Given an ASCII identity whose split keeps each Google property bounded.
      final length = entry.value.length;
      // When the controlled remote stores exact first/suffix identity pieces.
      properties['${entry.key}0'] = entry.value.substring(
        0,
        length > 64 ? 64 : length,
      );
      if (length > 64) properties['${entry.key}1'] = entry.value.substring(64);
      // Then adapter verification can compare actual remote binding values.
    }
    // When Google returns the allowlisted file metadata plus an unrelated key.
    final value = <String, Object?>{
      'id': fileId,
      'mimeType': material.original.mediaType,
      'size': material.original.byteLength.toString(),
      'parents': [driveConnection.folderId],
      'trashed': false,
      'appProperties': {...properties, 'unrelated': 'allowed'},
      'createdTime': createdTime,
      'ignoredRemoteField': 'private-remote-marker',
    };
    // Then tests can alter one concrete binding/type without claiming integrity.
    return value;
  }

  Map<String, Object?> acknowledgement(SubmissionRequest request) {
    // Given a server acknowledgement independent of storage success.
    final acceptance = SubmissionAcknowledgement(
      requestId: request.id,
      subjectId: request.subjectId,
      serverId: 'fake-server/${request.id}',
      receivedAt: request.createdAt,
      extensions: {
        'accepted': [request.id, null],
      },
    );
    // When the actual A codec serializes explicit server acceptance.
    final value = SubmissionCodec.acknowledgementToJson(acceptance);
    // Then transport tests can require the strict matching acknowledgement.
    return value;
  }

  SubmissionPacket packet(SubmissionRequest request) {
    // Given complete controlled receipts for every original in this request.
    final receipts = <String, SubmissionMaterialReceipt>{
      for (final material in request.materials)
        material.key: SubmissionMaterialReceipt(
          key: material.key,
          providerId: 'googleDrive',
          remoteId: 'File_${material.key}',
          accessConnectionId: 'drive',
          storedAt: request.createdAt,
          metadata: {'originalId': material.original.id},
        ),
    };
    // When a complete public packet freezes those receipts.
    final packet = SubmissionPacket(request: request, receipts: receipts);
    // Then the real transport codec, not a fake transport, encodes it.
    return packet;
  }

  void dispose() {
    // Given test-owned client resources after all held operations are released.
    final owned = client;
    // When the fixture is torn down, only its owner closes the client.
    owned.close();
    // Then borrowers have no lifetime authority over this close.
    expect(owned.closed, isTrue);
  }
}

http.StreamedResponse submissionJsonResponse(
  Object? value, {
  int status = 200,
  Map<String, String> headers = const {},
}) {
  // Given a controlled response body, never a real Drive/server observation.
  final bytes = utf8.encode(jsonEncode(value));
  // When the http streamed response emits the JSON bytes.
  final response = http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );
  // Then public adapters parse that actual response stream under their deadline.
  return response;
}

http.StreamedResponse submissionEmptyResponse(
  int status, {
  Map<String, String> headers = const {},
}) {
  // Given a selected controlled status with no acknowledgement body.
  final stream = Stream<List<int>>.value(const []);
  // When the HTTP port returns this actual empty stream.
  final response = http.StreamedResponse(stream, status, headers: headers);
  // Then a bare success/status can never manufacture an acceptance.
  return response;
}

Matcher submissionFailure(
  String code, {
  SubmissionFailureStage stage = SubmissionFailureStage.storage,
  bool retryable = false,
}) => isA<SubmissionAdapterException>()
    .having((value) => value.code, 'safe code', code)
    .having((value) => value.stage, 'stage', stage)
    .having((value) => value.retryable, 'retryable', retryable)
    .having(
      (value) => '${value.message}$value',
      'no credential/raw marker',
      isNot(contains(ControlledSubmissionCredentials.secret)),
    );

Future<void> submissionEntered(Completer<void> entered) {
  // Given a barrier signalled only by actual entry/abort/stream cancellation.
  final signal = entered.future;
  // When a scenario awaits entry under an explicit bounded test allowance.
  final observed = signal.timeout(const Duration(seconds: 2));
  // Then missing entry fails visibly and never leaves the test waiting forever.
  return observed;
}
