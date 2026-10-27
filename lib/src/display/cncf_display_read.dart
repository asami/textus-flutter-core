import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A redacted read failure; payloads, URIs and credentials are never reflected.
final class CncfDisplayReadException implements Exception {
  const CncfDisplayReadException(this.code, {this.statusCode});
  final String code;
  final int? statusCode;
  @override
  String toString() => 'CncfDisplayReadException($code)';
}

/// Caller-selected trusted source/definition metadata, never learned from HTTP.
final class CncfDisplayReadProfile {
  CncfDisplayReadProfile({
    required this.componentId,
    required this.resourceType,
    required this.listScreenId,
    required this.detailScreenId,
    required Map<String, Object?> semanticContract,
    required Map<String, Object?> provenance,
    required this.definitionRevision,
  }) : semanticContract = _freeze(semanticContract) as Map<String, Object?>,
       provenance = _freeze(provenance) as Map<String, Object?> {
    for (final id in [
      componentId,
      resourceType,
      listScreenId,
      detailScreenId,
      definitionRevision,
    ]) {
      _id(id);
    }
  }
  final String componentId;
  final String resourceType;
  final String listScreenId;
  final String detailScreenId;
  final Map<String, Object?> semanticContract;
  final Map<String, Object?> provenance;
  final String definitionRevision;
}

/// An exact CNCF resource observation. Long revisions remain decimal strings.
final class CncfDisplayResource {
  const CncfDisplayResource._(this.entityId, this.revision, this.fields);
  final String entityId;
  final String revision;

  /// Original ordered field values. No inverse semantic update is inferred.
  final List<Map<String, Object?>> fields;

  String text(String id) {
    final selected = fields.where((field) => field['id'] == id);
    if (selected.length != 1) return '';
    final value = selected.single['value'] as Map<String, Object?>;
    return value['type'] == 'text' ? value['text']! as String : '';
  }
}

/// Formal CNCF read payload, separate from the development-only prototype.
///
/// The complete admitted wire is immutable. Optional snapshot and context stay
/// absent when omitted; neither is manufactured from definition/resource IDs.
final class CncfDisplayRead {
  CncfDisplayRead._(this.wire, this.resources);
  final Map<String, Object?> wire;
  final List<CncfDisplayResource> resources;
  Map<String, Object?> get model => wire['model']! as Map<String, Object?>;
  Map<String, Object?>? get presentationContext =>
      wire.containsKey('presentationContext')
      ? _context(wire['presentationContext'])
      : null;
  String? get snapshotReference =>
      (model['snapshot'] as Map<String, Object?>?)?['reference'] as String?;

