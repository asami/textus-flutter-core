/// Injected local-installation/browser-origin whole-record storage boundary.
///
/// The framework serializes writes. No server profile or compare-and-swap
/// requirement is introduced, and no concrete adapter is supplied here.
abstract interface class SettingsStorage {
  /// Reads the record; null means absence, failure means unread storage.
  Future<String?> read();

  /// Replaces the whole record and completes only after durable acknowledgement.
  /// A failure is not acknowledged; adapters must never report early success.
  Future<void> write(String record);
}
