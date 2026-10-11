import '../capture/capture_material.dart';
import 'submission_adapters.dart';
import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'submission_request.dart';

/// Exact request/packet v1 and record v2 schemas, with detached output JSON.
/// Exact legacy record v1 remains readable without rewriting persistence.
/// Decoders throw [FormatException] for unknown/missing keys, invalid scalar
/// types/calendar times and inconsistent values; they never repair persistence.
abstract final class SubmissionCodec {
  /// Encodes the complete immutable request, including its local document.
  static Map<String, Object?> requestToJson(SubmissionRequest value) => {
    'version': 1,
    'id': value.id,
    'kind': value.kind,
    'subjectId': value.subjectId,
    'createdAt': value.createdAt.toIso8601String(),
    'document': j.detach(value.document),
    'payload': j.detach(value.payload),
    'materials': value.materials.map(materialToJson).toList(),
    'transportConnectionId': value.transportConnectionId,
    'storageConnectionId': value.storageConnectionId,
    'extensions': j.detach(value.extensions),
  };

  /// Decodes exactly version 1 and snapshots all nested JSON.
  static SubmissionRequest requestFromJson(Map<String, Object?> json) =>
      j.decode(() {
        final v = j.exact(json, {
          'version',
          'id',
          'kind',
          'subjectId',
          'createdAt',
          'document',
          'payload',
          'materials',
          'transportConnectionId',
          'storageConnectionId',
          'extensions',
        });
        j.version(v);
        return SubmissionRequest(
          id: j.string(v['id']),
          kind: j.string(v['kind']),
          subjectId: j.string(v['subjectId']),
          createdAt: j.time(v['createdAt']),
          document: j.object(v['document']),
          payload: j.object(v['payload']),
          materials: j
              .array(v['materials'])
              .map((m) => materialFromJson(j.object(m)))
              .toList(),
          transportConnectionId: j.string(v['transportConnectionId']),
          storageConnectionId: j.nullableString(v['storageConnectionId']),
          extensions: j.object(v['extensions']),
        );
      });

  /// Encodes all nullable keys, complete history and checkpoints of a record.
  static Map<String, Object?> recordToJson(SubmissionRecord value) => {
    'version': 2,
    'request': requestToJson(value.request),
    'state': value.state.name,
    'claimCount': value.claimCount,
    'updatedAt': value.updatedAt.toIso8601String(),
    'leaseToken': value.leaseToken,
    'leaseExpiresAt': value.leaseExpiresAt?.toIso8601String(),
    'nextAttemptAt': value.nextAttemptAt?.toIso8601String(),
    'reservations': {
      for (final e in value.reservations.entries)
        e.key: reservationToJson(e.value),
    },
    'receipts': {
      for (final e in value.receipts.entries) e.key: receiptToJson(e.value),
    },
    'failureHistory': value.failureHistory.map(failureToJson).toList(),
    'acknowledgement': value.acknowledgement == null
        ? null
        : acknowledgementToJson(value.acknowledgement!),
    'transportCheckpoint': value.transportCheckpoint == null
        ? null
        : {
            'claimCount': value.transportCheckpoint!.claimCount,
            'startedAt': value.transportCheckpoint!.startedAt
                ?.toIso8601String(),
            'isLegacyUnknown': value.transportCheckpoint!.isLegacyUnknown,
          },
  };

  /// Decodes the complete record; malformed state relationships are errors.
  static SubmissionRecord recordFromJson(Map<String, Object?> json) =>
      j.decode(() {
        final version = j.integer(json['version']);
        if (version != 1 && version != 2) {
          throw const FormatException('Unsupported submission record version');
        }
        final v = j.exact(json, {
          'version',
          'request',
          'state',
          'claimCount',
          'updatedAt',
          'leaseToken',
          'leaseExpiresAt',
          'nextAttemptAt',
          'reservations',
          'receipts',
          'failureHistory',
          'acknowledgement',
          if (version == 2) 'transportCheckpoint',
        });
        final request = requestFromJson(j.object(v['request']));
        final state = j.enumeration(v['state'], SubmissionState.values);
        final claimCount = j.integer(v['claimCount']);
        final receipts = {
          for (final e in j.object(v['receipts']).entries)
            e.key: receiptFromJson(j.object(e.value)),
        };
        SubmissionTransportCheckpoint? checkpoint;
        if (version == 1) {
          if (state != SubmissionState.submitted &&
              claimCount > 0 &&
              receipts.length == request.materials.length) {
            checkpoint = const SubmissionTransportCheckpoint.legacyUnknown();
          }
        } else if (v['transportCheckpoint'] != null) {
          final c = j.exact(v['transportCheckpoint'], {
            'claimCount',
            'startedAt',
            'isLegacyUnknown',
          });
          if (j.boolean(c['isLegacyUnknown'])) {
            if (c['claimCount'] != null || c['startedAt'] != null) {
              throw const FormatException(
                'Legacy dispatch attribution is unknown',
              );
            }
            checkpoint = const SubmissionTransportCheckpoint.legacyUnknown();
          } else {
            checkpoint = SubmissionTransportCheckpoint.pending(
              claimCount: j.integer(c['claimCount']),
              startedAt: j.time(c['startedAt']),
            );
          }
        }
        return SubmissionRecord(
          request: request,
          state: state,
          claimCount: claimCount,
          updatedAt: j.time(v['updatedAt']),
          leaseToken: j.nullableString(v['leaseToken']),
          leaseExpiresAt: j.nullableTime(v['leaseExpiresAt']),
          nextAttemptAt: j.nullableTime(v['nextAttemptAt']),
          reservations: {
            for (final e in j.object(v['reservations']).entries)
              e.key: reservationFromJson(j.object(e.value)),
          },
          receipts: receipts,
          failureHistory: j
              .array(v['failureHistory'])
              .map((f) => failureFromJson(j.object(f)))
              .toList(),
          acknowledgement: v['acknowledgement'] == null
              ? null
              : acknowledgementFromJson(j.object(v['acknowledgement'])),
          transportCheckpoint: checkpoint,
        );
      });

