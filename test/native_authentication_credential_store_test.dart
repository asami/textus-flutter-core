import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/src/authentication/native_authentication_credential_store.dart';

const _channel = MethodChannel(
  'org.textus.flutter.core/authentication_credentials',
);
const _revision = '00112233445566778899aabbccddeeff';
const _secretMarker = 'PRIVATE_NATIVE_CREDENTIAL';

Matcher _failure(NativeAuthenticationCredentialStoreErrorCode code) =>
    isA<NativeAuthenticationCredentialStoreException>()
        .having((error) => error.code, 'safe category', code)
        .having(
          (error) => '$error',
          'safe diagnostics',
          isNot(contains(_secretMarker)),
        );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('internal credential storage on $platform', () {
      late _MemoryNative native;
      setUp(() {
        debugDefaultTargetPlatformOverride = platform;
        native = _MemoryNative();
        messenger.setMockMethodCallHandler(_channel, native.handle);
      });

      test(
        'construction is inert and each handle has a fresh local identity',
        () async {
          // Given two new storage owners and no selected account/backend.
          final first = NativeAuthenticationCredentialStore();
          final second = NativeAuthenticationCredentialStore();
          // When support is queried and local entries are copied.
          expect(NativeAuthenticationCredentialStore.isSupported, isTrue);
          expect(native.calls, isEmpty);
          final bytes = Uint8List.fromList([1, 2]);
          final entry = NativeAuthenticationCredentialEntry(
            revision: _revision,
            value: bytes,
          );
          bytes[0] = 9;
          final snapshot = entry.value..[1] = 9;
          expect(snapshot, [1, 9]);
          // Then entry input/output cannot mutate storage snapshots or diagnostics.
          expect(entry.value, [1, 2]);
          expect('$entry', isNot(contains(_revision)));
          expect('$entry', isNot(contains('1, 2')));
          await first.read('slot');
          await second.read('slot');
          final handles = native.calls
              .map((call) => (call.arguments as Map)['handleId'])
              .toList();
          expect(handles.toSet().length, 2);
          expect(
            handles.every(
              (id) => id is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(id),
            ),
            isTrue,
          );
          await first.close();
          await second.close();
        },
      );

      test('structural bounds fail safely before channel dispatch', () async {
        // Given an open owner and invalid profile/revision/value inputs.
        final store = NativeAuthenticationCredentialStore();
        final valid = Uint8List.fromList([1]);
        // When every command receives rejected exact input, no argument is reflected.
        for (final profile in [
          '',
          '.slot',
          ' slot',
          'slot\n',
          'a/b',
          'é',
          'a' * 129,
        ]) {
          expect(() => store.read(profile), throwsArgumentError);
          expect(() => store.clear(profile), throwsArgumentError);
          expect(
            () => store.replace(
              profileId: profile,
              expectedRevision: null,
              value: valid,
            ),
            throwsArgumentError,
          );
          expect(
            () => store.remove(profileId: profile, expectedRevision: _revision),
            throwsArgumentError,
          );
        }
        for (final revision in [
          '',
          'A' * 32,
          'f' * 31,
          'f' * 33,
          '$_revision\n',
          _secretMarker,
        ]) {
          expect(
            () => store.replace(
              profileId: 'slot',
              expectedRevision: revision,
              value: valid,
            ),
            throwsArgumentError,
          );
          expect(
            () => store.remove(profileId: 'slot', expectedRevision: revision),
            throwsArgumentError,
          );
          expect(
            () => NativeAuthenticationCredentialEntry(
              revision: revision,
              value: valid,
            ),
            throwsArgumentError,
          );
        }
        for (final value in [Uint8List(0), Uint8List(65537)]) {
          expect(
            () => store.replace(
              profileId: 'slot',
              expectedRevision: null,
              value: value,
            ),
            throwsArgumentError,
          );
          expect(
            () => NativeAuthenticationCredentialEntry(
              revision: _revision,
              value: value,
            ),
            throwsArgumentError,
          );
        }
        try {
          store.read('$_secretMarker/');
          fail('Invalid input must be rejected');
        } catch (error) {
          expect('$error', isNot(contains(_secretMarker)));
        }
        // Then no invalid input reached the channel, while both endpoint sizes work.
        expect(native.calls, isEmpty);
        final maxProfile = 'a${'Z' * 127}';
        final first = await store.replace(
          profileId: maxProfile,
          expectedRevision: null,
          value: valid,
        );
        expect(first, isNotNull);
        final rotated = await store.replace(
          profileId: maxProfile,
          expectedRevision: first,
          value: Uint8List(65536),
        );
        expect(rotated, isNotNull);
        expect((await store.read(maxProfile))!.value.length, 65536);
        await store.close();
      });

      test('CAS and stale remove preserve exact profile and handle ownership', () async {
        // Given two independent owners of one synthetic protocol-backed store.
        final first = NativeAuthenticationCredentialStore();
        final second = NativeAuthenticationCredentialStore();
        final bytes = Uint8List.fromList([7, 8]);
        // When concurrent creates compete, only one null-expected write wins.
        expect(await first.read('Slot'), isNull);
        final create = first.replace(
          profileId: 'Slot',
          expectedRevision: null,
          value: bytes,
        );
        bytes[0] = 99;
        final competing = second.replace(
          profileId: 'Slot',
          expectedRevision: null,
          value: Uint8List.fromList([9]),
        );
        final outcomes = await Future.wait([create, competing]);
        expect(outcomes.whereType<String>().length, 1);
        final revision = outcomes.first!;
        expect(outcomes.last, isNull);
        expect((await second.read('Slot'))!.value, [7, 8]);
        final reply = (await second.read('Slot'))!.value..[0] = 77;
        expect(reply.first, 77);
        expect((await first.read('Slot'))!.value, [7, 8]);
        final other = await second.replace(
          profileId: 'slot',
          expectedRevision: null,
          value: Uint8List.fromList([2]),
        );
        final rotated = await second.replace(
          profileId: 'Slot',
          expectedRevision: revision,
          value: Uint8List.fromList([3]),
        );
        expect(rotated, isNot(revision));
        expect(
          await first.replace(
            profileId: 'Slot',
            expectedRevision: revision,
            value: Uint8List.fromList([4]),
          ),
          isNull,
        );
        expect(
          await first.remove(profileId: 'Slot', expectedRevision: revision),
          isFalse,
        );
        // Then stale ownership and retiring one handle cannot erase newer/other data.
        await first.close();
        expect(
          () => first.read('Slot'),
          throwsA(
            _failure(NativeAuthenticationCredentialStoreErrorCode.closed),
          ),
        );
        expect((await second.read('Slot'))!.revision, rotated);
        expect((await second.read('slot'))!.revision, other);
        expect(
          await second.remove(profileId: 'Slot', expectedRevision: rotated!),
          isTrue,
        );
        expect(
          await second.remove(profileId: 'Slot', expectedRevision: rotated),
          isFalse,
        );
        await second.clear('slot');
        await second.clear('slot');
        expect(await second.read('slot'), isNull);
        // Exact method maps are observed on the channel, including explicit null CAS.
        for (final call in native.calls) {
          final expected = switch (call.method) {
            'read' || 'clear' => {'handleId', 'profileId'},
            'replace' => {'handleId', 'profileId', 'expectedRevision', 'value'},
            'remove' => {'handleId', 'profileId', 'expectedRevision'},
            _ => {'handleId'},
          };
          expect((call.arguments as Map).keys.toSet(), expected);
        }
        await second.close();
      });

      test(
        'absent differs from safe native and missing-plugin failures',
        () async {
          // Given an absent slot, then native failures carrying private diagnostics.
          final store = NativeAuthenticationCredentialStore();
          expect(await store.read('slot'), isNull);
          for (final code in [
            'credentialStoreUnavailable',
            'unknown',
            'credentialStoreInvalidArguments',
            'credentialStoreClosed',
          ]) {
            messenger.setMockMethodCallHandler(_channel, (call) async {
              if (call.method == 'close') return null;
              throw PlatformException(
                code: code,
                message: _secretMarker,
                details: _secretMarker,
              );
            });
            // When native refuses access, only the fixed safe category is exposed.
            final expected = switch (code) {
              'credentialStoreInvalidArguments' =>
                NativeAuthenticationCredentialStoreErrorCode.invalidResponse,
              'credentialStoreClosed' =>
                NativeAuthenticationCredentialStoreErrorCode.closed,
              _ => NativeAuthenticationCredentialStoreErrorCode.unavailable,
            };
            await expectLater(store.read('slot'), throwsA(_failure(expected)));
          }
          messenger.setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'close') return null;
            throw MissingPluginException(_secretMarker);
          });
          // Then an unavailable implementation is never presented as an absent record.
          await expectLater(
            store.read('slot'),
            throwsA(
              _failure(
                NativeAuthenticationCredentialStoreErrorCode.unavailable,
              ),
            ),
          );
          await store.close();
        },
      );

      test('malformed replies cannot become stored entries or successful commands', () async {
        // Given native success envelopes with malformed closed-map values.
        final store = NativeAuthenticationCredentialStore();
        Object? reply;
        final methods = <String>[];
        messenger.setMockMethodCallHandler(_channel, (call) async {
          methods.add(call.method);
          return call.method == 'close' ? null : reply;
        });
        final invalid = _failure(
          NativeAuthenticationCredentialStoreErrorCode.invalidResponse,
        );
        // When read sees an extra/missing field, wrong type, invalid version-size metadata.
        for (final value in [
          <String, Object?>{},
          {
            'revision': _revision,
            'value': Uint8List.fromList([1]),
            'extra': true,
          },
          {
            'revision': 'A' * 32,
            'value': Uint8List.fromList([1]),
          },
          {
            'revision': _revision,
            'value': <int>[1],
          },
          {'revision': _revision, 'value': Uint8List(0)},
          {'revision': _revision, 'value': Uint8List(65537)},
          false,
        ]) {
          reply = value;
          await expectLater(store.read('slot'), throwsA(invalid));
        }
        for (final value in [
          true,
          'f' * 31,
          '$_revision\n',
          {'revision': _revision},
        ]) {
          reply = value;
          await expectLater(
            store.replace(
              profileId: 'slot',
              expectedRevision: null,
              value: Uint8List.fromList([1]),
            ),
            throwsA(invalid),
          );
        }
        reply = 1;
        await expectLater(
          store.remove(profileId: 'slot', expectedRevision: _revision),
          throwsA(invalid),
        );
        reply = false;
        await expectLater(store.clear('slot'), throwsA(invalid));
        // Then malformed reads never trigger hidden clear/remove/replace calls.
        expect(methods.where((method) => method == 'clear').length, 1);
        expect(methods.where((method) => method == 'remove').length, 1);
        expect(methods.where((method) => method == 'replace').length, 4);
        await store.close();
      });

      test('explicit clear recovers unavailable data without automatic read cleanup', () async {
        // Given an unreadable slot and a native boundary that only clear can recover.
        var unreadable = true;
        final methods = <String>[];
        messenger.setMockMethodCallHandler(_channel, (call) async {
          methods.add(call.method);
          if (call.method == 'close') return null;
          if (call.method == 'clear') {
            unreadable = false;
            return null;
          }
          if (unreadable) {
            throw PlatformException(
              code: 'credentialStoreUnavailable',
              details: _secretMarker,
            );
          }
          return null;
        });
        final store = NativeAuthenticationCredentialStore();
        // When a read fails, storage never clears it on behalf of the caller.
        await expectLater(
          store.read('slot'),
          throwsA(
            _failure(NativeAuthenticationCredentialStoreErrorCode.unavailable),
          ),
        );
        expect(methods, ['read']);
        expect(unreadable, isTrue);
        // Then an explicit trusted clear alone recovers absence, idempotently.
        await store.clear('slot');
        await store.clear('slot');
        expect(await store.read('slot'), isNull);
        expect(methods, ['read', 'clear', 'clear', 'read']);
        await store.close();
      });

      test(
        'concurrent revision owners receive one winner and one mismatch',
        () async {
          // Given two handles observing the exact same synthetic revision.
          final first = NativeAuthenticationCredentialStore();
          final second = NativeAuthenticationCredentialStore();
          final revision = await first.replace(
            profileId: 'slot',
            expectedRevision: null,
            value: Uint8List.fromList([1]),
          );
          // When both submit a rotation against that old revision concurrently.
          final results = await Future.wait([
            first.replace(
              profileId: 'slot',
              expectedRevision: revision,
              value: Uint8List.fromList([2]),
            ),
            second.replace(
              profileId: 'slot',
              expectedRevision: revision,
              value: Uint8List.fromList([3]),
            ),
          ]);
          // Then only the winner owns the current revision and stale removal fails.
          expect(results.whereType<String>().length, 1);
          expect(results.where((result) => result == null).length, 1);
          expect(
            (await second.read('slot'))!.revision,
            results.whereType<String>().single,
          );
          expect(
            await first.remove(profileId: 'slot', expectedRevision: revision!),
            isFalse,
          );
          expect((await second.read('slot'))!.value, [2]);
          await first.close();
          await second.close();
        },
      );

      test(
        'malformed native close is safe and its failed future is memoized',
        () async {
          // Given a native boundary that violates the close null-response ABI.
          var closes = 0;
          messenger.setMockMethodCallHandler(_channel, (call) async {
            closes++;
            return _secretMarker;
          });
          final store = NativeAuthenticationCredentialStore();
          // When the handle closes, native failure still leaves it retired.
          final closing = store.close();
          expect(identical(closing, store.close()), isTrue);
          await expectLater(
            closing,
            throwsA(
              _failure(
                NativeAuthenticationCredentialStoreErrorCode.unavailable,
              ),
            ),
          );
          // Then no retry channel dispatch or private diagnostics escape.
          expect(closes, 1);
          expect(
            () => store.read('slot'),
            throwsA(
              _failure(NativeAuthenticationCredentialStoreErrorCode.closed),
            ),
          );
        },
      );

      for (final method in ['read', 'replace']) {
        for (final throwsNative in [false, true]) {
          test(
            'close withdraws held $method and drains its ${throwsNative ? 'error' : 'value'}',
            () async {
              // Given accepted native IO held after dispatch and an independent close barrier.
              final entered = Completer<void>();
              final pending = Completer<Object?>();
              final closeEntered = Completer<void>();
              final closeReply = Completer<Object?>();
              messenger.setMockMethodCallHandler(_channel, (call) {
                if (call.method == 'close') {
                  closeEntered.complete();
                  return closeReply.future;
                }
                entered.complete();
                return pending.future;
              });
              final store = NativeAuthenticationCredentialStore();
              final operation = method == 'read'
                  ? store.read('slot')
                  : store.replace(
                      profileId: 'slot',
                      expectedRevision: null,
                      value: Uint8List.fromList([1]),
                    );
              final withdrawn = expectLater(
                operation,
                throwsA(
                  _failure(NativeAuthenticationCredentialStoreErrorCode.closed),
                ),
              );
              Future<void>? closing;
              Future<Object?>? closeOutcome;
              var done = false;
              try {
                await entered.future;
                // When close retires before awaiting, it starts native close immediately.
                closing = store.close();
                expect(identical(closing, store.close()), isTrue);
                closeOutcome = closing.then<Object?>(
                  (_) {
                    done = true;
                    return null;
                  },
                  onError: (Object error) {
                    done = true;
                    return error;
                  },
                );
                await closeEntered.future;
                expect(
                  () => store.clear('slot'),
                  throwsA(
                    _failure(
                      NativeAuthenticationCredentialStoreErrorCode.closed,
                    ),
                  ),
                );
                closeReply.complete(null);
                await Future<void>.value();
                expect(done, isFalse);
                if (throwsNative) {
                  pending.completeError(
                    PlatformException(
                      code: 'unknown',
                      message: _secretMarker,
                      details: _secretMarker,
                    ),
                  );
                } else {
                  pending.complete(
                    method == 'read'
                        ? {
                            'revision': _revision,
                            'value': Uint8List.fromList([1]),
                          }
                        : _revision,
                  );
                }
                await withdrawn;
                final outcome = await closeOutcome;
                // Then no late value publishes, and close reports a fixed safe drain error.
                if (throwsNative) {
                  expect(
                    outcome,
                    _failure(
                      NativeAuthenticationCredentialStoreErrorCode.unavailable,
                    ),
                  );
                } else {
                  expect(outcome, isNull);
                }
                expect(done, isTrue);
              } finally {
                if (!pending.isCompleted) pending.complete(null);
                if (!closeReply.isCompleted) closeReply.complete(null);
                await withdrawn;
                if (closeOutcome != null) await closeOutcome;
                if (closing == null) await store.close();
              }
            },
          );
        }
      }

      test(
        'native close failure still joins every accepted operation',
        () async {
          // Given two held reads and a native close that fails before either drains.
          final first = Completer<Object?>();
          final second = Completer<Object?>();
          final entered = Completer<void>();
          var reads = 0;
          messenger.setMockMethodCallHandler(_channel, (call) {
            if (call.method == 'close') {
              throw PlatformException(code: 'unknown', message: _secretMarker);
            }
            reads++;
            if (reads == 2) entered.complete();
            return reads == 1 ? first.future : second.future;
          });
          final store = NativeAuthenticationCredentialStore();
          final one = expectLater(
            store.read('one'),
            throwsA(
              _failure(NativeAuthenticationCredentialStoreErrorCode.closed),
            ),
          );
          final two = expectLater(
            store.read('two'),
            throwsA(
              _failure(NativeAuthenticationCredentialStoreErrorCode.closed),
            ),
          );
          Future<Object?>? joined;
          var done = false;
          try {
            await entered.future;
            // When close and one IO fail, the second pending call still owns drain work.
            joined = store.close().then<Object?>(
              (_) {
                done = true;
                return null;
              },
              onError: (Object error) {
                done = true;
                return error;
              },
            );
            first.completeError(
              PlatformException(code: 'unknown', details: _secretMarker),
            );
            await one;
            expect(done, isFalse);
            second.complete(null);
            await two;
            // Then the final safe error appears only after both accepted calls finish.
            expect(
              await joined,
              _failure(
                NativeAuthenticationCredentialStoreErrorCode.unavailable,
              ),
            );
            expect(done, isTrue);
          } finally {
            if (!first.isCompleted) first.complete(null);
            if (!second.isCompleted) second.complete(null);
            await Future.wait([one, two]);
            if (joined != null) await joined;
          }
        },
      );
    });
  }

  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.fuchsia,
  ]) {
    test(
      'unsupported $platform operations and memoized close perform no channel IO',
      () async {
        // Given a non-mobile platform with a channel tripwire.
        debugDefaultTargetPlatformOverride = platform;
        var calls = 0;
        messenger.setMockMethodCallHandler(_channel, (call) async {
          calls++;
          return null;
        });
        final store = NativeAuthenticationCredentialStore();
        // When all operations and close are attempted, support fails before dispatch.
        expect(NativeAuthenticationCredentialStore.isSupported, isFalse);
        final unavailable = throwsA(
          _failure(NativeAuthenticationCredentialStoreErrorCode.unavailable),
        );
        expect(() => store.read('slot'), unavailable);
        expect(
          () => store.replace(
            profileId: 'slot',
            expectedRevision: null,
            value: Uint8List.fromList([1]),
          ),
          unavailable,
        );
        expect(
          () => store.remove(profileId: 'slot', expectedRevision: _revision),
          unavailable,
        );
        expect(() => store.clear('slot'), unavailable);
        final closing = store.close();
        expect(identical(closing, store.close()), isTrue);
        await closing;
        // Then no native IO occurs and subsequent operations expose only closed.
        expect(calls, 0);
        expect(
          () => store.read('slot'),
          throwsA(
            _failure(NativeAuthenticationCredentialStoreErrorCode.closed),
          ),
        );
      },
    );
  }
}

/// Protocol fake only; it supplies no OS protection or authentication proof.
final class _MemoryNative {
  final calls = <MethodCall>[];
  final records = <String, NativeAuthenticationCredentialEntry>{};
  int next = 0;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final arguments = call.arguments as Map;
    final profile = arguments['profileId'] as String?;
    final entry = records[profile];
    switch (call.method) {
      case 'read':
        return entry == null
            ? null
            : {'revision': entry.revision, 'value': entry.value};
      case 'replace':
        if (entry?.revision != arguments['expectedRevision']) return null;
        final revision = (++next).toRadixString(16).padLeft(32, '0');
        records[profile!] = NativeAuthenticationCredentialEntry(
          revision: revision,
          value: arguments['value'] as Uint8List,
        );
        return revision;
      case 'remove':
        if (entry == null || entry.revision != arguments['expectedRevision']) {
          return false;
        }
        records.remove(profile);
        return true;
      case 'clear':
        records.remove(profile);
        return null;
      case 'close':
        return null;
      default:
        throw MissingPluginException();
    }
  }
}
