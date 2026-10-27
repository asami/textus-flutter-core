import 'settings_storage.dart';

/// Creates this platform's namespaced settings adapter without reading it.
SettingsStorage createStorage(String namespace) => throw UnsupportedError(
  'Local Settings storage is unavailable on this platform',
);
