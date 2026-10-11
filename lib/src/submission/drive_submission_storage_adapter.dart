import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'submission_adapters.dart';
import 'submission_connections.dart';
import 'submission_http.dart';
import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'submission_request.dart';

/// Google Drive binary storage through persisted, pre-generated file identities.
///
/// Client and credentials are borrowed and never closed. Construction performs
/// no IO. All platforms require a caller-supplied HTTP client and credential
/// provider; secure authorization and native scheduling are outside this API.
/// No originals are changed/deleted and no public sharing is performed. Verified
/// metadata binds identity/size; it does not prove byte integrity or server access.
final class DriveSubmissionStorageAdapter implements SubmissionStorageAdapter {
  /// Configures a total monotonic deadline (positive, at most 45 seconds).
  /// Optional cancellation immediately aborts current IO; a false or throwing
  /// current predicate safely cancels. An already dispatched effect may finish.
  DriveSubmissionStorageAdapter({
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

  /// Immutable explicit account/folder target used for every reservation.
  final DriveSubmissionConnection connection;
  final http.Client _client;
  final SubmissionCredentialProvider _credentials;

  /// Borrowed run predicate checked before IO and after every awaited stage.
  final bool Function()? isRunCurrent;

  /// Borrowed cancellation future; completion/error retires each active operation.
  final Future<void>? cancellation;

  /// Total operation deadline, including credential retrieval and response body.
  final Duration operationTimeout;

  @override
  String get providerId => 'googleDrive';

  static const _fields =
      'id,mimeType,size,parents,trashed,appProperties,createdTime';
  static final _generateIds = Uri.https(
    'www.googleapis.com',
    '/drive/v3/files/generateIds',
    {'count': '1', 'space': 'drive', 'type': 'files'},
  );
  static final _uploadUri = Uri.https(
    'www.googleapis.com',
    '/upload/drive/v3/files',
    {'uploadType': 'resumable', 'supportsAllDrives': 'true', 'fields': _fields},
  );

  SubmissionHttpOperation _operation() => SubmissionHttpOperation(
    stage: SubmissionFailureStage.storage,
    timeout: operationTimeout,
    isRunCurrent: isRunCurrent,
    cancellation: cancellation,
  );

  void _bind(SubmissionRequest request, SubmissionMaterial material) {
    if (request.storageConnectionId != connection.id) {
      throw httpFailure(
        SubmissionFailureStage.configuration,
        'connectionMismatch',
      );
    }
    if (!request.materials.any(
      (value) =>
          value.key == material.key && value.original == material.original,
    )) {
      throw httpFailure(
        SubmissionFailureStage.configuration,
        'materialMismatch',
      );
    }
    if (material.original.byteLength <= 0) {
      throw httpFailure(
        SubmissionFailureStage.configuration,
        'originalLengthMismatch',
      );
    }
  }

  Map<String, Object?> _data(
    SubmissionRequest request,
    SubmissionMaterial material,
    String fileId,
  ) => {
    'version': 1,
    'fileId': fileId,
    'connectionId': connection.id,
    'accountId': connection.accountId,
    'folderId': connection.folderId,
    'requestId': request.id,
    'materialKey': material.key,
    'originalId': material.original.id,
    'mediaType': material.original.mediaType,
    'byteLength': material.original.byteLength,
  };

  String _reservationId(
    SubmissionRequest request,
    SubmissionMaterial material,
    SubmissionStorageReservation reservation,
  ) {
    try {
      final data = j.exact(reservation.data, {
        'version',
        'fileId',
        'connectionId',
        'accountId',
        'folderId',
        'requestId',
        'materialKey',
        'originalId',
        'mediaType',
        'byteLength',
      });
      final fileId = j.string(data['fileId']);
      if (reservation.providerId != providerId ||
          reservation.key != material.key ||
          !_validDriveId(fileId) ||
          data['version'] is! int ||
          data['byteLength'] is! int ||
          !j.deepEquals(data, _data(request, material, fileId))) {
        throw const FormatException('Invalid reservation');
      }
      return fileId;
    } catch (_) {
      throw httpFailure(
        SubmissionFailureStage.configuration,
        'reservationMismatch',
      );
    }
  }

  /// Allocates one safe Drive file id without uploading bytes. Returns immutable
  /// reservation data for the queue to persist before any remote upload effect.
  /// Safe failures use [SubmissionAdapterException]; no token/session is retained.
  @override
  Future<SubmissionStorageReservation> prepare({
    required SubmissionRequest request,
    required SubmissionMaterial material,
  }) async {
    final operation = _operation();
    try {
      operation.check();
      _bind(request, material);
      final token = await operation.token(_credentials, connection.id);
      final response = await operation.send(
        _client,
        'GET',
        _generateIds,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      operation.check();
      if (response.statusCode != 200) {
        rejectHttpStatus(response, SubmissionFailureStage.storage, drive: true);
      }
      String fileId;
      try {
        final value = j.object(response.json());
        final ids = j.array(value['ids']);
        if (ids.length != 1 ||
            value['space'] != 'drive' ||
            value['kind'] != 'drive#generatedIds') {
          throw const FormatException('Invalid generated identity response');
        }
        fileId = j.string(ids.single);
        if (!_validDriveId(fileId)) {
          throw const FormatException('Invalid generated identity');
        }
      } catch (_) {
        throw httpFailure(SubmissionFailureStage.storage, 'invalidResponse');
      }
      operation.check();
      return SubmissionStorageReservation(
        key: material.key,
        providerId: providerId,
        data: _data(request, material, fileId),
      );
    } finally {
      operation.dispose();
    }
  }

  /// Snapshots bytes synchronously before the first await, validates all local
  /// bindings, then creates a transient resumable session and sends one unchanged
  /// binary PUT. A 409 is accepted only after fetching matching remote metadata.
  /// Partial 308/timeout safely require durable retry with the same reservation;
  /// timeout never rolls back a dispatched remote effect. No internal retry occurs.
  @override
  Future<SubmissionMaterialReceipt> upload({
    required SubmissionRequest request,
    required SubmissionMaterial material,
    required SubmissionStorageReservation reservation,
    required Uint8List bytes,
  }) async {
    final operation = _operation();
    final snapshot = Uint8List.fromList(bytes);
    try {
      operation.check();
      _bind(request, material);
      final fileId = _reservationId(request, material, reservation);
      if (snapshot.length != material.original.byteLength) {
        throw httpFailure(
          SubmissionFailureStage.configuration,
          'originalLengthMismatch',
        );
      }
      final token = await operation.token(_credentials, connection.id);
      final auth = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };
      final response = await operation.send(
        _client,
        'POST',
        _uploadUri,
        headers: {
          ...auth,
          'Content-Type': 'application/json',
          'X-Upload-Content-Length': snapshot.length.toString(),
          'X-Upload-Content-Type': material.original.mediaType,
        },
        body: utf8.encode(
          jsonEncode({
            'id': fileId,
            'name': '${request.id}_${material.key}',
            'mimeType': material.original.mediaType,
            'parents': [connection.folderId],
            'appProperties': _properties(request, material),
          }),
        ),
      );
      operation.check();
      if (response.statusCode == 409) {
        final verified = await _verifyExisting(
          operation,
          request,
          material,
          fileId,
          auth,
        );
        operation.check();
        return verified;
      }
      if (response.statusCode != 200) {
        rejectHttpStatus(response, SubmissionFailureStage.storage, drive: true);
      }
      final location = _location(response.headers['location']);
      operation.check();
      final uploaded = await operation.send(
        _client,
        'PUT',
        location,
        headers: {
          ...auth,
          'Content-Type': material.original.mediaType,
          'Content-Length': snapshot.length.toString(),
        },
        body: snapshot,
      );
      operation.check();
      if (uploaded.statusCode == 409) {
        final verified = await _verifyExisting(
          operation,
          request,
          material,
          fileId,
          auth,
        );
        operation.check();
        return verified;
      }
      if (uploaded.statusCode == 308) {
        throw httpFailure(
          SubmissionFailureStage.storage,
          'uploadIncomplete',
          retryable: true,
        );
      }
      if (uploaded.statusCode != 200 && uploaded.statusCode != 201) {
        rejectHttpStatus(uploaded, SubmissionFailureStage.storage, drive: true);
      }
      final receipt = _receipt(uploaded, request, material, fileId);
      operation.check();
      return receipt;
    } finally {
      operation.dispose();
    }
  }

  Future<SubmissionMaterialReceipt> _verifyExisting(
    SubmissionHttpOperation operation,
    SubmissionRequest request,
    SubmissionMaterial material,
    String fileId,
    Map<String, String> headers,
  ) async {
    final response = await operation.send(
      _client,
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
        'supportsAllDrives': 'true',
        'fields': _fields,
      }),
      headers: headers,
    );
    operation.check();
    if (response.statusCode == 404) {
      throw httpFailure(
        SubmissionFailureStage.storage,
        'verificationUnavailable',
        retryable: true,
      );
    }
    if (response.statusCode != 200) {
      rejectHttpStatus(response, SubmissionFailureStage.storage, drive: true);
    }
    final receipt = _receipt(response, request, material, fileId);
    operation.check();
    return receipt;
  }

