part of 'user_account_http_authentication_backend.dart';

/// Private storage port: both adapters retain the backend's existing CAS and
/// staged-session acceptance protocol. No credential becomes a UI model.
abstract interface class _CredentialSlot {
  Future<NativeAuthenticationCredentialEntry?> read(String profileId);
  Future<String?> replace({
    required String profileId,
    required String? expectedRevision,
    required Uint8List value,
  });
  Future<bool> remove({
    required String profileId,
    required String expectedRevision,
  });
  Future<void> close();
}

final class _NativeCredentialSlot implements _CredentialSlot {
  _NativeCredentialSlot(this.store);
  final NativeAuthenticationCredentialStore store;

  @override
  Future<NativeAuthenticationCredentialEntry?> read(String profileId) =>
      store.read(profileId);
  @override
  Future<String?> replace({
    required String profileId,
    required String? expectedRevision,
    required Uint8List value,
  }) => store.replace(
    profileId: profileId,
    expectedRevision: expectedRevision,
    value: value,
  );
  @override
  Future<bool> remove({
    required String profileId,
    required String expectedRevision,
  }) => store.remove(profileId: profileId, expectedRevision: expectedRevision);
  @override
  Future<void> close() => store.close();
}

final class _MemoryCredentialSlot implements _CredentialSlot {
  final Map<String, NativeAuthenticationCredentialEntry> _entries = {};
  final Random _random = Random.secure();
  bool _closed = false;

  void _requireOpen() {
    if (_closed) throw StateError('Authentication credential slot is closed');
  }

  @override
  Future<NativeAuthenticationCredentialEntry?> read(String profileId) async {
    _requireOpen();
    return _entries[profileId];
  }

  @override
  Future<String?> replace({
    required String profileId,
    required String? expectedRevision,
    required Uint8List value,
  }) async {
    _requireOpen();
    if (_entries[profileId]?.revision != expectedRevision) return null;
    final revision = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _entries[profileId] = NativeAuthenticationCredentialEntry(
      revision: revision,
      value: value,
    );
    return revision;
  }

  @override
  Future<bool> remove({
    required String profileId,
    required String expectedRevision,
  }) async {
    _requireOpen();
    if (_entries[profileId]?.revision != expectedRevision) return false;
    _entries.remove(profileId);
    return true;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _entries.clear();
  }
}