  /// Encodes a full original reference and exact provenance.
  static Map<String, Object?> materialToJson(SubmissionMaterial value) => {
    'key': value.key,
    'original': j.detach(value.original.toJson()),
    'provenance': j.detach(value.provenance),
  };

  /// Decodes a material, retaining the accepted capture reference schema.
  static SubmissionMaterial materialFromJson(Map<String, Object?> json) =>
      j.decode(() {
        final v = j.exact(json, {'key', 'original', 'provenance'});
        return SubmissionMaterial(
          key: j.string(v['key']),
          original: CaptureMaterialReference.fromJson(j.object(v['original'])),
          provenance: j.object(v['provenance']),
        );
      });

  /// Encodes provider reservation data without interpreting remote identities.
  static Map<String, Object?> reservationToJson(
    SubmissionStorageReservation value,
  ) => {
    'key': value.key,
    'providerId': value.providerId,
    'data': j.detach(value.data),
  };

  /// Decodes exactly a reservation's own keys.
  static SubmissionStorageReservation reservationFromJson(
    Map<String, Object?> json,
  ) => j.decode(() {
    final v = j.exact(json, {'key', 'providerId', 'data'});
    return SubmissionStorageReservation(
      key: j.string(v['key']),
      providerId: j.string(v['providerId']),
      data: j.object(v['data']),
    );
  });

  /// Encodes storage success, preserving descriptive remote id and metadata.
  static Map<String, Object?> receiptToJson(SubmissionMaterialReceipt value) =>
      {
        'key': value.key,
        'providerId': value.providerId,
        'remoteId': value.remoteId,
        'accessConnectionId': value.accessConnectionId,
        'storedAt': value.storedAt.toIso8601String(),
        'metadata': j.detach(value.metadata),
      };

  /// Decodes exactly a receipt's own keys and explicit-zone time.
  static SubmissionMaterialReceipt receiptFromJson(Map<String, Object?> json) =>
      j.decode(() {
        final v = j.exact(json, {
          'key',
          'providerId',
          'remoteId',
          'accessConnectionId',
          'storedAt',
          'metadata',
        });
        return SubmissionMaterialReceipt(
          key: j.string(v['key']),
          providerId: j.string(v['providerId']),
          remoteId: j.string(v['remoteId']),
          accessConnectionId: j.string(v['accessConnectionId']),
          storedAt: j.time(v['storedAt']),
          metadata: j.object(v['metadata']),
        );
      });

  /// Encodes explicit server acceptance; this is separate from storage receipts.
  static Map<String, Object?> acknowledgementToJson(
    SubmissionAcknowledgement value,
  ) => {
    'requestId': value.requestId,
    'subjectId': value.subjectId,
    'serverId': value.serverId,
    'receivedAt': value.receivedAt.toIso8601String(),
    'extensions': j.detach(value.extensions),
  };

  /// Decodes exactly an acknowledgement's own keys.
  static SubmissionAcknowledgement acknowledgementFromJson(
    Map<String, Object?> json,
  ) => j.decode(() {
    final v = j.exact(json, {
      'requestId',
      'subjectId',
      'serverId',
      'receivedAt',
      'extensions',
    });
    return SubmissionAcknowledgement(
      requestId: j.string(v['requestId']),
      subjectId: j.string(v['subjectId']),
      serverId: j.string(v['serverId']),
      receivedAt: j.time(v['receivedAt']),
      extensions: j.object(v['extensions']),
    );
  });

  /// Encodes only safe structured failure fields.
  static Map<String, Object?> failureToJson(SubmissionFailure value) => {
    'stage': value.stage.name,
    'code': value.code,
    'message': value.message,
    'retryable': value.retryable,
    'occurredAt': value.occurredAt.toIso8601String(),
    'claimCount': value.claimCount,
  };

  /// Decodes exactly safe failure keys, enum, count and time.
  static SubmissionFailure failureFromJson(Map<String, Object?> json) =>
      j.decode(() {
        final v = j.exact(json, {
          'stage',
          'code',
          'message',
          'retryable',
          'occurredAt',
          'claimCount',
        });
        return SubmissionFailure(
          stage: j.enumeration(v['stage'], SubmissionFailureStage.values),
          code: j.string(v['code']),
          message: j.string(v['message']),
          retryable: j.boolean(v['retryable']),
          occurredAt: j.time(v['occurredAt']),
          claimCount: j.integer(v['claimCount']),
        );
      });

  /// Encodes the ordered server packet, excluding local document and raw bytes.
  /// References remain logical; this adds no path or credential fields.
  static Map<String, Object?> packetToJson(SubmissionPacket value) => {
    'version': 1,
    'requestId': value.request.id,
    'kind': value.request.kind,
    'subjectId': value.request.subjectId,
    'createdAt': value.request.createdAt.toIso8601String(),
    'payload': j.detach(value.request.payload),
    'extensions': j.detach(value.request.extensions),
    'materials': [
      for (final m in value.request.materials)
        {
          ...materialToJson(m),
          'receipt': receiptToJson(value.receipts[m.key]!),
        },
    ],
  };
}
