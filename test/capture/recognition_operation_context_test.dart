import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('immutable generic operation context', () {
    test('OC1 caller collections and detached wire cannot change exact intent', () {
      // Given mutable ordered kinds and nested finite JSON with exact whitespace.
      final kinds = [' opaque/first ', 'second'];
      final nested = <String, Object?>{'values': <Object?>[null, true, 1, 1.5, ' raw ']};
      final extensions = <String, Object?>{'unknown': nested};
      final context = RecognitionOperationContext(sourceRole: ' opaque/role ',
        targetKinds: kinds, instructions: ' exact\n instructions ', extensions: extensions);
      // When caller collections and returned wire snapshots are mutated.
      kinds.clear(); (nested['values'] as List).clear(); extensions.clear();
      final wire = context.toJson();
      (wire['targetKinds'] as List).clear();
      (((wire['extensions'] as Map)['unknown'] as Map)['values'] as List).clear();
      // Then frozen exact values and a fresh detached schema1 snapshot survive.
      expect(context.sourceRole, ' opaque/role ');
      expect(context.targetKinds, [' opaque/first ', 'second']);
      expect(context.instructions, ' exact\n instructions ');
      expect(context.extensions, {'unknown': {'values': [null, true, 1, 1.5, ' raw ']}});
      expect(context.toJson(), {
        'schemaVersion': 1, 'sourceRole': ' opaque/role ',
        'targetKinds': [' opaque/first ', 'second'], 'instructions': ' exact\n instructions ',
        'extensions': {'unknown': {'values': [null, true, 1, 1.5, ' raw ']}},
      });
      expect(() => context.targetKinds.clear(), throwsUnsupportedError);
      expect(() => context.extensions['other'] = 1, throwsUnsupportedError);
      expect(() => (context.extensions['unknown'] as Map)['other'] = 1, throwsUnsupportedError);
      expect(() => ((context.extensions['unknown'] as Map)['values'] as List).clear(), throwsUnsupportedError);
      expect(RecognitionOperationContext.extensionKey, 'recognitionOperationContext');
    });

    test('OC1 equality and hash include exact role ordered kinds instructions and JSON', () {
      // Given equal nested metadata in different map orders and distinct fields.
      final context = _context(extensions: {'a': [1, true], 'b': null});
      final equal = _context(extensions: {'b': null, 'a': [1, true]});
      final different = [
        _context(role: 'other'), _context(kinds: ['second', 'first']),
        _context(instructions: 'other'), _context(extensions: {'a': [2, true], 'b': null}),
      ];
      // When schema1 is decoded and every field variant is compared.
      final decoded = RecognitionOperationContext.fromJson(context.toJson());
      // Then equality and hashes preserve all value fields and kind order.
      expect(equal, context); expect(equal.hashCode, context.hashCode);
      expect(decoded, context); expect(decoded.hashCode, context.hashCode);
      expect(context, isNot('context'));
      for (final variant in different) {
        // Given this changed value field from the finite equality matrix.
        // When the immutable contexts are compared.
        // Then the change is observable in value equality.
        expect(variant, isNot(context));
      }
      expect(_context().extensions, isEmpty);
    });

    test('OC1 invalid constructor values reject before any operation', () {
      // Given blank or duplicate intent and invalid finite-JSON boundaries.
      final cyclicMap = <String, Object?>{}; cyclicMap['self'] = cyclicMap;
      final cyclicList = <Object?>[]; cyclicList.add(cyclicList);
      final constructors = <void Function()>[
        () => _context(role: ' \n'), () => _context(instructions: '\t'),
        () => _context(kinds: []), () => _context(kinds: ['first', 'first']),
        () => _context(kinds: ['first', ' ']),
        for (final invalid in <Object?>[
          double.infinity, double.negativeInfinity, double.nan, Object(),
          <Object?, Object?>{1: 'non-string key'}, cyclicMap, cyclicList,
        ]) () => _context(extensions: {'invalid': invalid}),
      ];
      // When each malformed value is admitted by the public constructor.
      for (final construct in constructors) {
        // Given this concrete invalid intent or extension value.
        // When construction attempts to freeze it.
        // Then the value contract rejects with ArgumentError.
        expect(construct, throwsArgumentError);
      }
    });

    test('OC1 malformed wire keys types versions and values reject strictly', () {
      // Given exact schema1 JSON and finite malformed namespace variants.
      final valid = _context().toJson();
      final cyclicMap = <String, Object?>{}; cyclicMap['self'] = cyclicMap;
      final cyclicList = <Object?>[]; cyclicList.add(cyclicList);
      final malformed = <Object?>[
        null, [], 'context', {...valid, 'extra': null},
        for (final key in valid.keys) {...valid}..remove(key),
        for (final version in <Object?>[null, true, 1.0, 2, '1'])
          {...valid, 'schemaVersion': version},
        for (final role in <Object?>[null, 1, '', ' \n']) {...valid, 'sourceRole': role},
        for (final instructions in <Object?>[null, false, '', '\t'])
          {...valid, 'instructions': instructions},
        for (final kinds in <Object?>[null, {}, 'first', [], ['first', 1], ['first', 'first'], [' ']])
          {...valid, 'targetKinds': kinds},
        for (final extensions in <Object?>[
          null, [], <Object?, Object?>{1: true}, {'bad': Object()},
          {'bad': double.infinity}, {'bad': double.nan}, cyclicMap, {'bad': cyclicList},
        ]) {...valid, 'extensions': extensions},
      ];
      // When every malformed value is decoded through the public wire API.
      for (final wire in malformed) {
        // Given this malformed schema1 variant, including cycles and non-string keys.
        // When strict context decoding admits it.
        // Then errors are FormatException without normalization or partial salvage.
        expect(() => RecognitionOperationContext.fromJson(wire), throwsFormatException);
      }
    });
  });
}

RecognitionOperationContext _context({String role = 'opaque-role',
  Iterable<String> kinds = const ['first', 'second'], String instructions = 'exact instructions',
  Map<String, Object?> extensions = const {}}) => RecognitionOperationContext(
  sourceRole: role, targetKinds: kinds, instructions: instructions, extensions: extensions,
);
