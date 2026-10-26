import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'submission_adapters.dart';
import 'submission_connections.dart';
import 'submission_http.dart';
import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'tkl_material_delivery.dart';
import 'tkl_material_delivery_codec.dart';

/// Safe delivery failure. Unknown mutation outcomes require TKL reconciliation.
final class TklMaterialDeliveryHttpException implements Exception {
  const TklMaterialDeliveryHttpException._({
    required this.code,
    required this.retryable,
    required this.outcomeUnknown,
  });

  final String code;
  final bool retryable;
  final bool outcomeUnknown;

  @override
  String toString() => 'TklMaterialDeliveryHttpException($code)';
}

/// Native TKL operation client over one explicitly bootstrapped HTTPS service.
///
/// [connection.endpoint] is the deployed MaterialDelivery service root ending in
/// `/`. Configuration selects the service, never a Google destination. Production
/// discovery always calls TKL. Tests may explicitly supply a controlled service.
/// Clients/credentials are borrowed; construction starts no IO, consent or retry.
final class TklMaterialDeliveryHttpClient
    implements TklStreamingDirectMaterialDeliveryClient {
  TklMaterialDeliveryHttpClient({
    required this.connection,
    required http.Client client,
    required SubmissionCredentialProvider credentials,
    this.operationTimeout = const Duration(seconds: 45),
    this.isRunCurrent,
    this.cancellation,
    // Preserve public borrowed-port parameter names.
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _credentials = credentials {
    validateHttpTimeout(operationTimeout);
    if (!connection.endpoint.path.endsWith('/') ||
        !connection.requiresBearerToken) {
      throw ArgumentError('TKL requires an authenticated HTTPS service root.');
    }
  }

  final HttpSubmissionConnection connection;
  final http.Client _client;
  final SubmissionCredentialProvider _credentials;
  final Duration operationTimeout;
  final bool Function()? isRunCurrent;
  final Future<void>? cancellation;

  @override
  Future<TklMaterialDeliveryDestination> getDestination() => _call(
    'getDestination',
    decode: TklMaterialDeliveryCodec.destinationFromJson,
  );

  @override
  Future<TklMaterialDeliverySnapshot> prepare(
    TklMaterialDeliveryRequest request,
  ) => _call(
    'prepare',
    body: {
      'requestId': request.requestId,
      'contribution': request.contribution,
    },
    decode: (value) {
      final snapshot = TklMaterialDeliveryCodec.snapshotFromJson(value);
      if (snapshot.requestId != request.requestId) _invalid();
      return snapshot;
    },
  );

  @override
  Future<TklMaterialDeliverySnapshot?> findForRequest(String requestId) =>
      _call(
        'findForRequest',
        query: {'requestId': j.token(requestId)},
        decode: (value) {
          final fields = _fields(value, {'found'}, {'delivery'});
          if (fields['found'] is! bool) _invalid();
          if (fields['found'] == false) {
            if (fields['delivery'] != null) _invalid();
            return null;
          }
          final snapshot = TklMaterialDeliveryCodec.snapshotFromJson(
            fields['delivery'],
          );
          if (snapshot.requestId != requestId) _invalid();
          return snapshot;
        },
      );

  @override
  Future<TklMaterialDeliverySnapshot> get(String deliveryRef) => _call(
    'get',
    query: {'deliveryRef': _reference(deliveryRef)},
    decode: (value) => _selectedSnapshot(value, deliveryRef),
  );

  @override
  Future<TklMaterialDeliverySnapshot> uploadOriginal({
    required String deliveryRef,
    required String resourceId,
    required String mediaType,
    required Uint8List content,
  }) {
    final reference = _reference(deliveryRef);
    final resource = j.token(resourceId);
    // Validate MIME and snapshot bytes before any await or credential lookup.
    TklOriginalTransferProgress(
      resourceId: resource,
      mediaType: mediaType,
      byteLength: content.length,
      state: TklOriginalTransferState.pending,
    );
    final bytes = Uint8List.fromList(content);
    return _call(
      'uploadOriginal',
      multipart: (uri) => http.MultipartRequest('POST', uri)
        ..fields.addAll({'deliveryRef': reference, 'resourceId': resource})
        ..files.add(
          http.MultipartFile.fromBytes(
            'content',
            bytes,
            filename: 'original',
            contentType: MediaType.parse(mediaType),
          ),
        ),
      decode: (value) {
        final snapshot = _selectedSnapshot(value, reference);
        final matches = snapshot.resources.where(
          (item) => item.resourceId == resource,
        );
        if (matches.length != 1 ||
            matches.single.mediaType != mediaType ||
            matches.single.byteLength != bytes.length) {
          _invalid();
        }
        return snapshot;
      },
    );
  }

  @override
  Future<TklMaterialDeliverySnapshot> finalize(String deliveryRef) => _call(
    'finalize',
    body: {'deliveryRef': _reference(deliveryRef)},
    decode: (value) => _selectedSnapshot(value, deliveryRef),
  );

  @override
  Future<TklDirectTransferPreparation> prepareOriginalTransfer({
    required String deliveryRef,
    required String resourceId,
  }) => _call(
    'prepareOriginalTransfer',
    body: {
      'deliveryRef': _reference(deliveryRef),
      'resourceId': j.token(resourceId),
    },
    decode: (value) {
      final fields = _fields(value, {'delivery'}, {'instruction'});
      final snapshot = _selectedSnapshot(fields['delivery'], deliveryRef);
      final raw = fields['instruction'];
      TklDirectTransferInstruction? instruction;
      if (raw != null) {
        final item = TklMaterialDeliveryCodec.responseFields(raw, {
          'transfer_ref',
          'resource_id',
          'method',
          'upload_session_uri',
          'media_type',
          'byte_length',
          'next_offset',
        });
        if (item['method'] != 'googleDriveResumable' ||
            item['resource_id'] != resourceId ||
            item['byte_length'] is! int ||
            item['next_offset'] is! int) {
          _invalid();
        }
        instruction = TklDirectTransferInstruction(
          transferRef: j.string(item['transfer_ref']),
          resourceId: j.string(item['resource_id']),
          uploadUri: Uri.parse(j.string(item['upload_session_uri'])),
          mediaType: j.string(item['media_type']),
          byteLength: item['byte_length']! as int,
          nextOffset: item['next_offset']! as int,
        );
      }
      return TklDirectTransferPreparation(
        delivery: snapshot,
        instruction: instruction,
      );
    },
  );

  @override
  Future<TklMaterialDeliverySnapshot> confirmOriginalTransfer({
    required String deliveryRef,
    required TklDirectUploadReceipt receipt,
  }) => _call(
    'confirmOriginalTransfer',
    body: {
      'deliveryRef': _reference(deliveryRef),
      'resourceId': receipt.resourceId,
      'transferRef': receipt.transferRef,
      'result': {'outcome': 'uploaded', 'byteLength': receipt.byteLength},
    },
    decode: (value) => _selectedSnapshot(value, deliveryRef),
  );

  @override
  Future<TklDirectUploadReceipt> uploadDirect({
    required TklDirectTransferInstruction instruction,
    required Uint8List content,
  }) async {
    if (instruction.byteLength != content.length) {
      throw ArgumentError(
        'Direct upload original does not match its declaration.',
      );
    }
    final lifetime = SubmissionHttpOperation(
      stage: SubmissionFailureStage.storage,
      timeout: operationTimeout,
      isRunCurrent: isRunCurrent,
      cancellation: cancellation,
    );
    var dispatched = false;
    int? status;
    try {
      lifetime.check();
      final offset = instruction.nextOffset;
      final total = instruction.byteLength;
      dispatched = true;
      // The provider session is the narrow upload authority. Never attach the
      // TKL application bearer or retrieve a server Google credential here.
      final response = await lifetime.send(
        _client,
        'PUT',
        instruction.uploadUri,
        headers: {
          'Content-Type': instruction.mediaType,
          'Accept': 'application/json',
          'Content-Range': offset == total
              ? 'bytes */$total'
              : 'bytes $offset-${total - 1}/$total',
        },
        body: Uint8List.sublistView(content, offset),
      );
      status = response.statusCode;
      if (status != 200 && status != 201) {
        rejectHttpStatus(response, SubmissionFailureStage.storage);
      }
      lifetime.check();
      return TklDirectUploadReceipt(
        resourceId: instruction.resourceId,
        transferRef: instruction.transferRef,
        byteLength: total,
      );
    } catch (error) {
      final known = error is SubmissionAdapterException ? error : null;
      throw TklMaterialDeliveryHttpException._(
        code: known?.code ?? 'invalidResponse',
        retryable: known?.retryable ?? true,
        outcomeUnknown: dispatched && status != 401 && status != 403,
      );
    } finally {
      lifetime.dispose();
    }
  }

  @override
  Future<TklDirectUploadReceipt> uploadDirectStream({
    required TklDirectTransferInstruction instruction,
    required int totalLength,
    required TklOriginalRangeReader openRange,
  }) async {
    if (totalLength != instruction.byteLength) {
      throw ArgumentError('Direct original length does not match.');
    }
    final lifetime = SubmissionHttpOperation(
      stage: SubmissionFailureStage.storage, timeout: operationTimeout,
      isRunCurrent: isRunCurrent, cancellation: cancellation,
    );
    var dispatched = false;
    int? status;
    StreamIterator<List<int>>? reader;
    try {
      var offset = instruction.nextOffset;
      while (true) {
        lifetime.check();
        final end = offset + 262144 < totalLength
            ? offset + 262144 : totalLength;
        final bytes = BytesBuilder(copy: false);
        if (offset < end) {
          reader = StreamIterator<List<int>>(openRange(offset, end));
          while (await lifetime.wait(reader.moveNext())) {
            lifetime.check();
            final chunk = reader.current;
            if (chunk.length > 65536 || bytes.length + chunk.length > end - offset) {
              throw httpFailure(SubmissionFailureStage.storage, 'originalLengthMismatch');
            }
            bytes.add(chunk);
          }
          await reader.cancel();
          reader = null;
        }
        if (bytes.length != end - offset) {
          throw httpFailure(SubmissionFailureStage.storage, 'originalLengthMismatch');
        }
        lifetime.check();
        dispatched = true;
        // Session authority only: no credential lookup or application bearer.
        final response = await lifetime.send(
          _client, 'PUT', instruction.uploadUri,
          headers: {
            'Content-Type': instruction.mediaType,
            'Accept': 'application/json',
            'Content-Range': offset == totalLength
                ? 'bytes */$totalLength' : 'bytes $offset-${end - 1}/$totalLength',
          },
          body: bytes.takeBytes(),
        );
        status = response.statusCode;
        lifetime.check();
        if (status == 200 || status == 201) {
          if (end != totalLength) {
            throw httpFailure(SubmissionFailureStage.storage, 'uploadIncomplete');
          }
          return TklDirectUploadReceipt(
            resourceId: instruction.resourceId, transferRef: instruction.transferRef,
            byteLength: totalLength,
          );
        }
        if (status != 308) rejectHttpStatus(response, SubmissionFailureStage.storage);
        final range = response.headers['range'];
        final match = range == null ? null : RegExp(r'^bytes=0-([0-9]+)$').firstMatch(range);
        final last = match == null ? null : int.tryParse(match[1]!);
        final acknowledged = last == null ? null : last + 1;
        if (acknowledged == null || acknowledged <= offset ||
            acknowledged > end || acknowledged > totalLength) {
          throw httpFailure(SubmissionFailureStage.storage, 'uploadIncomplete');
        }
        offset = acknowledged;
      }
    } catch (error) {
      final known = error is SubmissionAdapterException ? error : null;
      throw TklMaterialDeliveryHttpException._(
        code: known?.code ?? 'invalidResponse',
        retryable: known?.retryable ?? true,
        outcomeUnknown: dispatched && status != 401 && status != 403,
      );
    } finally {
      lifetime.dispose();
      await reader?.cancel();
    }
  }

  Future<T> _call<T>(
    String operation, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    http.MultipartRequest Function(Uri)? multipart,
    required T Function(Object?) decode,
  }) async {
    final lifetime = SubmissionHttpOperation(
      stage: SubmissionFailureStage.transport,
      timeout: operationTimeout,
      isRunCurrent: isRunCurrent,
      cancellation: cancellation,
    );
    final mutating = body != null || multipart != null;
    var dispatched = false;
    int? status;
    try {
      lifetime.check();
      final uri = connection.endpoint
          .resolve(operation)
          .replace(queryParameters: query);
      final headers = <String, String>{'Accept': 'application/json'};
      final token = await lifetime.token(_credentials, connection.id);
      headers['Authorization'] = 'Bearer $token';
      List<int>? bytes;
      if (multipart != null) {
        final request = multipart(uri);
        bytes = await lifetime.wait(request.finalize().toBytes());
        headers.addAll(request.headers);
      } else if (body != null) {
        headers['Content-Type'] = 'application/json';
        bytes = utf8.encode(jsonEncode(body));
      }
      lifetime.check();
      dispatched = true;
      final response = await lifetime.send(
        _client,
        mutating ? 'POST' : 'GET',
        uri,
        headers: headers,
        body: bytes,
      );
      status = response.statusCode;
      if (status != 200 && status != 201) {
        rejectHttpStatus(response, SubmissionFailureStage.transport);
      }
      final type = response.headers['content-type'];
      if (type == null ||
          !RegExp(
            r'^application/json(?:\s*;\s*charset\s*=\s*(?:[A-Za-z0-9_-]+|"[A-Za-z0-9_-]+"))?\s*$',
            caseSensitive: false,
          ).hasMatch(type.trim())) {
        _invalid();
      }
      final result = decode(response.json());
      lifetime.check();
      return result;
    } catch (error) {
      final known = error is SubmissionAdapterException ? error : null;
      throw TklMaterialDeliveryHttpException._(
        code: known?.code ?? 'invalidResponse',
        retryable: known?.retryable ?? false,
        outcomeUnknown:
            mutating && dispatched && status != 401 && status != 403,
      );
    } finally {
      lifetime.dispose();
    }
  }
}

TklMaterialDeliverySnapshot _selectedSnapshot(Object? value, String reference) {
  final snapshot = TklMaterialDeliveryCodec.snapshotFromJson(value);
  if (snapshot.deliveryRef != reference) _invalid();
  return snapshot;
}

Map<String, Object?> _fields(
  Object? value,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  final fields = j.object(value);
  if (!required.every(fields.containsKey) ||
      !fields.keys.every(
        (key) => required.contains(key) || optional.contains(key),
      )) {
    _invalid();
  }
  return fields;
}

String _reference(String value) {
  if (value.length > 2048 ||
      value.trim().isEmpty ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'))) {
    throw ArgumentError('Invalid TKL delivery reference.');
  }
  return value;
}

Never _invalid() => throw const FormatException('Invalid TKL response.');
