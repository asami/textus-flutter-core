import 'package:web/web.dart' as web;

import 'settings_storage.dart';

/// Creates this platform's namespaced settings adapter without reading it.
SettingsStorage createStorage(String namespace) =>
    _BrowserSettingsStorage(namespace);

class _BrowserSettingsStorage implements SettingsStorage {
  _BrowserSettingsStorage(String namespace)
    : _key = 'textus.settings.$namespace';

  final String _key;

  @override
  Future<String?> read() async => web.window.localStorage.getItem(_key);

  @override
  Future<void> write(String record) async {
    // setItem completes synchronously or throws (quota/security restrictions).
    // The controller receives success only after that origin record replacement.
    web.window.localStorage.setItem(_key, record);
  }
}