  /// Decodes the selected server contract; mutations need their own descriptor.
  static CncfDisplayRead decode(
    Map<String, Object?> input,
    CncfDisplayReadProfile profile, {
    required bool detail,
    String? expectedResourceId,
  }) {
    final wire = _object(_freeze(input));
    _keys(
      wire,
      {
        'schema',
        'version',
        'componentId',
        'resourceType',
        'abi',
        'semanticContract',
        'provenance',
        'definition',
        'model',
      },
      optional: {'presentationContext'},
    );
    if (wire['schema'] != 'cncf.display-model.v1' ||
        wire['version'] != 1 ||
        wire['version'] is! int) {
      _fail('protocolIncompatible');
    }
    if (wire['componentId'] != profile.componentId ||
        wire['resourceType'] != profile.resourceType) {
      _fail('sourceMismatch');
    }
    if (!_equal(wire['abi'], {
          'identity': 'cncf.logical-ui-generated.v1',
          'version': 1,
        }) ||
        !_equal(wire['semanticContract'], profile.semanticContract) ||
        !_equal(wire['provenance'], profile.provenance)) {
      _fail('metadataMismatch');
    }
    final screen = detail ? profile.detailScreenId : profile.listScreenId;
    if (!_equal(wire['definition'], {
      'screenId': screen,
      'revision': profile.definitionRevision,
    })) {
      _fail('definitionMismatch');
    }
    final model = _object(wire['model']);
    _keys(
      model,
      detail
          ? {'type', 'screenId', 'title', 'resource', 'sections', 'actions'}
          : {'type', 'screenId', 'title', 'items', 'detailTarget', 'actions'},
      optional: detail ? {} : {'snapshot'},
    );
    if (model['type'] != (detail ? 'detail' : 'list') ||
        model['screenId'] != screen) {
      _fail('modelMismatch');
    }
    _text(model['title']);
    _actions(model['actions']);
    final resources = <CncfDisplayResource>[];
    if (detail) {
      final fields = <Map<String, Object?>>[];
      final sectionIds = <String>{};
      for (final item in _array(model['sections'])) {
        final section = _object(item);
        _keys(section, {'id', 'fields'}, optional: {'title'});
        if (!sectionIds.add(_id(section['id']))) _fail('duplicateSection');
        if (section.containsKey('title')) _text(section['title']);
        fields.addAll(_fields(section['fields']));
      }
      final resource = _resource(model['resource'], fields);
      if (resource.entityId != expectedResourceId) _fail('resourceMismatch');
      resources.add(resource);
    } else {
      if (!_equal(model['detailTarget'], {
        'screenId': profile.detailScreenId,
      })) {
        _fail('definitionMismatch');
      }
      if (model.containsKey('snapshot')) {
        final snapshot = _object(model['snapshot']);
        _keys(snapshot, {'reference'});
        _id(snapshot['reference']);
      }
      final ids = <String>{};
      for (final item in _array(model['items'])) {
        final row = _object(item);
        _keys(row, {'resource', 'fields', 'actions'});
        _actions(row['actions']);
        final resource = _resource(row['resource'], _fields(row['fields']));
        if (!ids.add(resource.entityId)) _fail('duplicateResource');
        resources.add(resource);
      }
    }
    if (wire.containsKey('presentationContext')) {
      _context(wire['presentationContext']);
    }
    return CncfDisplayRead._(wire, List.unmodifiable(resources));
  }
}

