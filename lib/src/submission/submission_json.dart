import 'dart:collection';

// Internal value/schema vocabulary; this library is intentionally not exported.
String token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError('Expected a safe identity token');
  }
  return value;
}

String descriptive(String value) {
  if (value.trim().isEmpty) throw ArgumentError('Expected nonblank text');
  return value;
}

Map<String, Object?> frozenJson(Map<String, Object?> value) =>
    freeze(value, HashSet<Object>.identity()) as Map<String, Object?>;

Object? freeze(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is! Map && value is! List) {
    throw ArgumentError('Expected finite JSON');
  }
  if (!ancestors.add(value)) throw ArgumentError('Cyclic JSON');
  try {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) throw ArgumentError('Nonstring JSON key');
        result[entry.key as String] = freeze(entry.value, ancestors);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    return List<Object?>.unmodifiable(
      (value as List).map((item) => freeze(item, ancestors)),
    );
  } finally {
    ancestors.remove(value);
  }
}

Object? detach(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: detach(entry.value),
    };
  }
  if (value is List) return value.map(detach).toList();
  return value;
}

bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && deepEquals(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int deepHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, deepHash(entry.value)),
      ),
    );
  }
  if (value is List) return Object.hashAll(value.map(deepHash));
  return value.hashCode;
}

Map<String, Object?> object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a string-keyed object');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?> exact(Object? value, Set<String> keys) {
  final result = object(value);
  if (result.length != keys.length || !result.keys.every(keys.contains)) {
    throw const FormatException('Invalid submission schema keys');
  }
  return result;
}

String string(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

String? nullableString(Object? value) => value == null ? null : string(value);

int integer(Object? value) {
  if (value is! int) throw const FormatException('Expected integer');
  return value;
}

bool boolean(Object? value) {
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

List<Object?> array(Object? value) {
  if (value is! List) throw const FormatException('Expected array');
  return List<Object?>.from(value);
}

T enumeration<T extends Enum>(Object? value, List<T> values) {
  final name = string(value);
  for (final item in values) {
    if (item.name == name) return item;
  }
  throw const FormatException('Invalid enumeration');
}

void version(Map<String, Object?> value) {
  if (integer(value['version']) != 1) {
    throw const FormatException('Unsupported submission version');
  }
}

DateTime time(Object? value) {
  final text = string(value);
  final match = RegExp(
    r'^([+-]?\d{4,6})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
    r'(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(text);
  final parsed = DateTime.tryParse(text);
  if (match == null || parsed == null) {
    throw const FormatException('Expected an explicit-zone ISO time');
  }
  final components = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final zone = match.group(8)!;
  if (zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 23 ||
          int.parse(zone.substring(4, 6)) > 59)) {
    throw const FormatException('Invalid timezone');
  }
  final calendar = DateTime.utc(
    components[0],
    components[1],
    components[2],
    components[3],
    components[4],
    components[5],
  );
  if (!deepEquals(components, [
    calendar.year,
    calendar.month,
    calendar.day,
    calendar.hour,
    calendar.minute,
    calendar.second,
  ])) {
    throw const FormatException('Invalid calendar time');
  }
  return parsed.toUtc();
}

DateTime? nullableTime(Object? value) => value == null ? null : time(value);

T decode<T>(T Function() operation) {
  try {
    return operation();
  } on ArgumentError {
    throw const FormatException('Invalid submission value');
  }
}
