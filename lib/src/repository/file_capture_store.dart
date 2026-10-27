/// Platform-selected local durable persistence.
///
/// IO platforms provide filesystem storage; other platforms expose a stub that
/// throws UnsupportedError for every operation and for the default factory.
library;

export 'file_capture_store_stub.dart'
    if (dart.library.io) 'file_capture_store_io.dart';
