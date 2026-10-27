import 'dart:typed_data';

import 'submission_json.dart' as j;
import 'tkl_original_content.dart';

/// Availability supplied by TKL, independently of platform sign-in or uploads.
enum TklDestinationAvailability {
  available,
  configurationRequired,
  unavailable,
}

/// Physical mechanism selected by TKL; consumers never infer a Drive location.
enum TklMaterialTransferMethod { tklMultipart, googleDriveResumable }

/// TKL registration progress, separate from a Studio submission acknowledgement.
enum TklMaterialDeliveryState {
  prepared,
  transferring,
  readyToRegister,
  registering,
  registered,
  verifying,
  verificationFailed,
  reconciliationRequired,
}

enum TklOriginalVerificationState { pending, verifying, verified, failed }

/// Actual retained original progress, without provider keys or credentials.
enum TklOriginalTransferState {
  pending,
  transferring,
  uploaded,
  reconciliationRequired,
}

/// Logical server configuration projection; construction performs no IO.
final class TklMaterialDeliveryDestination {
  /// Available destinations require a complete logical binding and mechanism.
  /// Missing configuration can be represented without inventing a destination.
  TklMaterialDeliveryDestination({
    required this.availability,
    String? destinationId,
    String? label,
    this.transferMethod,
    this.maxResourceBytes,
    this.transferReason,
    this.contentIntegrity,
  }) : destinationId = destinationId == null ? null : _text(destinationId),
       label = label == null ? null : _text(label) {
    if ((this.destinationId == null) != (this.label == null) ||
        (availability == TklDestinationAvailability.available &&
            (this.destinationId == null || transferMethod == null)) ||
        (maxResourceBytes != null && maxResourceBytes! < 0) ||
        (contentIntegrity != null && contentIntegrity != 'sha256')) {
      throw ArgumentError('Invalid TKL destination projection.');
    }
  }

  final TklDestinationAvailability availability;
  final String? destinationId;
  final String? label;
  final TklMaterialTransferMethod? transferMethod;
  final int? maxResourceBytes;
  final String? transferReason;
  final String? contentIntegrity;

  @override
  String toString() => 'TklMaterialDeliveryDestination(${availability.name})';
}

/// Generic immutable committed JSON, with no Book or provider interpretation.
final class TklMaterialDeliveryRequest {
  /// Freezes JSON values while retaining nulls, list order and literal strings.
  /// TKL's owning contribution parser remains the semantic admission authority.
  TklMaterialDeliveryRequest({
    required String requestId,
    required Map<String, Object?> contribution,
  }) : requestId = j.token(requestId),
       contribution = j.frozenJson(contribution);

  final String requestId;
  final Map<String, Object?> contribution;

  @override
  String toString() => 'TklMaterialDeliveryRequest(<committed>)';
}

