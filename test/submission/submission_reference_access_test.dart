import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_background_fixture.dart';
import '../support/submission_fixture.dart';

void main() {
  test('RA1 exact receipt access ids override unrelated selection and remain frozen', () async {
    // Given real photo/audio intent whose actual receipts use two different ids.
    final fixture = await SubmissionFixture.create();
    final store = MemorySubmissionConfigurationStore();
    try {
      final request = await fixture.request();
      final packet = _packet(request, ['drive', 'otherDrive']);
      final wire = SubmissionCodec.packetToJson(packet);
      await _definitions(store);
      final selected = await store.snapshot();
      final ids = ['drive', 'otherDrive'];
      final bindings = {'server': ids};
      // When pure evaluation inspects only safe registered ids and explicit map.
      final sufficient = _snapshot(selected, bindings);
      final available =
          ConfiguredSubmissionReferenceAccessPolicy.evaluateSnapshot(
            packet: packet,
            snapshot: sufficient,
          );
      ids.clear();
      bindings.clear();
      // Then unrelated selected pair cannot redirect exact receipt access checks.
      expect(available, SubmissionReferenceAccessState.available);
      expect(sufficient.selectedStorageConnectionId, 'selectedDrive');
      expect(sufficient.selectedTransportConnectionId, 'selectedServer');
      expect(sufficient.referenceAccessBindings, {
        'server': ['drive', 'otherDrive'],
      });
      for (final access in <Map<String, List<String>>>[
        {},
        {'server': []},
        {
          'server': ['drive'],
        },
      ]) {
        // Given missing, explicitly empty, or insufficient local declarations.
        // When the same immutable packet is reevaluated against each snapshot.
        final state =
            ConfiguredSubmissionReferenceAccessPolicy.evaluateSnapshot(
              packet: packet,
              snapshot: _snapshot(selected, access),
            );
        // Then only a missing key is unknown; known insufficient access is denied.
        expect(
          state,
          access.isEmpty
              ? SubmissionReferenceAccessState.unknown
              : SubmissionReferenceAccessState.unavailable,
        );
      }
      // Given an unknown actual receipt id or unregistered transport definition.
      // When the pure evaluator inspects either independently of binding presence.
      final unknownReceipt =
          ConfiguredSubmissionReferenceAccessPolicy.evaluateSnapshot(
            packet: _packet(request, ['drive', 'missing']),
            snapshot: sufficient,
          );
      final missingTransport = SubmissionConfigurationSnapshot(
        driveConnections: selected.driveConnections,
        httpConnections: [],
      );
      // Then neither selection, request storage id nor receipt alone grants access.
      expect(unknownReceipt, SubmissionReferenceAccessState.unavailable);
      expect(
        ConfiguredSubmissionReferenceAccessPolicy.evaluateSnapshot(
          packet: packet,
          snapshot: missingTransport,
        ),
        SubmissionReferenceAccessState.unavailable,
      );
      expect(SubmissionCodec.packetToJson(packet), wire);
      expect(store.credentialCalls, 0);
      expect(fixture.scheduler.calls, 0);
      expect(fixture.storage.prepares, 0);
      expect(fixture.storage.uploads, 0);
      expect(fixture.transport.submits, 0);
    } finally {
      // Given only this scenario owns the test store and real files/queues.
      // When independent owners drain and close, then no borrowed port is leaked.
      await store.close();
      await fixture.dispose();
    }
  });

  test('RA1 every required evaluation reads live bindings and zero materials skip IO', () async {
    // Given a live mutable test configuration and independently controlled ports.
    final fixture = await SubmissionFixture.create();
    final store = MemorySubmissionConfigurationStore();
    try {
      await _definitions(store);
      final policy = ConfiguredSubmissionReferenceAccessPolicy(
        configuration: store,
      );
      final packet = _packet(await fixture.request(), ['drive', 'otherDrive']);
      final empty = SubmissionPacket(
        request: await fixture.request(
          id: 'empty',
          subjectId: 'emptySubject',
          withMaterials: false,
        ),
        receipts: {},
      );
      // When an empty packet is observed before any configured store read.
      expect(
        await policy.evaluate(empty),
        SubmissionReferenceAccessState.available,
      );
      // Then no snapshot, credentials or remote operation is needed.
      expect(store.snapshotCalls, 0);
      // When required packets are observed across explicit provision and revocation.
      expect(
        await policy.evaluate(packet),
        SubmissionReferenceAccessState.unknown,
      );
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: ['drive', 'otherDrive'],
      );
      expect(
        await policy.evaluate(packet),
        SubmissionReferenceAccessState.available,
      );
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: [],
      );
      expect(
        await policy.evaluate(packet),
        SubmissionReferenceAccessState.unavailable,
      );
      // Then every observation is fresh and no credential/wake/upload/POST occurs.
      expect(store.snapshotCalls, 3);
      expect(store.credentialCalls, 0);
      expect(fixture.scheduler.calls, 0);
      expect(fixture.storage.uploads, 0);
      expect(fixture.transport.submits, 0);
    } finally {
      // Given independent owners for configuration and real local artifacts.
      // When cleanup closes both, then policy has never claimed their lifetimes.
      await store.close();
      await fixture.dispose();
    }
  });
}

Future<void> _definitions(MemorySubmissionConfigurationStore store) async {
  // Given three safe Drive ids and two HTTP ids, with unrelated selection.
  for (final id in ['drive', 'otherDrive', 'selectedDrive']) {
    // When each exact immutable storage target is registered in the test port.
    await store.putDrive(
      DriveSubmissionConnection(
        id: id,
        accountId: 'owner@example.test',
        folderId: 'Folder',
      ),
    );
    // Then later receipt membership checks use the actual registered definition.
  }
  for (final id in ['server', 'selectedServer']) {
    // Given independently registered transport identities.
    // When they are inserted without any fabricated resolver access.
    await store.putHttp(
      HttpSubmissionConnection(
        id: id,
        endpoint: Uri.parse('https://example.test/submit'),
      ),
    );
    // Then selection can vary separately from the explicit binding map.
  }
  // When the unrelated pair is selected for future intent, then packet ids remain.
  await store.select(
    storageConnectionId: 'selectedDrive',
    transportConnectionId: 'selectedServer',
  );
}

SubmissionConfigurationSnapshot _snapshot(
  SubmissionConfigurationSnapshot base,
  Map<String, List<String>> bindings,
) {
  // Given the same safe definitions/selection and one explicit local access fact.
  // When a new frozen snapshot is built without credentials or inferred grants.
  final snapshot = SubmissionConfigurationSnapshot(
    driveConnections: base.driveConnections,
    httpConnections: base.httpConnections,
    selectedStorageConnectionId: base.selectedStorageConnectionId,
    selectedTransportConnectionId: base.selectedTransportConnectionId,
    referenceAccessBindings: bindings,
  );
  // Then scenarios can compare current map semantics while base remains frozen.
  return snapshot;
}

SubmissionPacket _packet(SubmissionRequest request, List<String> accessIds) {
  // Given one actual required key and explicit access id for each controlled receipt.
  // When the complete immutable packet validates matching material receipt keys.
  final packet = SubmissionPacket(
    request: request,
    receipts: {
      for (var i = 0; i < request.materials.length; i++)
        request.materials[i].key: SubmissionMaterialReceipt(
          key: request.materials[i].key,
          providerId: 'controlledDrive',
          remoteId: 'controlled/${request.materials[i].key}',
          accessConnectionId: accessIds[i],
          storedAt: request.createdAt,
        ),
    },
  );
  // Then evaluation receives actual receipt access ids, never inferred selection.
  return packet;
}