/// Authenticated read-only CNCF transport. No automatic retries or redirects.
///
/// Client ownership stays with the caller. HTTPS is mandatory except an explicit
/// loopback development target; token lookup happens per request and is ephemeral.
final class CncfDisplayReadClient {
  factory CncfDisplayReadClient.standard({
    required CncfDisplayReadProfile profile,
    required Uri endpoint,
    required Future<String?> Function() bearerToken,
  }) {
    final client = http.Client();
    try {
      return CncfDisplayReadClient(
        profile: profile,
        endpoint: endpoint,
        client: client,
        bearerToken: bearerToken,
      ).._ownsClient = true;
    } catch (_) {
      client.close();
      rethrow;
    }
  }
  CncfDisplayReadClient({
    required this.profile,
    required this.endpoint,
    required http.Client client,
    required Future<String?> Function() bearerToken,
    this.timeout = const Duration(seconds: 20),
    this.allowLoopbackHttp = false,
    // Public callback/client names are stable; their ownership stays private.
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _bearerToken = bearerToken {
    final local =
        allowLoopbackHttp &&
        endpoint.scheme == 'http' &&
        (endpoint.host == '127.0.0.1' || endpoint.host == '::1');
    if ((!local && endpoint.scheme != 'https') ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        !endpoint.path.endsWith('/') ||
        timeout <= Duration.zero) {
      throw ArgumentError('Invalid Display endpoint or timeout');
    }
  }
  final CncfDisplayReadProfile profile;
  final Uri endpoint;
  final Duration timeout;
  final bool allowLoopbackHttp;
  final http.Client _client;
  final Future<String?> Function() _bearerToken;
  Map<String, Object?>? _context;
  int _generation = 0;
  bool _closed = false;
  bool _ownsClient = false;
  Completer<void>? _activeAbort;

  Future<CncfDisplayRead> query() => _read(false, null);
  Future<CncfDisplayRead> read(String resourceId) {
    _id(resourceId);
    return _read(true, resourceId);
  }

  /// Retires this flow without closing the borrowed HTTP client.
  void dispose() {
    _closed = true;
    _context = null;
    _generation++;
    final abort = _activeAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    if (_ownsClient) _client.close();
  }

  Future<CncfDisplayRead> _read(bool detail, String? resourceId) async {
    if (_closed) _fail('disposed');
    final generation = ++_generation;
    final previous = _activeAbort;
    if (previous != null && !previous.isCompleted) previous.complete();
    final abort = Completer<void>();
    _activeAbort = abort;
    var retired = false;
    StreamSubscription<List<int>>? bodySubscription;
    void check() {
      if (retired || _closed || generation != _generation) _fail('superseded');
    }

    void stop() {
      retired = true;
      if (!abort.isCompleted) abort.complete();
    }

    try {
      return await (() async {
        final token = await _bearerToken();
        check();
        if (token == null ||
            !RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(token)) {
          _fail('authenticationRequired');
        }
        final uri = endpoint
            .resolve(detail ? 'display/read.json' : 'display/query.json')
            .replace(
              queryParameters: {
                'resourceType': profile.resourceType,
                'screenId': detail
                    ? profile.detailScreenId
                    : profile.listScreenId,
                'resourceId': ?resourceId,
                'textus.output.shape': 'envelope',
              },
            );
        final request = http.AbortableRequest(
          'GET',
          uri,
          abortTrigger: abort.future,
        )..followRedirects = false;
        request.headers.addAll({
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'X-CNCF-Presentation-Context': _contextHeader(_context),
        });
        final response = await _client.send(request);
        if (retired || _closed || generation != _generation) {
          await response.stream.listen((_) {}, onError: (Object _) {}).cancel();
          _fail('superseded');
        }
        final bytes = <int>[];
        final body = Completer<void>();
        unawaited(
          abort.future.then((_) {
            if (!body.isCompleted) {
              body.completeError(const CncfDisplayReadException('superseded'));
            }
          }),
        );
        bodySubscription = response.stream.listen(
          (chunk) {
            if (body.isCompleted) return;
            if (bytes.length + chunk.length > 262144) {
              body.completeError(
                const CncfDisplayReadException('responseTooLarge'),
              );
            } else {
              bytes.addAll(chunk);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!body.isCompleted) body.completeError(error, stack);
          },
          onDone: () {
            if (!body.isCompleted) body.complete();
          },
        );
        await body.future;
        check();
        if (response.statusCode != 200) {
          throw CncfDisplayReadException(
            'httpRejected',
            statusCode: response.statusCode,
          );
        }
        if ((response.headers['content-type'] ?? '')
                .toLowerCase()
                .split(';')
                .first
                .trim() !=
            'application/json') {
          _fail('contentTypeInvalid');
        }
        final raw = utf8.decode(bytes);
        _uniqueJsonKeys(raw);
        final envelope = _object(jsonDecode(raw));
        // CNCF synchronous success carries the OBJECT in data; no raw-payload fallback.
        final data = _object(envelope['data']);
        final decoded = CncfDisplayRead.decode(
          data,
          profile,
          detail: detail,
          expectedResourceId: resourceId,
        );
        _context = decoded.presentationContext;
        return decoded;
      })().timeout(
        timeout,
        onTimeout: () {
          stop();
          _fail('timeout');
        },
      );
    } on CncfDisplayReadException {
      rethrow;
    } catch (_) {
      _fail('invalidResponseOrConnection');
    } finally {
      stop();
      final subscription = bodySubscription;
      if (subscription != null) {
        unawaited(subscription.cancel().catchError((Object _) {}));
      }
    }
  }
}

Never _fail(String code) => throw CncfDisplayReadException(code);

// HTTP field values are ASCII. JSON escapes preserve the admitted Unicode
// strings (including surrogate pairs) without inventing another carrier format.
String _contextHeader(Map<String, Object?>? context) {
  final canonical = <String, Object?>{
    'version': 1,
    'families': [
      for (final value in context?['families'] as List<Object?>? ?? const [])
        _canonicalFamily(_object(value)),
    ],
  };
  final encoded = jsonEncode(canonical);
  final ascii = StringBuffer();
  for (final unit in encoded.codeUnits) {
    if (unit > 0x7e) {
      ascii.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    } else {
      ascii.writeCharCode(unit);
    }
  }
  return ascii.toString();
}

Map<String, Object?> _canonicalFamily(Map<String, Object?> family) {
  final data = _object(family['data']);
  final keys = switch (family['name']) {
    'cncf.locale' => ['languageTag'],
    'cncf.presentation' => ['variant'],
    'cncf.display-flow' => ['displayInstance', 'correlation', 'expiresAt'],
    _ => throw const CncfDisplayReadException('contextFamilyInvalid'),
  };
  return {
    'name': family['name'],
    'version': 1,
    'data': {for (final key in keys) key: data[key]},
  };
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) _fail('objectRequired');
  return value;
}

List<Object?> _array(Object? value) {
  if (value is! List<Object?>) _fail('arrayRequired');
  return value;
}

String _text(Object? value) {
  if (value is! String) _fail('textRequired');
  return value;
}

String _id(Object? value) {
  final text = _text(value);
  if (text.isEmpty ||
      text.trim() != text ||
      text.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    _fail('identityInvalid');
  }
  return text;
}

void _keys(
  Map<String, Object?> value,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  if (!required.every(value.containsKey) ||
      value.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      ) ||
      value.values.any((v) => v == null)) {
    _fail('membersInvalid');
  }
}

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, v) => MapEntry(key, _freeze(v))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  _fail('jsonInvalid');
}