/// One logical original declaration and its observed TKL progress.
final class TklOriginalTransferProgress {
  /// Rejects invalid identifiers, MIME or lengths without reflecting inputs.
  TklOriginalTransferProgress({
    required String resourceId,
    required String mediaType,
    required this.byteLength,
    required this.state,
    this.contentDigest,
    this.verificationState,
    this.verificationAttempts,
    this.verificationReason,
  }) : resourceId = j.token(resourceId),
       mediaType = _text(mediaType) {
    if (byteLength < 0 ||
        !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+/[!#$%&'*+.^_`|~0-9A-Za-z-]+$")
            .hasMatch(mediaType)) {
      throw ArgumentError('Invalid TKL original progress.');
    }
    final hasProof = contentDigest != null;
    if (hasProof != (verificationState != null) ||
        hasProof != (verificationAttempts != null) ||
        (!hasProof && verificationReason != null) ||
        (verificationAttempts != null &&
            (verificationAttempts! < 0 || verificationAttempts! > 3)) ||
        (verificationReason != null &&
            verificationReason != 'integrityMismatch' &&
            verificationReason != 'verificationUnavailable') ||
        (verificationState == TklOriginalVerificationState.failed) !=
            (verificationReason != null) ||
        (verificationState == TklOriginalVerificationState.pending &&
            verificationAttempts != 0) ||
        (verificationState == TklOriginalVerificationState.verifying &&
            verificationAttempts == 3) ||
        (verificationState != null &&
            verificationState != TklOriginalVerificationState.pending &&
            (state != TklOriginalTransferState.uploaded ||
                verificationAttempts == 0)) ||
        (verificationReason == 'verificationUnavailable' &&
            verificationAttempts != 3)) {
      throw ArgumentError('Invalid TKL original verification.');
    }
  }

  final String resourceId;
  final String mediaType;
  final int byteLength;
  final TklOriginalTransferState state;
  final TklContentDigest? contentDigest;
  final TklOriginalVerificationState? verificationState;
  final int? verificationAttempts;
  final String? verificationReason;
}

/// Actual server state, never inferred from an upload or a planned Material URN.
final class TklMaterialDeliverySnapshot {
  /// Retains immutable resource order; only confirmed Registered exposes a
  /// Material reference. Construction does not persist, authorize or submit.
  TklMaterialDeliverySnapshot({
    required String deliveryRef,
    required String requestId,
    required this.revision,
    required String destinationId,
    required String destinationLabel,
    required this.state,
    required List<TklOriginalTransferProgress> resources,
    String? materialRef,
    String? actionRequired,
    this.transferMethod = TklMaterialTransferMethod.tklMultipart,
    this.transferReason,
  }) : deliveryRef = _text(deliveryRef),
       requestId = j.token(requestId),
       destinationId = _text(destinationId),
       destinationLabel = _text(destinationLabel),
       resources = List<TklOriginalTransferProgress>.unmodifiable(resources),
       materialRef = materialRef == null ? null : _text(materialRef),
       actionRequired = actionRequired == null ? null : _text(actionRequired) {
    final registered = state == TklMaterialDeliveryState.registered;
    final complete = this.resources.every(
      (resource) => resource.state == TklOriginalTransferState.uploaded,
    );
    final digestCount = this.resources.where((r) => r.contentDigest != null).length;
    final verified = this.resources.every(
      (r) => r.verificationState == TklOriginalVerificationState.verified,
    );
    if (revision <= 0 ||
        this.resources.map((resource) => resource.resourceId).toSet().length !=
            this.resources.length ||
        registered != (this.materialRef != null) ||
        ((registered ||
                state == TklMaterialDeliveryState.readyToRegister ||
                state == TklMaterialDeliveryState.registering) &&
            (!complete || (digestCount > 0 && !verified))) ||
        (digestCount != 0 && digestCount != this.resources.length) ||
        (state == TklMaterialDeliveryState.verifying &&
            (digestCount == 0 || verified || !this.resources.any(
              (r) => r.state == TklOriginalTransferState.uploaded &&
                  r.verificationState != TklOriginalVerificationState.verified,
            ))) ||
        (state == TklMaterialDeliveryState.verificationFailed &&
            !this.resources.any(
              (r) => r.verificationState == TklOriginalVerificationState.failed,
            ))) {
      throw ArgumentError('Invalid TKL delivery snapshot.');
    }
  }

  final String deliveryRef;
  final String requestId;
  final int revision;
  final String destinationId;
  final String destinationLabel;
  final TklMaterialDeliveryState state;
  final List<TklOriginalTransferProgress> resources;
  final String? materialRef;
  final String? actionRequired;
  final TklMaterialTransferMethod transferMethod;
  final String? transferReason;

