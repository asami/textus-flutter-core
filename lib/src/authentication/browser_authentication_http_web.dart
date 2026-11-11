import 'dart:async';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

http.Client createBrowserAuthenticationHttpClient(Uri authority) {
  if (authority.origin != Uri.base.origin) {
    throw ArgumentError('Browser authentication requires the page origin');
  }
  return _BrowserAuthenticationHttpClient(authority);
}

http.Client createAuthenticatedServiceHttpClient(Uri serviceBaseUri) =>
    createBrowserAuthenticationHttpClient(serviceBaseUri);

/// Only a TKL-issued Google resumable capability can use this cookie-free CORS
/// transport. Human account credentials are never forwarded to that origin.
http.Client createCapabilityTransferHttpClient() =>
    _BrowserAuthenticationHttpClient(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files'),
      capabilityTransfer: true,
    );

/// The ordinary BrowserClient uses `same-origin` credentials, which would send
/// ambient cookies alongside our explicit Bearer. Fetch must instead omit them.
final class _BrowserAuthenticationHttpClient extends http.BaseClient {
  _BrowserAuthenticationHttpClient(
    this.authority, {
    this.capabilityTransfer = false,
  });
  final Uri authority;
  final bool capabilityTransfer;
  final Set<web.AbortController> _pending = {};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed ||
        request.url.origin != authority.origin ||
        !request.url.path.startsWith(authority.path) ||
        request.url.userInfo.isNotEmpty ||
        request.url.hasFragment ||
        (capabilityTransfer &&
            (request.url.path != authority.path ||
                request.url.queryParameters['uploadType'] != 'resumable' ||
                request.url.queryParameters['upload_id']?.isNotEmpty != true ||
                request.headers.keys.any(
                  (key) => const {
                    'authorization',
                    'cookie',
                    'proxy-authorization',
                  }.contains(key.toLowerCase()),
                )))) {
      throw http.ClientException('Authentication request is unavailable');
    }
    final abort = web.AbortController();
    _pending.add(abort);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.then<void>((_) {
          if (_pending.contains(abort)) abort.abort();
        }),
      );
    }
    try {
      final body = await request.finalize().toBytes();
      if (_closed) throw StateError('closed');
      final response = await web.window
          .fetch(
            request.url.toString().toJS,
            web.RequestInit(
              method: request.method,
              body: body.isEmpty ? null : body.toJS,
              headers: request.headers.jsify()! as web.HeadersInit,
              credentials: 'omit',
              redirect: 'error',
              cache: 'no-store',
              mode: capabilityTransfer ? 'cors' : 'same-origin',
              referrerPolicy: 'no-referrer',
              signal: abort.signal,
            ),
          )
          .toDart;
      final headers = <String, String>{};
      (response.headers as _IterableHeaders).forEach(
        ((String value, String key) {
          headers[key.toLowerCase()] = value;
        }).toJS,
      );
      return http.StreamedResponse(
        _body(response, abort),
        response.status,
        headers: headers,
        request: request,
      );
    } catch (_) {
      _pending.remove(abort);
      abort.abort();
      throw http.ClientException('Authentication transport failed');
    }
  }

  Stream<List<int>> _body(
    web.Response response,
    web.AbortController abort,
  ) async* {
    web.ReadableStreamDefaultReader? reader;
    var completed = false;
    try {
      reader = response.body?.getReader() as web.ReadableStreamDefaultReader?;
      if (reader == null) {
        completed = true;
        return;
      }
      while (true) {
        final chunk = await reader.read().toDart;
        if (chunk.done) {
          completed = true;
          break;
        }
        yield (chunk.value as JSUint8Array).toDart;
      }
    } catch (_) {
      throw http.ClientException('Authentication response failed');
    } finally {
      _pending.remove(abort);
      if (!completed) {
        abort.abort();
        try {
          await reader?.cancel().toDart;
        } catch (_) {
          // Aborted/error streams may reject cancellation; the request is retired.
        }
      }
    }
  }

  @override
  void close() {
    _closed = true;
    for (final abort in _pending) {
      abort.abort();
    }
    _pending.clear();
  }
}

@JS()
extension type _IterableHeaders._(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
}
