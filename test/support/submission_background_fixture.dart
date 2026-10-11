import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import 'submission_fixture.dart';
import 'submission_http_fixture.dart';

/// Behavioral test port only. It proves immutable configuration behavior, never
/// Android encryption, cross-engine SQL atomicity or a real Google account grant.
final class MemorySubmissionConfigurationStore
    implements SubmissionConfigurationStore, SubmissionCredentialProvider {
  final Map<String, DriveSubmissionConnection> _drive = {};
  final Map<String, HttpSubmissionConnection> _http = {};
  final Map<String, String> _tokens = {};
  Map<String, List<String>> _bindings = {};
  String? _storage;
  String? _transport;
  bool closed = false;
  int credentialCalls = 0;
  int snapshotCalls = 0;
  Future<void> Function()? beforeSnapshot;

  void _open() {
    // Given the test-owned handle has a monotonic closed state.
    final unavailable = closed;
    // When a caller attempts an operation after close.
    if (unavailable) {
      throw SubmissionConfigurationException.safe('configurationClosed');
    }
    // Then accepted open operations continue without silently reopening the handle.
  }

  @override
  Future<SubmissionConfigurationSnapshot> snapshot() async {
    // Given all committed safe definitions and the current new-intent selection.
    _open();
    snapshotCalls++;
    // Given an optional scenario-owned barrier/error before observing live data.
    // When that controlled read settles, reject a retired test handle as usual.
    await beforeSnapshot?.call();
    _open();
    // When the public snapshot freezes those values.
    final snapshot = SubmissionConfigurationSnapshot(
      driveConnections: _drive.values.toList(),
      httpConnections: _http.values.toList(),
      selectedStorageConnectionId: _storage,
      selectedTransportConnectionId: _transport,
      referenceAccessBindings: _bindings,
    );
    // Then callers cannot mutate the store through a snapshot or see secret fields.
    return snapshot;
  }

  void _insert(
    String id,
    Map<String, Object?> definition,
    void Function() write,
  ) {
    // Given the immutable identity already accepted under either kind.
    _open();
    final existing = _drive[id]?.toJson() ?? _http[id]?.toJson();
    // When a differing definition or an over-capacity new identity is proposed.
    if (existing != null && jsonEncode(existing) != jsonEncode(definition)) {
      throw SubmissionConfigurationException.safe('connectionConflict');
    }
    if (existing == null && _drive.length + _http.length >= 128) {
      throw SubmissionConfigurationException.safe('configurationInvalid');
    }
    // Then only a valid insertion reaches the atomic test-port write.
    write();
  }

  @override
  Future<void> putDrive(DriveSubmissionConnection connection) async {
    // Given the complete immutable drive definition supplied to the public port.
    final definition = connection.toJson();
    // When insertion is accepted, retain that exact account/folder identity.
    _insert(connection.id, definition, () {
      // Given identity validation succeeded without replacing another kind.
      final accepted = connection;
      // When the test port writes its safe definition.
      _drive[accepted.id] = accepted;
      // Then future snapshots contain the same target.
    });
    // Then conflicts throw before altering the previously accepted definition.
  }

  @override
  Future<void> putHttp(HttpSubmissionConnection connection) async {
    // Given an endpoint and its immutable authentication requirement.
    final definition = connection.toJson();
    // When insertion passes the same identity policy.
    _insert(connection.id, definition, () {
      // Given this definition is accepted under its stable HTTP identity.
      final accepted = connection;
      // When the safe definition is stored.
      _http[accepted.id] = accepted;
      // Then rotations can affect only its separately stored test credential.
    });
    // Then no previous secret or endpoint is replaced by a conflicting proposal.
  }

  @override
  Future<void> select({
    String? storageConnectionId,
    String? transportConnectionId,
  }) async {
    // Given current registered definitions and the old selection.
    _open();
    // When both new selections are validated before either is written.
    SubmissionConfigurationSnapshot(
      driveConnections: _drive.values.toList(),
      httpConnections: _http.values.toList(),
      selectedStorageConnectionId: storageConnectionId,
      selectedTransportConnectionId: transportConnectionId,
      referenceAccessBindings: _bindings,
    );
    _storage = storageConnectionId;
    _transport = transportConnectionId;
    // Then existing requests still reference their original ids and all maps survive.
  }

  @override
  Future<void> setReferenceAccess({
    required String transportConnectionId,
    required List<String> storageConnectionIds,
  }) async {
    // Given a copied proposal replacing just one explicit local test declaration.
    _open();
    final proposed = {
      ..._bindings,
      transportConnectionId: List<String>.of(storageConnectionIds),
    };
    // When the whole resulting snapshot validates before any committed write.
    final validated = SubmissionConfigurationSnapshot(
      driveConnections: _drive.values.toList(),
      httpConnections: _http.values.toList(),
      selectedStorageConnectionId: _storage,
      selectedTransportConnectionId: _transport,
      referenceAccessBindings: proposed,
    );
    // Then rejected proposals are atomic and accepted maps cannot alias inputs.
    _bindings = validated.referenceAccessBindings;
  }

  Future<void> setHttpBearerToken(String id, String? token) async {
    // Given a registered HTTP definition and a separately held test credential.
    _open();
    final connection = _http[id];
    // When a rotation/removal is proposed for that same exact definition.
    if (connection == null ||
        (token != null &&
            (!connection.requiresBearerToken ||
                token.length > 8192 ||
                !RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(token)))) {
      throw SubmissionConfigurationException.safe('configurationInvalid');
    }
    if (token == null) {
      _tokens.remove(id);
    } else {
      _tokens[id] = token;
    }
    // Then snapshots remain secret-free while dedicated retrieval reflects rotation.
  }

  @override
  Future<String?> bearerToken(String connectionId) async {
    // Given a matching configured connection and separately held test credentials.
    _open();
    // When only the credential port is explicitly called.
    credentialCalls++;
    final token = _tokens[connectionId];
    // Then a secret is returned only from this dedicated call, never from a snapshot.
    return token;
  }

  @override
  Future<void> close() async {
    // Given one test-owned handle, independent of the queue/client.
    final owned = this;
    // When its lifetime is retired repeatedly.
    owned.closed = true;
    // Then subsequent operations reject without removing its definitions.
  }
}