  Uri _location(String? text) {
    final uri = text == null ? null : Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'www.googleapis.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != '/upload/drive/v3/files' ||
        uri.queryParametersAll['uploadType']?.length != 1 ||
        uri.queryParametersAll['uploadType']?.single != 'resumable' ||
        uri.queryParametersAll['upload_id']?.length != 1 ||
        (uri.queryParametersAll['upload_id']?.single.trim().isEmpty ?? true)) {
      throw httpFailure(
        SubmissionFailureStage.storage,
        'invalidUploadLocation',
      );
    }
    return uri;
  }

  SubmissionMaterialReceipt _receipt(
    SubmissionHttpResponse response,
    SubmissionRequest request,
    SubmissionMaterial material,
    String fileId,
  ) {
    Object? json;
    try {
      json = response.json();
    } catch (_) {
      throw httpFailure(SubmissionFailureStage.storage, 'invalidResponse');
    }
    late String id;
    late String mime;
    late String size;
    late List<Object?> parents;
    late bool trashed;
    late Map<String, Object?> properties;
    late String createdTime;
    late DateTime storedAt;
    try {
      final value = j.object(json);
      id = j.string(value['id']);
      mime = j.string(value['mimeType']);
      size = j.string(value['size']);
      parents = j.array(value['parents']);
      trashed = j.boolean(value['trashed']);
      properties = j.object(value['appProperties']);
      createdTime = j.string(value['createdTime']);
      if (!_validDriveId(id) ||
          mime.isEmpty ||
          !RegExp(r'^[1-9][0-9]*$').hasMatch(size) ||
          parents.any((parent) => parent is! String)) {
        throw const FormatException('Invalid remote metadata');
      }
      storedAt = _googleTime(createdTime);
    } catch (_) {
      throw httpFailure(
        SubmissionFailureStage.storage,
        'invalidRemoteMetadata',
      );
    }
    final expected = _properties(request, material);
    if (id != fileId ||
        mime != material.original.mediaType ||
        size != material.original.byteLength.toString() ||
        trashed ||
        !j.deepEquals(parents, [connection.folderId]) ||
        expected.entries.any((entry) => properties[entry.key] != entry.value)) {
      throw httpFailure(
        SubmissionFailureStage.storage,
        'remoteBindingMismatch',
      );
    }
    return SubmissionMaterialReceipt(
      key: material.key,
      providerId: providerId,
      remoteId: fileId,
      accessConnectionId: connection.id,
      storedAt: storedAt,
      metadata: {
        'version': 1,
        'connectionId': connection.id,
        'accountId': connection.accountId,
        'folderId': connection.folderId,
        'originalId': material.original.id,
        'mediaType': material.original.mediaType,
        'byteLength': material.original.byteLength,
        'createdTime': createdTime,
      },
    );
  }
}

bool _validDriveId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(value);

Map<String, String> _properties(
  SubmissionRequest request,
  SubmissionMaterial material,
) {
  final properties = <String, String>{};
  for (final entry in {
    'request': request.id,
    'material': material.key,
    'original': material.original.id,
  }.entries) {
    final value = entry.value;
    properties['${entry.key}0'] = value.substring(
      0,
      value.length > 64 ? 64 : value.length,
    );
    if (value.length > 64) properties['${entry.key}1'] = value.substring(64);
  }
  return properties;
}

DateTime _googleTime(String value) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})'
    r'(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (match == null) {
    throw const FormatException('Invalid remote creation time');
  }
  final fraction = match.group(2);
  final normalized = fraction == null
      ? value
      : '${match.group(1)}.${fraction.substring(0, fraction.length > 6 ? 6 : fraction.length)}${match.group(3)}';
  return j.time(normalized);
}
