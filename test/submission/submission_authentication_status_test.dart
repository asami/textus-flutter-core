import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final lake in [false, true]) {
    for (final bound in [false, true]) {
      test(
        'local binding survives codec and observations (lake=$lake, bound=$bound)',
        () {
          // Given immutable local intent with one original and no login or ACK.
          final request = _request(lake: lake, bound: bound);
          final ready = SubmissionRecord(
            request: request,
            state: SubmissionState.readyToSubmit,
            claimCount: 0,
            updatedAt: _time,
          );
          // When persistence is decoded and current network observations change.
          final decoded = SubmissionCodec.recordFromJson(
            SubmissionCodec.recordToJson(ready),
          );
          final statuses = [
            for (final network in SubmissionNetworkState.values)
              SubmissionTransferStatus.fromRecord(
                decoded,
                observedAt: _time,
                networkState: network,
              ),
          ];
          // Then the flag follows only saved intent, without fabricating progress or authority.
          for (final status in statuses) {
            expect(status.hasAuthenticationBinding, bound);
            expect(status.usesLakeDelivery, lake);
            expect(status.upload.completedCount, 0);
            expect(status.upload.totalCount, 1);
            expect(
              status.files.single.original,
              request.materials.single.original,
            );
            expect(status.acknowledgement, isNull);
            expect(status.acknowledgementUncertain, isFalse);
            expect(status.actions, {SubmissionTransferAction.requestRun});
          }
          expect(decoded, ready);
          expect(
            decoded.request.authenticationBinding,
            request.authenticationBinding,
          );
        },
      );

      test(
        'failure never invents or removes binding (lake=$lake, bound=$bound)',
        () {
          // Given an authenticationRequired failure attributed to a real claim.
          final request = _request(lake: lake, bound: bound);
          final failure = SubmissionFailure(
            stage: SubmissionFailureStage.configuration,
            code: 'authenticationRequired',
            message: 'Authentication is required.',
            retryable: false,
            occurredAt: _time,
            claimCount: 1,
          );
          final failed = SubmissionRecord(
            request: request,
            state: SubmissionState.submissionFailed,
            claimCount: 1,
            updatedAt: _time,
            failureHistory: [failure],
          );
          // When the existing failed queue facts are projected without any account input.
          final status = SubmissionTransferStatus.fromRecord(
            failed,
            observedAt: _time,
          );
          // Then binding is independent of the failure code and retry remains the existing action.
          expect(status.hasAuthenticationBinding, bound);
          expect(status.upload.state, SubmissionTransferOperationState.failed);
          expect(status.upload.failure, failure);
          expect(status.actions, {SubmissionTransferAction.retry});
          expect(status.acknowledgement, isNull);
          expect(status.acknowledgementUncertain, isFalse);
        },
      );
    }

    test(
      'binding fact participates in status value semantics (lake=$lake)',
      () {
        // Given records equal in all pre-existing presentation facts and differing only in binding.
        SubmissionTransferStatus project(bool bound) =>
            SubmissionTransferStatus.fromRecord(
              SubmissionRecord(
                request: _request(lake: lake, bound: bound),
                state: SubmissionState.readyToSubmit,
                claimCount: 0,
                updatedAt: _time,
              ),
              observedAt: _time,
            );
        // When independent observations of each immutable request are compared.
        final unbound = project(false);
        final bound = project(true);
        final equalBound = project(true);
        // Then the new observed fact distinguishes values and equal values retain equal hashes.
        expect(bound, equalBound);
        expect(bound.hashCode, equalBound.hashCode);
        expect(bound, isNot(unbound));
        expect(bound.upload, unbound.upload);
        expect(bound.submission, unbound.submission);
        expect(bound.actions, unbound.actions);
        expect(bound.files, unbound.files);
      },
    );
  }

  for (final bound in [false, true]) {
    test('ordinary acceptance and uncertainty retain binding=$bound', () {
      // Given a no-upload ordinary request and an earlier potentially sent claim.
      final request = _request(lake: false, bound: bound, original: false);
      final failure = SubmissionFailure(
        stage: SubmissionFailureStage.transport,
        code: 'authRequired',
        message: 'Authentication expired.',
        retryable: false,
        occurredAt: _time,
        claimCount: 1,
      );
      final unknown = SubmissionRecord(
        request: request,
        state: SubmissionState.submissionFailed,
        claimCount: 1,
        updatedAt: _time,
        failureHistory: [failure],
        transportCheckpoint: SubmissionTransportCheckpoint.pending(
          claimCount: 1,
          startedAt: _time,
        ),
      );
      final ack = SubmissionAcknowledgement(
        requestId: request.id,
        subjectId: request.subjectId,
        serverId: 'confirmed-studio',
        receivedAt: _time,
      );
      final accepted = SubmissionRecord(
        request: request,
        state: SubmissionState.submitted,
        claimCount: 1,
        updatedAt: _time,
        acknowledgement: ack,
      );
      // When both actual lifecycle snapshots are projected independently.
      final uncertain = SubmissionTransferStatus.fromRecord(
        unknown,
        observedAt: _time,
      );
      final received = SubmissionTransferStatus.fromRecord(
        accepted,
        observedAt: _time,
      );
      // Then neither uncertainty nor matching acceptance changes the local binding fact.
      expect(uncertain.hasAuthenticationBinding, bound);
      expect(uncertain.acknowledgementUncertain, isTrue);
      expect(
        uncertain.submission.state,
        SubmissionTransferOperationState.outcomeUnknown,
      );
      expect(uncertain.acknowledgement, isNull);
      expect(received.hasAuthenticationBinding, bound);
      expect(received.acknowledgement, ack);
      expect(
        received.submission.state,
        SubmissionTransferOperationState.succeeded,
      );
      expect(received.actions, isEmpty);
    });

    test(
      'real queue reopen and separate Registered handoff retain binding=$bound',
      () async {
        // Given a real SQLite source whose immutable participant intent is already saved.
        final fixture = await SubmissionFixture.create();
        try {
          final queue = await fixture.openQueue();
          final request = _request(lake: true, bound: bound, original: false);
          await queue.enqueue(request);
          await queue.claimNext(
            now: _time,
            leaseToken: 'registration',
            leaseDuration: const Duration(minutes: 1),
          );
          final snapshot = TklMaterialDeliverySnapshot(
            deliveryRef: 'delivery',
            requestId: request.id,
            revision: 1,
            destinationId: 'fixtureLibrary',
            destinationLabel: 'Registered library',
            state: TklMaterialDeliveryState.registered,
            materialRef: 'urn:textus:klake:test:material:binding',
            resources: const [],
          );
          await queue.saveTklProgress(
            id: request.id,
            leaseToken: 'registration',
            now: _time,
            progress: snapshot,
          );
          final source = await queue.completeMaterialRegistration(
            id: request.id,
            leaseToken: 'registration',
            now: _time,
          );
          final target = HttpSubmissionConnection(
            id: 'studio',
            endpoint: Uri.parse('https://studio.example.test/book-materials'),
          );
          final packet = RegisteredMaterialSubmissionPacket(
            sourceRequest: request,
            target: target,
            association: RegisteredMaterialAssociation(
              materialRef: snapshot.materialRef!,
              resources: const [],
            ),
          );
          await queue.createHandoff(
            id: 'handoff',
            source: source,
            target: target,
            packet: packet,
            now: _time,
          );
          await queue.claimNextHandoff(
            now: _time,
            leaseToken: 'handoff-claim',
            leaseDuration: const Duration(minutes: 1),
          );
          await queue.finishHandoff(
            id: 'handoff',
            leaseToken: 'handoff-claim',
            now: _time,
            state: RegisteredMaterialHandoffState.outcomeUnknown,
            failure: RegisteredMaterialHandoffFailure(
              kind: RegisteredMaterialHandoffFailureKind.outcomeUnknown,
              code: 'acceptanceUnknown',
              message: 'Unconfirmed acceptance.',
            ),
          );
          // When a separate real database handle reads and projects the saved source and handoff.
          final reopened = await fixture.openQueue();
          final retained = (await reopened.find(request.id))!;
          final handoff = (await reopened.findHandoffForSource(request.id))!;
          final status = SubmissionTransferStatus.fromRecord(
            retained,
            observedAt: _time,
            handoff: handoff,
            networkState: SubmissionNetworkState.offline,
          );
          // Then separate Studio uncertainty supplies no login or owner inference and no ACK.
          expect(status.hasAuthenticationBinding, bound);
          expect(retained, source);
          expect(
            handoff.sourceRequest.authenticationBinding,
            request.authenticationBinding,
          );
          expect(
            status.registration!.state,
            SubmissionTransferOperationState.succeeded,
          );
          expect(
            status.submission.state,
            SubmissionTransferOperationState.outcomeUnknown,
          );
          expect(status.acknowledgementUncertain, isTrue);
          expect(status.acknowledgement, isNull);
          expect(status.actions, isEmpty);
          expect(fixture.scheduler.calls, 0);
          expect(fixture.transport.packets, isEmpty);
          expect(fixture.storage.prepares, 0);
        } finally {
          await fixture.dispose();
        }
      },
    );
  }
}

