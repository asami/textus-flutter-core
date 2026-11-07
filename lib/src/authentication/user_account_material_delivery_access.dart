part of 'user_account_http_authentication_backend.dart';

/// Core-bound existing TKL delivery and Registered-source Studio handoff ports.
/// Closing/retiring the creating HTTP session fences every borrowed capability.
final class UserAccountMaterialDeliveryAccess {
  UserAccountMaterialDeliveryAccess._({
    required this.binding,
    required this.authentication,
    required this.tklConnection,
    required this.studioConnection,
    required this.delivery,
    required this.studio,
    required this._close,
  });
  final SubmissionAuthenticationBinding binding;
  final SubmissionAuthenticationContext authentication;
  final HttpSubmissionConnection tklConnection;
  final HttpSubmissionConnection studioConnection;
  final TklMaterialDeliveryHttpClient delivery;
  final HttpSubmissionTransport studio;
  final void Function() _close;
  bool _closed = false;
  void close() {
    if (!_closed) {
      _closed = true;
      _close();
    }
  }
}

final class _DeliveryRoutingClient extends http.BaseClient {
  _DeliveryRoutingClient(this.base, this.control, this.direct);
  final Uri base;
  final http.Client control;
  final http.Client direct;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.origin == base.origin &&
        request.url.path.startsWith(base.path)) {
      return control.send(request);
    }
    final uri = request.url;
    if (uri.scheme != 'https' ||
        uri.host != 'www.googleapis.com' ||
        uri.port != 443 ||
        uri.path != '/upload/drive/v3/files' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParameters['uploadType'] != 'resumable' ||
        uri.queryParameters['upload_id']?.isNotEmpty != true ||
        request.headers.keys.any(
          (key) => const {
            'authorization',
            'cookie',
            'proxy-authorization',
          }.contains(key.toLowerCase()),
        )) {
      throw http.ClientException('Capability transfer target is unavailable');
    }
    return direct.send(request);
  }

  @override
  void close() {
    /* Borrowed transports remain session/caller owned. */
  }
}
