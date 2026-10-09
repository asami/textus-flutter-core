import 'settings_storage.dart';
import 'local_settings_storage_stub.dart'
    if (dart.library.io) 'local_settings_storage_io.dart'
    if (dart.library.js_interop) 'local_settings_storage_web.dart'
    as platform;

/// Creates caller-owned installation/origin storage for one Settings controller.
///
/// Uses a flushed temporary file and replacement on native platforms, and a
/// namespaced browser localStorage record on Web. Constructors perform no I/O.
/// One application controller owns writes for a namespace; cross-process or
/// cross-tab concurrent writers are not coordinated by this local boundary.
SettingsStorage createLocalSettingsStorage({required String namespace}) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(namespace)) {
    throw ArgumentError.value(
      namespace,
      'namespace',
      'A local storage name is required',
    );
  }
  return platform.createStorage(namespace);
}
