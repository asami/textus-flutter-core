/// Native per-call ML Kit resources on IO; truthful unsupported API elsewhere.
library;

export 'mlkit_image_recognition_provider_stub.dart'
    if (dart.library.io) 'mlkit_image_recognition_provider_io.dart';