final _time = DateTime.utc(2026, 11, 6, 1);

SubmissionRequest _request({
  required bool lake,
  required bool bound,
  bool original = true,
}) => SubmissionRequest(
  id: 'book',
  kind: 'bookMaterial',
  subjectId: 'book',
  createdAt: _time,
  document: const {'title': '保持した原文'},
  payload: const {
    'schemaVersion': 1,
    'type': 'bookMaterial',
    'material': {'schemaVersion': 2, 'id': 'book'},
    'recognitionReports': <String, Object?>{},
  },
  materials: [
    if (original)
      SubmissionMaterial(
        key: 'photo',
        original: CaptureMaterialReference(
          id: 'original',
          mediaType: 'image/jpeg',
          byteLength: 3,
          capturedAt: _time,
        ),
      ),
  ],
  storageConnectionId: !lake && original ? 'drive' : null,
  transportConnectionId: 'transport',
  tklDelivery: lake
      ? TklMaterialDeliveryRequest(requestId: 'book', contribution: const {})
      : null,
  authenticationBinding: bound
      ? SubmissionAuthenticationBinding(
          authority: UserAccountHttpProfile.fromString(
            profileId: 'studio-user',
            serviceBaseUri: 'https://studio.example.test',
          ),
          userAccountId: 'PRIVATE.ACCOUNT.A',
        )
      : null,
);
