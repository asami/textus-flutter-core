import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('typed families and immutable context', () {
    test('known families decode typed payloads with structural equality', () {
      // Given a fresh locale, supplied arm and matching flow correlation.
      final original = context();
      // When the public context codec roundtrips.
      final decoded = PresentationContext.fromJson(original.toJson());
      // Then all known payloads are typed and context/family equality is structural.
      expect(decoded, original);
      expect(decoded.hashCode, original.hashCode);
      expect(decoded.families[0].payload, isA<LocalePresentationPayload>());
      expect(
        decoded.families[1].payload,
        isA<SuppliedArmPresentationPayload>(),
      );
      expect(
        decoded.families[2].payload,
        isA<CorrelationPresentationPayload>(),
      );
      expect(decoded.families, original.families);
    });

    test('context payload collections and policy inputs are defensively immutable', () {
      // Given mutable nested JSON, families and policy input collections.
      final nested = <Object?>['value'];
      final map = <String, Object?>{'nested': nested};
      final payload = OpaquePresentationPayload(map);
      final families = <PresentationContextFamily>[extension(payload: payload)];
      final original = context(families: families);
      final producers = <String>{'producer'};
      final extensions = <PresentationExtensionSupport>[support()];
      final admissionPolicy = PresentationContextPolicy(
        allowedProducerIds: producers,
        optionalExtensions: extensions,
      );
      // When external collections change after construction.
      nested.add('later');
      map['extra'] = true;
      families.clear();
      producers.clear();
      extensions.clear();
      final admitted = admit(admissionPolicy, original);
      // Then stored values, admission inputs and nested views remain immutable.
      expect((payload.values['nested'] as List), ['value']);
      expect(original.families.length, 1);
      expect(admitted.context, original);
      expect(
        () => (payload.values['nested'] as List).add('x'),
        throwsUnsupportedError,
      );
      expect(() => original.families.clear(), throwsUnsupportedError);
      expect(() => admitted.diagnostics.clear(), throwsUnsupportedError);
      expect(
        () => admissionPolicy.allowedProducerIds.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('context admission and structural boundaries', () {
    test(
      'source component flow and explicit UTC clock are admission boundaries',
      () {
        // Given one fixed flow and its exact allowed producer.
        final original = context();
        final policy = policyFor();
        // When expected source/component/flow or clock differs.
        final actions = [
          () => policy.admit(
            original,
            sourceId: 'other',
            componentId: 'component',
            flowId: 'flow',
            nowUtc: instant(),
          ),
          () => policy.admit(
            original,
            sourceId: 'source',
            componentId: 'other',
            flowId: 'flow',
            nowUtc: instant(),
          ),
          () => policy.admit(
            original,
            sourceId: 'source',
            componentId: 'component',
            flowId: 'other',
            nowUtc: instant(),
          ),
          () => policy.admit(
            original,
            sourceId: 'source',
            componentId: 'component',
            flowId: 'flow',
            nowUtc: DateTime(2026, 10, 2),
          ),
        ];
        // Then each incompatibility is explicit and the previous context is intact.
        for (final action in actions) {
          expect(action, throwsA(isA<PresentationContextException>()));
        }
        expect(original.flowId, 'flow');
      },
    );

    test('supplied arm must be required and correlation must match enclosing flow', () {
      // Given candidate arm/correlation wire with invalid required/flow flags.
      final optionalArm = arm().toJson()..['required'] = false;
      final wrongFlow = context().toJson();
      final families = wrongFlow['families'] as List;
      ((families[2] as Map<String, Object?>)['payload']
              as Map<String, Object?>)['flowReference'] =
          'another';
      // When these malformed known families decode.
      final actions = [
        () => PresentationContextFamily.fromJson(optionalArm),
        () => PresentationContext.fromJson(wrongFlow),
      ];
      // Then decoding rejects them before admission can omit anything.
      for (final action in actions) {
        expect(action, throwsFormatException);
      }
    });

    test('malformed known payload never becomes opaque or expires away', () {
      // Given expired optional locale v1 with malformed or extra payload members.
      final invalid = locale(expiresAt: instant()).toJson();
      invalid['payload'] = {'localeTag': 'ja_JP'};
      final extra = locale().toJson();
      extra['payload'] = {'localeTag': 'ja-JP', 'extra': true};
      final missing = locale().toJson()..['payload'] = <String, Object?>{};
      // When known v1 decoding occurs before expiry/support filtering.
      final actions = [
        () => PresentationContextFamily.fromJson(invalid),
        () => PresentationContextFamily.fromJson(extra),
        () => PresentationContextFamily.fromJson(missing),
      ];
      // Then malformed known content rejects at structural decoding.
      for (final action in actions) {
        expect(action, throwsFormatException);
      }
    });

    test('optional unsupported known versions decode opaque then omit diagnostically', () {
      // Given an optional future locale version with structurally valid JSON.
      final future = PresentationContextFamily(
        namespace: 'textus.presentation.locale',
        version: 2,
        producerId: 'producer',
        isRequired: false,
        expiresAt: null,
        payload: OpaquePresentationPayload({'future': true}),
      );
      final original = context(families: [future]);
      // When the public codec and fixed support policy admit it.
      final decoded = PresentationContext.fromJson(original.toJson());
      final admission = admit(policyFor(), decoded);
      // Then structural decoding is opaque but carriage is omitted with a diagnostic.
      expect(decoded.families.single.payload, isA<OpaquePresentationPayload>());
      expect(admission.context.families, isEmpty);
      expect(admission.diagnostics.single.code, 'unsupported-version');
    });

    test(
      'required known unsupported version is rejected by admission policy',
      () {
        // Given a structurally valid required future locale family.
        final future = PresentationContextFamily(
          namespace: 'textus.presentation.locale',
          version: 2,
          producerId: 'producer',
          isRequired: true,
          expiresAt: null,
          payload: OpaquePresentationPayload({'future': true}),
        );
        final decoded = PresentationContext.fromJson(
          context(families: [future]).toJson(),
        );
        // When fixed known-v1 support checks the required future version.
        PresentationContextAdmission action() => admit(policyFor(), decoded);
        // Then required unsupported content rejects even with optional extension support.
        expect(
          action,
          throwsA(
            isA<PresentationContextException>().having(
              (error) => error.code,
              'code',
              'unsupported-version',
            ),
          ),
        );
        expect(
          () => admit(
            policyFor(
              extensions: [
                PresentationExtensionSupport(
                  namespace: 'textus.presentation.locale',
                  version: 2,
                  producerId: 'producer',
                ),
              ],
            ),
            decoded,
          ),
          throwsA(isA<PresentationContextException>()),
        );
      },
    );
    test('producer allowlist is exact even for optional omitted families', () {
      // Given optional known and unknown families from an unallowed producer.
      final wires = [locale().toJson(), extension().toJson()];
      for (final wire in wires) {
        wire['producerId'] = 'producer ';
        final original = context(
          families: [PresentationContextFamily.fromJson(wire)],
        );
        // When policy checks exact producer identity.
        PresentationContextAdmission action() => admit(policyFor(), original);
        // Then whitespace is preserved and the unallowed producer rejects.
        expect(
          action,
          throwsA(
            isA<PresentationContextException>().having(
              (error) => error.code,
              'code',
              'producer-not-allowed',
            ),
          ),
        );
      }
    });

    test('expiry edge omits optional and rejects required at injected instant', () {
      // Given optional expiry exactly now and required arm expiry exactly now.
      final optional = context(families: [locale(expiresAt: instant())]);
      final required = context(families: [arm(expiresAt: instant())]);
      // When the injected clock reaches that instant.
      final omitted = admit(policyFor(), optional);
      PresentationContextAdmission reject() => admit(policyFor(), required);
      // Then optional omission is diagnosed and required expiry blocks.
      expect(omitted.context.families, isEmpty);
      expect(omitted.diagnostics.single.code, 'expired');
      expect(reject, throwsA(isA<PresentationContextException>()));
      // Given expiry one microsecond after now.
      final future = context(
        families: [
          locale(expiresAt: instant().add(const Duration(microseconds: 1))),
        ],
      );
      // When admitted at the same injected instant.
      final retained = admit(policyFor(), future);
      // Then an unexpired family remains present.
      expect(retained.context.families.length, 1);
    });

    test('unknown optional extension needs exact support and required unknown rejects', () {
      // Given bounded optional hints and required unknown hints.
      final original = context(families: [extension()]);
      final required = context(families: [extension(required: true)]);
      // When admitted with absent, exact and mismatching extension support.
      final omitted = admit(policyFor(), original);
      final retained = admit(policyFor(extensions: [support()]), original);
      final mismatch = admit(
        policyFor(
          extensions: [
            PresentationExtensionSupport(
              namespace: 'neutral.hints',
              version: 2,
              producerId: 'producer',
            ),
          ],
        ),
        original,
      );
      // Then only exact optional support carries through and required unknown rejects.
      expect(omitted.diagnostics.single.code, 'unknown-family');
      expect(retained.context, original);
      expect(mismatch.context.families, isEmpty);
      expect(
        () => admit(policyFor(extensions: [support()]), required),
        throwsA(isA<PresentationContextException>()),
      );
    });

    test('all families obey count size depth finite JSON and unique namespace bounds', () {
      // Given exact boundary-size/depth payloads and several excess/invalid inputs.
      final exactpayload = {'x': 'a' * 4088};
      final depthpayload = {
        'x': {
          'y': [
            {'z': true},
          ],
        },
      };
      final actions = [
        () => OpaquePresentationPayload({'x': 'a' * 4089}),
        () => OpaquePresentationPayload({'x': '界' * 1400}),
        () => OpaquePresentationPayload({
          'x': {
            'y': [
              {'z': []},
            ],
          },
        }),
        () => OpaquePresentationPayload({'x': DateTime.utc(2026)}),
        () => OpaquePresentationPayload({'x': double.nan}),
        () => OpaquePresentationPayload({
          'x': {1: 'invalid key'},
        }),
        () => context(families: [locale(), locale()]),
        () => context(
          families: List.generate(
            9,
            (index) => extension(namespace: 'neutral.$index'),
          ),
        ),
        () => SuppliedArmPresentationPayload(
          namespace: 'n',
          presentationSet: 's',
          armId: 'a',
          definitionVersion: 1,
          assignmentReference: 'a' * 4096,
        ),
        () => PresentationContextFamily.fromJson({
          ...extension().toJson(),
          'payload': {'x': 'a' * 4096},
        }),
      ];
      // When exact boundary-size/depth payloads are constructed.
      final exact = OpaquePresentationPayload(exactpayload);
      final depth = OpaquePresentationPayload(depthpayload);
      // Then exact limits work.
      expect(utf8.encode(jsonEncode(exact.toJson())).length, 4096);
      expect(depth.toJson()['x'], isA<Map>());
      for (final action in actions) {
        Object? observedfailure;
        // When invalid constructors or decoder paths check limits before omission.
        try {
          action();
        } catch (error) {
          observedfailure = error;
        }
        // Then every excess/non-JSON case rejects.
        expect(observedfailure, isA<FormatException>());
      }
    });

    test('closed context family and payload identity shapes reject malformed versions', () {
      // Given closed context/family shapes with extra keys, missing keys and bad versions.
      final actions = [
        () => PresentationContext.fromJson({
          ...context().toJson(),
          'schema': 'wrong',
        }),
        () => PresentationContext.fromJson({
          ...context().toJson(),
          'security': {},
        }),
        () => PresentationContextFamily.fromJson({
          ...locale().toJson(),
          'version': 1.0,
        }),
        () => PresentationContextFamily.fromJson({
          ...locale().toJson(),
          'version': 0,
        }),
        () => PresentationContextFamily.fromJson(
          {...locale().toJson()}..remove('expiresAt'),
        ),
        () => PresentationContextFamily.fromJson({
          ...locale().toJson(),
          'expiresAt': '2026-02-30T00:00:00Z',
        }),
        () => PresentationContextFamily.fromJson({
          ...arm().toJson(),
          'payload': {'namespace': 'n'},
        }),
      ];
      for (final action in actions) {
        Object? observedfailure;
        // When structural decoding processes these objects.
        try {
          action();
        } catch (error) {
          observedfailure = error;
        }
        // Then no malformed identity or runtime/security member enters context.
        expect(observedfailure, isA<FormatException>());
      }
    });
  });

  group('response continuation and replacement', () {
    test('producer may replace only correlation attempt while preserving arm and locale', () {
      // Given a fixed locale/arm/correlation flow and a new producer attempt.
      final previous = context();
      final received = context(attempt: 'attempt-2');
      // When response replacement policy admits that response.
      final admitted = policyFor().admitResponse(
        previous,
        received,
        nowUtc: instant(),
      );
      // Then attempt changes while fixed family payloads remain structurally identical.
      expect(
        (admitted.context.families[2].payload as CorrelationPresentationPayload)
            .attemptReference,
        'attempt-2',
      );
      expect(admitted.context.families.take(2), previous.families.take(2));
      expect(
        (previous.families[2].payload as CorrelationPresentationPayload)
            .attemptReference,
        'attempt-1',
      );
    });

    test('incompatible arm locale producer lifetime and omission preserve original', () {
      // Given a fixed flow and various incompatible response family updates.
      final previous = context();
      final producerWire = copy(previous.toJson());
      for (final family in producerWire['families'] as List) {
        (family as Map<String, Object?>)['producerId'] = 'other';
      }
      final changedProducer = PresentationContext.fromJson(producerWire);
      final incompatible = [
        context(armId: 'B'),
        context(localeTag: 'en-US'),
        context(families: [locale(), correlation()]),
        context(families: [arm(), correlation()]),
        context(
          families: [
            locale(),
            arm(expiresAt: instant().add(const Duration(days: 1))),
            correlation(),
          ],
        ),
        changedProducer,
      ];
      final policy = PresentationContextPolicy(
        allowedProducerIds: {'producer', 'other'},
      );
      for (final received in incompatible) {
        // When pure response admission detects the incompatible update.
        PresentationContextAdmission action() =>
            policy.admitResponse(previous, received, nowUtc: instant());
        // Then it throws without replacing the previous family/selection data.
        expect(action, throwsA(isA<PresentationContextException>()));
        expect(
          (previous.families[1].payload as SuppliedArmPresentationPayload)
              .armId,
          'A',
        );
        expect(
          (previous.families[0].payload as LocalePresentationPayload).localeTag,
          'ja-JP',
        );
      }
    });

    test('optional expiry or filtered unsupported family permits diagnosed omission', () {
      // Given an optional locale that has expired and an unexpired supported locale.
      final expired = context(families: [locale(expiresAt: instant())]);
      final supported = context(families: [locale()]);
      final empty = context(families: []);
      final future = context(
        families: [
          PresentationContextFamily(
            namespace: 'textus.presentation.locale',
            version: 2,
            producerId: 'producer',
            isRequired: false,
            expiresAt: null,
            payload: OpaquePresentationPayload({'future': true}),
          ),
        ],
      );
      // When previous expiry or received unsupported filtering explains omission.
      final expiry = policyFor().admitResponse(
        expired,
        empty,
        nowUtc: instant(),
      );
      final unsupported = policyFor().admitResponse(
        supported,
        future,
        nowUtc: instant(),
      );
      // Then omission is permitted only for these optional cases.
      expect(expiry.context.families, isEmpty);
      expect(unsupported.context.families, isEmpty);
      expect(unsupported.diagnostics.single.code, 'unsupported-version');
      expect(
        () => policyFor().admitResponse(supported, empty, nowUtc: instant()),
        throwsA(isA<PresentationContextException>()),
      );
    });

    test('optional extension replaces wholesale without deep merge', () {
      // Given a supported optional extension with two keys and a new bounded payload.
      final previous = context(
        families: [
          extension(
            payload: OpaquePresentationPayload({'keep': 1, 'remove': true}),
          ),
        ],
      );
      final received = context(
        families: [
          extension(payload: OpaquePresentationPayload({'keep': 2})),
        ],
      );
      final policy = policyFor(extensions: [support()]);
      // When response admission replaces the opaque payload.
      final admitted = policy.admitResponse(
        previous,
        received,
        nowUtc: instant(),
      );
      // Then old keys are absent, previous data is intact and structural map order is irrelevant.
      expect(
        (admitted.context.families.single.payload as OpaquePresentationPayload)
            .values,
        {'keep': 2},
      );
      expect(
        (previous.families.single.payload as OpaquePresentationPayload).values,
        {'keep': 1, 'remove': true},
      );
      expect(
        OpaquePresentationPayload({'a': 1, 'b': 2}),
        OpaquePresentationPayload({'b': 2, 'a': 1}),
      );
      expect(
        OpaquePresentationPayload({'a': 1, 'b': 2}).hashCode,
        OpaquePresentationPayload({'b': 2, 'a': 1}).hashCode,
      );
    });

    test(
      'extension replacement cannot change identity lifetime or exceed bounds',
      () {
        // Given one supported optional extension and incompatible replacement metadata.
        final previous = context(families: [extension()]);
        final version = context(families: [extension(version: 2)]);
        final expiry = context(
          families: [
            extension(expiresAt: instant().add(const Duration(days: 1))),
          ],
        );
        final producer = context(families: [extension(producer: 'other')]);
        final policy = PresentationContextPolicy(
          allowedProducerIds: {'producer', 'other'},
          optionalExtensions: [
            support(),
            PresentationExtensionSupport(
              namespace: 'neutral.hints',
              version: 2,
              producerId: 'producer',
            ),
            PresentationExtensionSupport(
              namespace: 'neutral.hints',
              version: 1,
              producerId: 'other',
            ),
          ],
        );
        // When replacing with changed version, producer or expiry.
        final actions = [
          () => policy.admitResponse(previous, version, nowUtc: instant()),
          () => policy.admitResponse(previous, expiry, nowUtc: instant()),
          () => policy.admitResponse(previous, producer, nowUtc: instant()),
          () =>
              extension(payload: OpaquePresentationPayload({'x': 'a' * 4096})),
        ];
        // Then incompatible or oversized replacement cannot overwrite previous context.
        for (final action in actions.take(3)) {
          expect(action, throwsA(isA<PresentationContextException>()));
        }
        expect(actions.last, throwsFormatException);
        expect(previous.families.single, extension());
      },
    );

    test('no new family can appear mid-flow even if optional would be filtered', () {
      // Given a neutral flow with no supplied arm or extension.
      final previous = context(families: [locale(), correlation()]);
      final candidates = [
        context(),
        context(families: [locale(), correlation(), extension()]),
      ];
      // When responses introduce a required arm or unknown optional family.
      final actions = candidates.map(
        (received) =>
            () => policyFor().admitResponse(
              previous,
              received,
              nowUtc: instant(),
            ),
      );
      // Then both new-family updates reject and neutral context remains fixed.
      for (final action in actions) {
        expect(action, throwsA(isA<PresentationContextException>()));
      }
      expect(previous.families.length, 2);
    });
  });
}

DateTime instant() => DateTime.utc(2026, 10, 2);
PresentationContextPolicy policyFor({
  List<PresentationExtensionSupport> extensions = const [],
}) => PresentationContextPolicy(
  allowedProducerIds: {'producer'},
  optionalExtensions: extensions,
);
PresentationContextAdmission admit(
  PresentationContextPolicy policy,
  PresentationContext value,
) => policy.admit(
  value,
  sourceId: 'source',
  componentId: 'component',
  flowId: 'flow',
  nowUtc: instant(),
);
PresentationContext context({
  List<PresentationContextFamily>? families,
  String localeTag = 'ja-JP',
  String armId = 'A',
  String attempt = 'attempt-1',
}) => PresentationContext(
  flowId: 'flow',
  sourceId: 'source',
  componentId: 'component',
  families:
      families ??
      [locale(tag: localeTag), arm(id: armId), correlation(attempt: attempt)],
);
PresentationContextFamily locale({String tag = 'ja-JP', DateTime? expiresAt}) =>
    PresentationContextFamily(
      namespace: 'textus.presentation.locale',
      version: 1,
      producerId: 'producer',
      isRequired: false,
      expiresAt: expiresAt,
      payload: LocalePresentationPayload(localeTag: tag),
    );
PresentationContextFamily arm({String id = 'A', DateTime? expiresAt}) =>
    PresentationContextFamily(
      namespace: 'textus.presentation.arm',
      version: 1,
      producerId: 'producer',
      isRequired: true,
      expiresAt: expiresAt,
      payload: SuppliedArmPresentationPayload(
        namespace: 'neutral',
        presentationSet: 'set',
        armId: id,
        definitionVersion: 1,
        assignmentReference: 'assignment',
      ),
    );
PresentationContextFamily correlation({String attempt = 'attempt-1'}) =>
    PresentationContextFamily(
      namespace: 'textus.presentation.correlation',
      version: 1,
      producerId: 'producer',
      isRequired: false,
      expiresAt: null,
      payload: CorrelationPresentationPayload(
        flowReference: 'flow',
        attemptReference: attempt,
      ),
    );
PresentationContextFamily extension({
  String namespace = 'neutral.hints',
  int version = 1,
  String producer = 'producer',
  bool required = false,
  DateTime? expiresAt,
  OpaquePresentationPayload? payload,
}) => PresentationContextFamily(
  namespace: namespace,
  version: version,
  producerId: producer,
  isRequired: required,
  expiresAt: expiresAt,
  payload: payload ?? OpaquePresentationPayload({'density': 'comfortable'}),
);
PresentationExtensionSupport support() => PresentationExtensionSupport(
  namespace: 'neutral.hints',
  version: 1,
  producerId: 'producer',
);
Map<String, Object?> copy(Map<String, Object?> json) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(json)) as Map);
