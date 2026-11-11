import 'package:http/http.dart' as http;

http.Client createCapabilityTransferHttpClient() => http.Client();

http.Client createBrowserAuthenticationHttpClient(Uri authority) =>
    throw UnsupportedError('Browser authentication transport is unavailable');

http.Client createAuthenticatedServiceHttpClient(Uri serviceBaseUri) =>
    http.Client();