  @override
  String toString() => 'TklMaterialDeliverySnapshot(${state.name}, $revision)';
}

/// Ephemeral, narrow provider instruction. Never persist its URI in queue/status.
final class TklDirectTransferInstruction {
  TklDirectTransferInstruction({
    required String transferRef,
    required String resourceId,
    required Uri uploadUri,
    required String mediaType,
    required this.byteLength,
    required this.nextOffset,
  }) : transferRef = _text(transferRef),
       resourceId = j.token(resourceId),
       uploadUri = uploadUri,
       mediaType = _text(mediaType) {
    final query = uploadUri.queryParametersAll;
    if (uploadUri.toString().length > 16384 ||
        uploadUri.scheme != 'https' ||
        uploadUri.host != 'www.googleapis.com' ||
        uploadUri.userInfo.isNotEmpty ||
        uploadUri.authority.contains('@') ||
        uploadUri.hasFragment ||
        uploadUri.port != 443 ||
        uploadUri.path != '/upload/drive/v3/files' ||
        uploadUri.toString().contains(RegExp(r'[\\\x00-\x20\x7f-\x9f]')) ||
        query['uploadType']?.length != 1 ||
        query['uploadType']?.single != 'resumable' ||
        query['upload_id']?.length != 1 ||
        query['upload_id']!.single.isEmpty ||
        byteLength < 0 ||
        nextOffset < 0 ||
        nextOffset > byteLength) {
      throw ArgumentError('Invalid TKL direct transfer instruction.');
    }
    TklOriginalTransferProgress(
      resourceId: resourceId,
      mediaType: mediaType,
      byteLength: byteLength,
      state: TklOriginalTransferState.pending,
    );
  }
  final String transferRef;
  final String resourceId;
  final Uri uploadUri;
  final String mediaType;
  final int byteLength;
  final int nextOffset;
  @override
  String toString() => 'TklDirectTransferInstruction(<redacted>)';
}

/// A fresh TKL observation and optional instruction for this one original.
final class TklDirectTransferPreparation {
  TklDirectTransferPreparation({required this.delivery, this.instruction}) {
    final instruction = this.instruction;
    if (instruction != null &&
        (delivery.transferMethod !=
                TklMaterialTransferMethod.googleDriveResumable ||
            !delivery.resources.any(
              (resource) =>
                  resource.resourceId == instruction.resourceId &&
                  resource.mediaType == instruction.mediaType &&
                  resource.byteLength == instruction.byteLength &&
                  resource.state == TklOriginalTransferState.pending,
            ))) {
      throw ArgumentError(
        'TKL transfer instruction does not match the delivery.',
      );
    }
  }
  final TklMaterialDeliverySnapshot delivery;
  final TklDirectTransferInstruction? instruction;
}

/// Safe local completion checkpoint, distinct from TKL's provider confirmation.
final class TklDirectUploadReceipt {
  TklDirectUploadReceipt({
    required String resourceId,
    required String transferRef,
    required this.byteLength,
  }) : resourceId = j.token(resourceId),
       transferRef = _text(transferRef) {
    if (byteLength < 0) throw ArgumentError('Invalid direct upload receipt.');
  }
  final String resourceId;
  final String transferRef;
  final int byteLength;
  @override
  String toString() => 'TklDirectUploadReceipt(<uploaded>)';
  @override
  bool operator ==(Object other) =>
      other is TklDirectUploadReceipt &&
      other.resourceId == resourceId &&
      other.transferRef == transferRef &&
      other.byteLength == byteLength;
  @override
  int get hashCode => Object.hash(resourceId, transferRef, byteLength);
}

/// Optional direct-transfer capability; ordinary TKL clients remain compatible.
abstract interface class TklDirectMaterialDeliveryClient
    implements TklMaterialDeliveryClient {
  Future<TklDirectTransferPreparation> prepareOriginalTransfer({
    required String deliveryRef,
    required String resourceId,
  });
  Future<TklDirectUploadReceipt> uploadDirect({
    required TklDirectTransferInstruction instruction,
    required Uint8List content,
  });
  Future<TklMaterialDeliverySnapshot> confirmOriginalTransfer({
    required String deliveryRef,
    required TklDirectUploadReceipt receipt,
  });
}

/// Borrowed reopenable half-open original reader. No path or session is retained.
typedef TklOriginalRangeReader = Stream<List<int>> Function(int start, int end);

/// Optional bounded direct ingress; the byte-array API remains source compatible.
abstract interface class TklStreamingDirectMaterialDeliveryClient
    implements TklDirectMaterialDeliveryClient {
  Future<TklDirectUploadReceipt> uploadDirectStream({
    required TklDirectTransferInstruction instruction,
    required int totalLength,
    required TklOriginalRangeReader openRange,
  });
}

/// Borrowed public TKL port for the existing Core queue/background owner.
///
/// Implementations preserve actual authenticated caller context and structured
/// failures. There is no close, scheduler, local queue or implicit authorization
/// on this port. An explicit HTTPS implementation is provided separately.
abstract interface class TklMaterialDeliveryClient {
  /// Passive server projection; no provisioning or Google consent is implied.
  Future<TklMaterialDeliveryDestination> getDestination();

  /// Uses the persisted Commit correlation. A retry first reconciles that
  /// correlation rather than calling the old create-only registration API.
  Future<TklMaterialDeliverySnapshot> prepare(
    TklMaterialDeliveryRequest request,
  );

  /// Null means confirmed authorized absence only, never an IO/auth failure.
  Future<TklMaterialDeliverySnapshot?> findForRequest(String requestId);

  /// Queries the same retained opaque reference without provider mutation.
  Future<TklMaterialDeliverySnapshot> get(String deliveryRef);

  /// Sends bytes for an exact retained declaration through TKL's chosen ingress.
  /// [mediaType] is the retained original declaration used for the binary part.
  /// Never interprets a reference as a local path or silently selects a provider.
  Future<TklMaterialDeliverySnapshot> uploadOriginal({
    required String deliveryRef,
    required String resourceId,
    required String mediaType,
    required Uint8List content,
  });

  /// Returns actual registration state; upload alone never supplies acceptance.
  Future<TklMaterialDeliverySnapshot> finalize(String deliveryRef);
}

String _text(String value) {
  if (value.trim().isEmpty ||
      value.length > 2048 ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'))) {
    throw ArgumentError('Invalid TKL delivery text.');
  }
  return value;
}
