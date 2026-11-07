library;

export 'platform_media_input_stub.dart'
    if (dart.library.io) 'platform_media_input_native.dart'
    if (dart.library.js_interop) 'platform_media_input_web.dart';
