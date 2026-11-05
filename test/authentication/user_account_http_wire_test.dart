import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/src/authentication/user_account_http_wire.dart';

final _invalidResponse = throwsA(
  isA<UserAccountHttpWireException>().having(
    (error) => error.toString(),
    'fixed safe diagnostic',
    'UserAccountHttpWireException(invalidResponse)',
  ),
);

// Independently authored synthetic objects; these are not execution captures.
Map<String, Object?> _session() => {
  'user_account_id': ' synthetic/account:α ',
  'credential_id': 'synthetic credential',
  'access_session_id': 'synthetic/access-session',
  'access_token': 'SYNTHETIC.access+token/one==',
  'refresh_session_id': 'synthetic/refresh-session',
  'refresh_token': 'SYNTHETIC_refresh~token-two=',
  'authenticated': true,
};

Map<String, Object?> _challenge() => {
  'user_account_id': ' synthetic/account:α ',
  'credential_id': 'synthetic credential',
  'two_factor_required': true,
  'challenge_id': ' synthetic/challenge:β ',
  'channel': 'email',
  'authenticated': false,
};

void main() {
  group('distinct six-key refresh objects', () {
    Map<String, Object?> refresh() => {
      'user_account_id': 'synthetic/rotating-account',
      'access_session_id': 'synthetic/new-access-session',
      'access_token': 'SYNTHETIC.rotated-access=',
      'refresh_session_id': 'synthetic/new-refresh-session',
      'refresh_token': 'SYNTHETIC.rotated-refresh==',
      'authenticated': true,
    };

    test(
      'refresh preserves exact fields without manufacturing a credential',
      () {
        // Given an independently authored six-key rotated pair.
        final document = refresh();
        // When the refresh decoder consumes it and the input changes later.
        final pair = decodeUserAccountHttpRefresh(document);
        document.clear();
        // Then it remains a distinct immutable DTO with fixed diagnostics.
        expect(pair.userAccountId, 'synthetic/rotating-account');
        expect(pair.accessSessionId, 'synthetic/new-access-session');
        expect(pair.accessToken, 'SYNTHETIC.rotated-access=');
        expect(pair.refreshSessionId, 'synthetic/new-refresh-session');
        expect(pair.refreshToken, 'SYNTHETIC.rotated-refresh==');
        expect('$pair', 'UserAccountHttpWireRefreshPair');
        expect(() => decodeUserAccountHttpLogin(refresh()), _invalidResponse);
        expect(
          () => decodeUserAccountHttpRefresh(_session()),
          _invalidResponse,
        );
      },
    );

    for (final key in refresh().keys) {
      for (final variation in ['missing', 'null', 'wrong-type']) {
        test('refresh rejects $variation $key', () {
          // Given an incomplete or incorrectly typed required refresh field.
          final document = refresh();
          if (variation == 'missing') {
            document.remove(key);
          } else {
            document[key] = variation == 'null' ? null : <String>[];
          }
          // When that root is decoded.
          UserAccountHttpWireRefreshPair action() =>
              decodeUserAccountHttpRefresh(document);
          // Then strict shape validation fails without echoing received data.
          expect(action, _invalidResponse);
        });
      }
    }

    test(
      'refresh rejects mixed flags, extra fields and malformed token syntax',
      () {
        // Given incompatible classification and credential encodings.
        final documents = <Object?>[
          null,
          [],
          'synthetic',
          {...refresh(), 'credential_id': 'synthetic/credential'},
          {...refresh(), 'two_factor_required': true},
          {...refresh(), 'authenticated': false},
          {...refresh(), 'authenticated': 'true'},
          {...refresh(), 'authenticated': 1},
          {...refresh(), 'access_token': 'synthetic token'},
          {...refresh(), 'refresh_token': 'synthetic=interior'},
          {...refresh(), 'access_token': 'synthetic\n'},
          {...refresh(), 'user_account_id': ' '},
          {...refresh(), 'refresh_session_id': 'synthetic\u0000'},
          {'data': refresh()},
        ];
        // When each is decoded through the refresh-only entry point.
        final actions = documents.map(
          (document) =>
              () => decodeUserAccountHttpRefresh(document),
        );
        // Then none can weaken the original seven-key login contract.
        for (final action in actions) {
          expect(action, _invalidResponse);
        }
      },
    );
  });

  group('adopted initial password-login objects', () {
    test('normal login retains every exact opaque identity and token', () {
      // Given a synthetic root normal-login response with significant spaces.
      final document = _session();
      // When the object is decoded.
      final result = decodeUserAccountHttpLogin(document);
      // Then it is a session pair preserving every supplied value exactly.
      expect(result, isA<UserAccountHttpWireSessionPair>());
      final pair = result as UserAccountHttpWireSessionPair;
      expect(pair.userAccountId, ' synthetic/account:α ');
      expect(pair.credentialId, 'synthetic credential');
      expect(pair.accessSessionId, 'synthetic/access-session');
      expect(pair.accessToken, 'SYNTHETIC.access+token/one==');
      expect(pair.refreshSessionId, 'synthetic/refresh-session');
      expect(pair.refreshToken, 'SYNTHETIC_refresh~token-two=');
    });

    test(
      'email challenge remains distinct from authenticated session data',
      () {
        // Given a synthetic root response requiring email verification.
        final document = _challenge();
        // When the object is decoded.
        final result = decodeUserAccountHttpLogin(document);
        // Then only an exact challenge is returned, without a session-pair result.
        expect(result, isA<UserAccountHttpWireChallenge>());
        expect(result, isNot(isA<UserAccountHttpWireSessionPair>()));
        final challenge = result as UserAccountHttpWireChallenge;
        expect(challenge.userAccountId, ' synthetic/account:α ');
        expect(challenge.credentialId, 'synthetic credential');
        expect(challenge.challengeId, ' synthetic/challenge:β ');
        expect(challenge.channel, 'email');
      },
    );

    test('decoding leaves input unchanged and detaches both results', () {
      // Given two mutable synthetic response maps and their original values.
      final sessionDocument = _session();
      final challengeDocument = _challenge();
      final originalSession = Map<String, Object?>.of(sessionDocument);
      final originalChallenge = Map<String, Object?>.of(challengeDocument);
      // When both maps are decoded and the caller later replaces their content.
      final pair = decodeUserAccountHttpLogin(
        sessionDocument,
      ) as UserAccountHttpWireSessionPair;
      final challenge = decodeUserAccountHttpLogin(
        challengeDocument,
      ) as UserAccountHttpWireChallenge;
      // Then decoding itself did not modify either input.
      expect(sessionDocument, originalSession);
      expect(challengeDocument, originalChallenge);
      sessionDocument.updateAll((key, value) => 'replaced');
      challengeDocument.clear();
      // Then caller mutations cannot change any retained DTO field.
      expect(pair.userAccountId, originalSession['user_account_id']);
      expect(pair.credentialId, originalSession['credential_id']);
      expect(pair.accessSessionId, originalSession['access_session_id']);
      expect(pair.accessToken, originalSession['access_token']);
      expect(pair.refreshSessionId, originalSession['refresh_session_id']);
      expect(pair.refreshToken, originalSession['refresh_token']);
      expect(challenge.userAccountId, originalChallenge['user_account_id']);
      expect(challenge.credentialId, originalChallenge['credential_id']);
      expect(challenge.challengeId, originalChallenge['challenge_id']);
      expect(challenge.channel, 'email');
    });

    test('DTO diagnostics contain only their safe type names', () {
      // Given valid synthetic session and challenge objects containing secrets.
      final sessionDocument = _session();
      final challengeDocument = _challenge();
      // When decoded results are rendered for diagnostics.
      final pairText = decodeUserAccountHttpLogin(sessionDocument).toString();
      final challengeText = decodeUserAccountHttpLogin(challengeDocument)
          .toString();
      // Then no identity, token or challenge data appears in those diagnostics.
      expect(pairText, 'UserAccountHttpWireSessionPair');
      expect(challengeText, 'UserAccountHttpWireChallenge');
      for (final value in sessionDocument.values.whereType<String>()) {
        expect(pairText, isNot(contains(value)));
      }
      for (final value in challengeDocument.values.whereType<String>()) {
        expect(challengeText, isNot(contains(value)));
      }
    });

    for (final shape in ['session', 'challenge']) {
      final fixture = shape == 'session' ? _session : _challenge;
      for (final key in fixture().keys) {
        test('$shape rejects missing required $key', () {
          // Given a response missing one required field of the selected shape.
          final document = fixture()..remove(key);
          // When decoding is attempted.
          UserAccountHttpWireLoginResult action() =>
              decodeUserAccountHttpLogin(document);
          // Then incompleteness is a fixed invalid-response failure.
          expect(action, _invalidResponse);
        });
      }

      for (final key in fixture().keys.where(
        (key) => fixture()[key] is String,
      )) {
        for (final value in <Object?>[null, 17, true, <String>[]]) {
          test('$shape rejects non-string $key (${value.runtimeType})', () {
            // Given a required string replaced by null or a different JSON type.
            final document = fixture()..[key] = value;
            // When decoding is attempted.
            UserAccountHttpWireLoginResult action() =>
                decodeUserAccountHttpLogin(document);
            // Then the value is rejected without reflecting its contents.
            expect(action, _invalidResponse);
          });
        }
      }
    }

    test('extra, mixed, enveloped and camelCase login shapes are rejected', () {
      // Given incompatible records alongside otherwise valid synthetic fields.
      final camelCase = _session()
        ..remove('user_account_id')
        ..['userAccountId'] = 'synthetic/account';
      final documents = <Object?>[
        {..._session(), 'extra': 'synthetic-extra'},
        {..._session(), 'error': null},
        {..._session(), 'challenge_id': 'synthetic-challenge'},
        {..._challenge(), 'access_token': 'SYNTHETIC.token'},
        {..._challenge(), 'refresh_session_id': 'synthetic-session'},
        {..._challenge(), 'error': 'synthetic-error'},
        {..._session(), ..._challenge()},
        {'data': _session()},
        {'body': _challenge()},
        camelCase,
      ];
      // When each incompatible root is decoded.
      final actions = documents.map(
        (document) =>
            () => decodeUserAccountHttpLogin(document),
      );
      // Then none is accepted as either supported login result.
      for (final action in actions) {
        expect(action, _invalidResponse);
      }
    });

    test(
      'only exact boolean classification and email challenge are accepted',
      () {
        // Given false normal-login flags, true challenge flags and wrong flag types.
        final documents = <Object?>[
          for (final value in <Object?>[false, null, 'true', 1])
            {..._session(), 'authenticated': value},
          for (final value in <Object?>[true, null, 'false', 0])
            {..._challenge(), 'authenticated': value},
          for (final value in <Object?>[false, null, 'true', 1])
            {..._challenge(), 'two_factor_required': value},
          for (final value in ['', 'sms', 'Email', 'email ', 'email\n'])
            {..._challenge(), 'channel': value},
        ];
        // When each flag/channel variation is decoded.
        final actions = documents.map(
          (document) =>
              () => decodeUserAccountHttpLogin(document),
        );
        // Then all unsupported classifications fail with the safe fixed exception.
        for (final action in actions) {
          expect(action, _invalidResponse);
        }
      },
    );

    for (final (shape, fixture, fields) in [
      (
        'session',
        _session,
        [
          'user_account_id',
          'credential_id',
          'access_session_id',
          'refresh_session_id',
        ],
      ),
      (
        'challenge',
        _challenge,
        ['user_account_id', 'credential_id', 'challenge_id'],
      ),
    ]) {
      for (final field in fields) {
        test('$shape $field accepts exactly 4096 UTF-8 bytes', () {
          // Given an opaque non-UUID identity at the multibyte byte limit.
          final identity = 'é' * 2048;
          final document = fixture()..[field] = identity;
          // When the selected login shape is decoded.
          final result = decodeUserAccountHttpLogin(document);
          // Then the original multibyte string is preserved without conversion.
          final retained = switch (result) {
            UserAccountHttpWireSessionPair() => {
              'user_account_id': result.userAccountId,
              'credential_id': result.credentialId,
              'access_session_id': result.accessSessionId,
              'refresh_session_id': result.refreshSessionId,
            },
            UserAccountHttpWireChallenge() => {
              'user_account_id': result.userAccountId,
              'credential_id': result.credentialId,
              'challenge_id': result.challengeId,
            },
          };
          expect(retained[field], identity);
        });

        test('$shape $field rejects blank, oversized and control values', () {
          // Given blank, byte-oversized and every ASCII C0/DEL identity variant.
          final values = [
            '',
            '   ',
            '\u3000',
            'a' * 4097,
            '${'é' * 2048}a',
            for (var code = 0; code < 32; code++)
              'synthetic${String.fromCharCode(code)}identity',
            'synthetic\u007fidentity',
          ];
          // When the invalid values replace this opaque field.
          final actions = values.map(
            (value) =>
                () => decodeUserAccountHttpLogin(fixture()..[field] = value),
          );
          // Then every value fails without identity text in the diagnostic.
          for (final action in actions) {
            expect(action, _invalidResponse);
          }
        });
      }
    }

    for (final field in ['access_token', 'refresh_token']) {
      test('$field preserves accepted alphabet, padding and endpoint sizes', () {
        // Given synthetic tokens at both limits and the complete allowed alphabet.
        final values = ['a', 'a' * 8192, 'AZaz09._~+/-', 'SYNTHETIC=='];
        // When each token is decoded in the chosen session field.
        final results = values.map(
          (value) =>
              decodeUserAccountHttpLogin(_session()..[field] = value)
                  as UserAccountHttpWireSessionPair,
        );
        // Then accepted tokens retain their exact value, including end padding.
        expect(
          results.map(
            (pair) =>
                field == 'access_token' ? pair.accessToken : pair.refreshToken,
          ),
          values,
        );
      });

      test('$field rejects invalid syntax, trailing newline and overflow', () {
        // Given empty/oversized tokens, whitespace, controls and invalid padding.
        final values = [
          '',
          'a' * 8193,
          '=',
          '==',
          'a=b',
          'a==b=',
          ' a',
          'a ',
          'a b',
          'a\t',
          'a\r',
          'a\n',
          'a\u0000',
          'a\u007f',
          'é',
          'a:b',
          'a%b',
        ];
        // When each invalid token is decoded in the chosen session field.
        final actions = values.map(
          (value) =>
              () => decodeUserAccountHttpLogin(_session()..[field] = value),
        );
        // Then syntax and full-input bounds fail with the fixed safe exception.
        for (final action in actions) {
          expect(action, _invalidResponse);
        }
      });
    }
  });

  group('root object admission shared by both decoders', () {
    test('null, scalar, list and non-string-key roots fail safely', () {
      // Given values that cannot represent a supported string-key JSON object.
      final documents = <Object?>[
        null,
        'SYNTHETIC_PRIVATE_ROOT',
        42,
        true,
        <Object?>[],
        [_session()],
        <Object?, Object?>{1: 'SYNTHETIC_PRIVATE_VALUE'},
        <Object?, Object?>{..._session(), null: 'synthetic'},
        <Object?, Object?>{'id': 'synthetic-account', 1: 'synthetic'},
      ];
      // When each value is submitted to both object decoders.
      final actions = [
        for (final document in documents) ...[
          () => decodeUserAccountHttpLogin(document),
          () => decodeUserAccountHttpAccount(
            document,
            expectedUserAccountId: 'synthetic-account',
          ),
        ],
      ];
      // Then all invalid roots expose exactly the same data-free failure.
      for (final action in actions) {
        expect(action, _invalidResponse);
      }
    });
  });

  group('expected-account projection', () {
    test(
      'only exact root id and authoritative handle enter the projection',
      () {
        // Given an open account record with unrelated principals and secret metadata.
        final document = <String, Object?>{
          'id': ' synthetic/account:α ',
          'handle': ' Synthetic Handle ',
          'owner_id': 'synthetic-public-principal',
          'name': 'synthetic-other-name',
          'email': 'synthetic@example.invalid',
          'login_name': 'synthetic-login',
          'access_token': 'SYNTHETIC.secret',
          'metadata': {'nested': 'synthetic-private-value'},
        };
        final original = Map<String, Object?>.of(document);
        // When the exact login account is projected and the source is later cleared.
        final account = decodeUserAccountHttpAccount(
          document,
          expectedUserAccountId: ' synthetic/account:α ',
        );
        // Then decoding preserves the source and returns only the requested values.
        expect(document, original);
        document.clear();
        expect(account.userAccountId, ' synthetic/account:α ');
        expect(account.displayName, ' Synthetic Handle ');
        expect('$account', isNot(contains('SYNTHETIC.secret')));
        expect('$account', isNot(contains('synthetic-private-value')));
      },
    );

    test('owner, case and surrounding-space similarities cannot replace id', () {
      // Given different account IDs even where the owner equals the expected ID.
      final documents = [
        {'id': 'different-account', 'owner_id': 'synthetic-account'},
        {'owner_id': 'synthetic-account'},
        {'id': 'Synthetic-account'},
        {'id': ' synthetic-account'},
        {'id': 'synthetic-account '},
      ];
      // When each is projected for the exact account expected from login.
      final actions = documents.map(
        (document) =>
            () => decodeUserAccountHttpAccount(
              document,
              expectedUserAccountId: 'synthetic-account',
            ),
      );
      // Then no alternate identity or owner representation binds successfully.
      for (final action in actions) {
        expect(action, _invalidResponse);
      }
    });

    test('missing and null handles have no fallback to labels', () {
      // Given matching IDs with only non-authoritative name/email/login labels.
      final documents = [
        <String, Object?>{
          'id': 'synthetic-account',
          'name': 'synthetic-name',
          'email': 'synthetic@example.invalid',
          'login_name': 'synthetic-login',
        },
        <String, Object?>{
          'id': 'synthetic-account',
          'handle': null,
          'name': 'synthetic-name',
        },
      ];
      // When the records are projected for the exact account.
      final accounts = documents.map(
        (document) => decodeUserAccountHttpAccount(
          document,
          expectedUserAccountId: 'synthetic-account',
        ),
      );
      // Then absent/null handles remain null rather than a derived display name.
      for (final account in accounts) {
        expect(account.userAccountId, 'synthetic-account');
        expect(account.displayName, isNull);
      }
    });

    for (final handle in ['', '   ', ' Synthetic Handle ', 'é' * 2048]) {
      test(
        'valid handle of ${handle.length} code units is retained exactly',
        () {
          // Given an empty, blank, padded or maximum-byte authoritative handle.
          final document = {'id': 'synthetic-account', 'handle': handle};
          // When its account is projected.
          final account = decodeUserAccountHttpAccount(
            document,
            expectedUserAccountId: 'synthetic-account',
          );
          // Then the exact handle is kept without trimming or fallback.
          expect(account.displayName, handle);
        },
      );
    }

    test(
      'account id and expected identity share the exact opaque byte bound',
      () {
        // Given a matching non-UUID identity at the multibyte byte limit.
        final identity = 'é' * 2048;
        final document = {'id': identity};
        // When projected using the same exact expected identity.
        final account = decodeUserAccountHttpAccount(
          document,
          expectedUserAccountId: identity,
        );
        // Then the original opaque identity is preserved.
        expect(account.userAccountId, identity);
        expect(account.displayName, isNull);
      },
    );

    test('malformed account and expected identities are independently rejected', () {
      // Given blank, oversized and ASCII-control identities.
      final identities = [
        '',
        '   ',
        '\u3000',
        'a' * 4097,
        '${'é' * 2048}a',
        for (var code = 0; code < 32; code++)
          'synthetic${String.fromCharCode(code)}account',
        'synthetic\u007faccount',
      ];
      // When each invalid identity appears in the record, expectation or both.
      final actions = [
        for (final identity in identities) ...[
          () => decodeUserAccountHttpAccount({
            'id': identity,
          }, expectedUserAccountId: 'synthetic-account'),
          () => decodeUserAccountHttpAccount({
            'id': 'synthetic-account',
          }, expectedUserAccountId: identity),
          () => decodeUserAccountHttpAccount({
            'id': identity,
          }, expectedUserAccountId: identity),
        ],
      ];
      // Then invalid values fail even when record and expectation are identical.
      for (final action in actions) {
        expect(action, _invalidResponse);
      }
    });

    test('missing, null and non-string account ids fail safely', () {
      // Given account records without a valid string id.
      final documents = <Object?>[
        <String, Object?>{},
        for (final value in <Object?>[null, 23, false, <String>[]])
          {'id': value, 'handle': 'synthetic-handle'},
      ];
      // When projected for a valid expected identity.
      final actions = documents.map(
        (document) =>
            () => decodeUserAccountHttpAccount(
              document,
              expectedUserAccountId: 'synthetic-account',
            ),
      );
      // Then the required account identity cannot be fabricated or coerced.
      for (final action in actions) {
        expect(action, _invalidResponse);
      }
    });

    test('non-string and byte-oversized handles fail safely', () {
      // Given authoritative handles with unsupported types or excessive bytes.
      final handles = <Object?>[
        23,
        true,
        <String>[],
        <String, String>{},
        'a' * 4097,
        '${'é' * 2048}a',
      ];
      // When those handles accompany an otherwise matching account id.
      final actions = handles.map(
        (handle) =>
            () => decodeUserAccountHttpAccount({
              'id': 'synthetic-account',
              'handle': handle,
            }, expectedUserAccountId: 'synthetic-account'),
      );
      // Then malformed display metadata cannot yield an accepted projection.
      for (final action in actions) {
        expect(action, _invalidResponse);
      }
    });

    test('any root error key rejects even an exactly matching account', () {
      // Given error-bearing records, including null/false errors with valid ids.
      final errors = <Object?>[null, false, '', 'SYNTHETIC_PRIVATE_ERROR', {}];
      // When each error value accompanies a matching account and valid handle.
      final actions = errors.map(
        (error) =>
            () => decodeUserAccountHttpAccount({
              'id': 'synthetic-account',
              'handle': 'synthetic',
              'error': error,
            }, expectedUserAccountId: 'synthetic-account'),
      );
      // Then the response is rejected without exposing the error or identity.
      for (final action in actions) {
        expect(action, _invalidResponse);
      }
    });
  });
}