/// Test-owned real files/SQLite with accepted B1 HTTP adapters and controlled IO.
final class SubmissionBackgroundFixture {
  SubmissionBackgroundFixture._(this.disk);
  final SubmissionFixture disk;
  final network = SubmissionHttpFixture();
  final configuration = MemorySubmissionConfigurationStore();
  final List<CapturedSubmissionHttpRequest> uploads = [];
  Map<String, Object?>? serverPacket;
  int closes = 0;

  static Future<SubmissionBackgroundFixture> create() async {
    // Given a test-private real disk/SQLite fixture with separately owned ports.
    final disk = await SubmissionFixture.create();
    // When safe definitions are registered in a behavioral test port.
    final fixture = SubmissionBackgroundFixture._(disk);
    await fixture.configuration.putDrive(fixture.network.driveConnection);
    await fixture.configuration.putHttp(fixture.network.httpConnection);
    await fixture.configuration.select(
      storageConnectionId: 'drive',
      transportConnectionId: 'server',
    );
    // Given the fake server resolver explicitly owns access to this fake Drive.
    // When the fixture provisions that controlled fact independently of selection.
    await fixture.configuration.setReferenceAccess(
      transportConnectionId: 'server',
      storageConnectionIds: ['drive'],
    );
    // Then scenarios can alter selection while keeping accepted request identities.
    return fixture;
  }