bool _equal(Object? a, Object? b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]))
    : a is List && b is List
    ? a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]))
    : a == b && (a is num ? a.runtimeType == b.runtimeType : true);

CncfDisplayResource _resource(
  Object? value,
  List<Map<String, Object?>> fields,
) {
  final resource = _object(value);
  _keys(resource, {'entityId', 'revision'});
  final revision = _text(resource['revision']);
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(revision) ||
      BigInt.parse(revision) > BigInt.parse('9223372036854775807')) {
    _fail('revisionInvalid');
  }
  return CncfDisplayResource._(
    _id(resource['entityId']),
    revision,
    List.unmodifiable(fields),
  );
}

List<Map<String, Object?>> _fields(Object? values) {
  final ids = <String>{};
  return List.unmodifiable(
    _array(values).map((v) {
      final field = _object(v);
      _keys(field, {'id', 'label', 'role', 'value'});
      if (!ids.add(_id(field['id']))) _fail('duplicateField');
      _text(field['label']);
      if (!{
        'content',
        'title',
        'subtitle',
        'description',
        'status',
      }.contains(field['role'])) {
        _fail('roleInvalid');
      }
      final value = _object(field['value']);
      // ESA5-01 is the accepted Text reference read slice. Other kinds fail
      // explicitly until a lossless typed scalar consumer is implemented.
      if (value['type'] == 'text') {
        _keys(value, {'type', 'text'});
        _text(value['text']);
      } else if (value['type'] == 'missing') {
        _keys(value, {'type'});
      } else {
        _fail('valueKindUnsupported');
      }
      return field;
    }),
  );
}

void _actions(Object? values) {
  final ids = <String>{};
  for (final v in _array(values)) {
    final a = _object(v);
    _keys(a, {'id', 'label', 'bindingId', 'availability'});
    if (!ids.add(_id(a['id']))) _fail('duplicateAction');
    _text(a['label']);
    _id(a['bindingId']);
    if (!{'hidden', 'disabled', 'enabled'}.contains(a['availability'])) {
      _fail('availabilityInvalid');
    }
  }
}

