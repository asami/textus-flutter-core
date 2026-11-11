/// Explicit browser durable media/queue adapters. Native defaults are unchanged.
library;

export 'browser_capture_store_stub.dart'
    if (dart.library.js_interop) 'browser_capture_store_web.dart';