  Future<SubmissionBackgroundResources> resources(
    SubmissionRunLifetime lifetime, {
    SubmissionQueueStore? queue,
  }) async {
    // Given a separately opened durable queue and all persisted safe definitions.
    final owned = queue ?? await disk.openQueue();
    final snapshot = await configuration.snapshot();
    // When the existing service borrows adapters configured for the same lifetime.
    final service = disk.service(
      owned,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: configuration,
      ),
      storageAdapters: {
        for (final connection in snapshot.driveConnections)
          connection.id: DriveSubmissionStorageAdapter(
            connection: connection,
            client: network.client,
            credentials: network.credentials,
            isRunCurrent: () => lifetime.isCurrent,
            cancellation: lifetime.cancelled,
          ),
      },
      transports: {
        for (final connection in snapshot.httpConnections)
          connection.id: HttpSubmissionTransport(
            connection: connection,
            client: network.client,
            credentials: network.credentials,
            isRunCurrent: () => lifetime.isCurrent,
            cancellation: lifetime.cancelled,
          ),
      },
    );
    var closed = false;
    // Then the runner can borrow the ports while the fixture alone controls cleanup.
    return SubmissionBackgroundResources(
      service: service,
      queue: owned,
      close: () async {
        // Given this custom composition owns service/queue handles, not its client.
        if (closed) return;
        closed = true;
        // When the owner explicitly drains and closes both handles.
        closes++;
        await service.close();
        await owned.close();
        // Then repeated close is harmless and no adapter closes the borrowed client.
        expect(network.client.closed, isFalse);
      },
    );
  }

  void successfulHttp(SubmissionRequest request) {
    // Given exact photo/audio originals and a controlled allocation/session state.
    var generated = 0;
    SubmissionMaterial? pending;
    Map<String, Object?>? metadata;
    // When the concrete B1 adapters send through the captured HTTP port.
    network.client.handler = (captured) async {
      // Given every request was built by the public concrete adapters.
      final body = captured.method == 'POST'
          ? captured.json
          : <String, Object?>{};
      // When the configured HTTP server receives the actual packet.
      if (captured.uri.host == network.httpConnection.endpoint.host) {
        serverPacket = body;
        // Then only a matching explicit controlled acknowledgement is returned.
        expect(captured.method, 'POST');
        return submissionJsonResponse(
          network.acknowledgement(request),
          status: 201,
        );
      }
      // Given preparation has no binary body and allocates one file per original.
      if (captured.uri.path.endsWith('/generateIds')) {
        final material = request.materials[generated++];
        // When a controlled remote identity is reserved.
        final response = submissionJsonResponse({
          'ids': ['File_${material.key}'],
          'space': 'drive',
          'kind': 'drive#generatedIds',
        });
        // Then all originals are reserved before any binary upload begins.
        expect(uploads, isEmpty);
        return response;
      }
      // Given a resumable initiation binds the existing immutable file id.
      if (captured.method == 'POST') {
        metadata = body;
        pending = request.materials.singleWhere(
          (m) => body['id'] == 'File_${m.key}',
        );
        // When the controlled remote opens a resumable session.
        final response = submissionEmptyResponse(
          200,
          headers: {'location': SubmissionHttpFixture.uploadLocation},
        );
        // Then the binary upload will use that same reserved identity.
        expect(metadata!['parents'], [network.driveConnection.folderId]);
        return response;
      }
      // Given a binary PUT for the exact material selected during initiation.
      final material = pending!;
      // When unchanged bytes reach the controlled HTTP boundary.
      uploads.add(captured);
      // Then metadata verification yields a real B1 receipt for this controlled response.
      expect(captured.method, 'PUT');
      return submissionJsonResponse(
        network.file(request, material, 'File_${material.key}'),
        status: 201,
      );
    };
    // Then tests observe actual adapter bodies and durable queue transitions.
  }

  Future<void> dispose() async {
    // Given fixture-owned real disk handles and a separately owned HTTP client.
    final owned = network.client;
    // When teardown joins services/queues before removing only test-private files.
    try {
      await disk.dispose();
    } finally {
      network.dispose();
      await configuration.close();
    }
    // Then all owned HTTP resources are closed and production roots are untouched.
    expect(owned.closed, isTrue);
  }
}