Map<String, Object?> _context(Object? value) {
  final context = _object(value);
  _keys(context, {'version', 'families'});
  if (context['version'] is! int || context['version'] != 1) {
    _fail('contextVersionInvalid');
  }
  final families = _array(context['families']);
  if (families.length > 8 || utf8.encode(jsonEncode(context)).length > 8192) {
    _fail('contextLimitExceeded');
  }
  final names = <String>{};
  final supported = <Map<String, Object?>>[];
  final pending = <(Object?, int)>[(context, 1)];
  while (pending.isNotEmpty) {
    final (value, depth) = pending.removeLast();
    if (value is Map || value is List) {
      if (depth > 8) _fail('contextLimitExceeded');
      final children = value is Map ? value.values : value as List;
      pending.addAll(children.map((v) => (v, depth + 1)));
    }
  }
  for (final value in families) {
    final f = _object(value);
    _keys(f, {'name', 'version', 'data'});
    final name = _id(f['name']);
    if (!RegExp(
          r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*(?:\.[a-z][a-z0-9]*(?:-[a-z0-9]+)*)+$',
        ).hasMatch(name) ||
        !names.add(name) ||
        name.length > 64 ||
        f['version'] is! int ||
        (f['version']! as int) <= 0) {
      _fail('contextFamilyInvalid');
    }
    final data = _object(f['data']);
    if (f['version'] != 1) continue;
    switch (name) {
      case 'cncf.locale':
        _keys(data, {'languageTag'});
        _bounded(data['languageTag'], 128);
        if (!RegExp(
          r'^(?:und|[a-z]{2,3})(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?(?:-[a-z0-9]{5,8}|-[0-9][a-z0-9]{3})*(?:-[a-wy-z0-9](?:-[a-z0-9]{2,8})+)*(?:-x(?:-[a-z0-9]{1,8})+)?$',
        ).hasMatch(data['languageTag']! as String)) {
          _fail('localeUnsupported');
        }
        supported.add(f);
      case 'cncf.presentation':
        _keys(data, {'variant'});
        _bounded(data['variant'], 128);
        supported.add(f);
      case 'cncf.display-flow':
        _keys(data, {'displayInstance', 'correlation', 'expiresAt'});
        _bounded(data['displayInstance'], 256);
        _bounded(data['correlation'], 256);
        final expiry = _text(data['expiresAt']);
        if (!RegExp(
              r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3}|\.\d{6}|\.\d{9})?Z$',
            ).hasMatch(expiry) ||
            DateTime.tryParse(expiry)?.isUtc != true) {
          _fail('contextExpiryInvalid');
        }
        final parsed = DateTime.parse(expiry);
        final fraction = expiry.contains('.')
            ? expiry.split('.').last.replaceAll('Z', '')
            : null;
        if (parsed.toIso8601String().substring(0, 19) !=
                expiry.substring(0, 19) ||
            (fraction != null &&
                (fraction == '000' ||
                    fraction.length > 3 && fraction.endsWith('000')))) {
          _fail('contextExpiryInvalid');
        }
        supported.add(f);
    }
  }
  const order = ['cncf.locale', 'cncf.presentation', 'cncf.display-flow'];
  supported.sort(
    (a, b) => order
        .indexOf(a['name']! as String)
        .compareTo(order.indexOf(b['name']! as String)),
  );
  return Map.unmodifiable({
    'version': 1,
    'families': List.unmodifiable(supported),
  });
}

void _bounded(Object? value, int maxBytes) {
  final text = _id(value);
  if (utf8.encode(text).length > maxBytes ||
      text.runes.any(
        (rune) =>
            rune >= 0xd800 && rune <= 0xdfff || rune >= 0x80 && rune <= 0x9f,
      )) {
    _fail('contextValueInvalid');
  }
}

// Standard JSON performs syntax decoding. This bounded lexical preflight also
// rejects repeated decoded object keys before dart:convert could collapse them.
void _uniqueJsonKeys(String text) {
  final stack = <Set<String>?>[];
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '{' || c == '[') {
      stack.add(c == '{' ? <String>{} : null);
      if (stack.length > 64) _fail('jsonDepthExceeded');
    } else if (c == '}' || c == ']') {
      if (stack.isEmpty) _fail('jsonInvalid');
      stack.removeLast();
    } else if (c == '"') {
      final start = i++;
      while (i < text.length && text[i] != '"') {
        if (text[i] == '\\') i++;
        i++;
      }
      if (i >= text.length) _fail('jsonInvalid');
      var next = i + 1;
      while (next < text.length && ' \n\r\t'.contains(text[next])) {
        next++;
      }
      if (next < text.length && text[next] == ':') {
        if (stack.isEmpty ||
            stack.last == null ||
            !stack.last!.add(
              jsonDecode(text.substring(start, i + 1)) as String,
            )) {
          _fail('duplicateJsonMember');
        }
      }
    }
  }
}
