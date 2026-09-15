import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('a local repository saves and reads a session by its identity', () async {
    // Given a session and a consumer-injected local repository.
    final session = _session();
    final CaptureLocalRepository repository = _MemoryLocalRepository();

    // When the session is saved and read with its identity.
    await repository.save(session);
    final readSession = await repository.read(session.id);

    // Then the matching immutable session is returned.
    expect(readSession, isNotNull);
    expect(readSession!.id, session.id);
    expect(readSession.lifecycle, session.lifecycle);
    expect(readSession.items, session.items);
    expect(readSession.createdAt, session.createdAt);
    expect(readSession.updatedAt, session.updatedAt);
    expect(await repository.read(CaptureSessionId('missing')), isNull);
  });

  test('a remote repository submits the supplied session independently',
      () async {
    // Given a session and a consumer-injected remote repository.
    final session = _session();
    final fake = _RecordingRemoteRepository();
    final CaptureRemoteRepository repository = fake;

    // When the session is submitted through the remote boundary.
    await repository.submit(session);

    // Then the remote implementation receives that session without local IO.
    expect(fake.submittedSessions, <CaptureSession>[session]);
  });
}

final class _MemoryLocalRepository implements CaptureLocalRepository {
  final Map<CaptureSessionId, CaptureSession> _sessions =
      <CaptureSessionId, CaptureSession>{};

  @override
  Future<CaptureSession?> read(CaptureSessionId id) async => _sessions[id];

  @override
  Future<void> save(CaptureSession session) async {
    _sessions[session.id] = session;
  }
}

final class _RecordingRemoteRepository implements CaptureRemoteRepository {
  final List<CaptureSession> submittedSessions = <CaptureSession>[];

  @override
  Future<void> submit(CaptureSession session) async {
    submittedSessions.add(session);
  }
}

CaptureSession _session() {
  return CaptureSession(
    id: CaptureSessionId('session-1'),
    lifecycle: CaptureSessionLifecycle.draft,
    items: const <CaptureItem>[],
    createdAt: DateTime.utc(2026, 9, 16),
    updatedAt: DateTime.utc(2026, 9, 16),
  );
}
