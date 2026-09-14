/// Chooses an OCR engine for the platform.
///
/// The conditional import is what keeps ML Kit out of the web build: the web
/// compiler never follows the io branch, so the plugin's platform channels
/// are never reachable from a browser target.
library;

export 'engine_factory_stub.dart' if (dart.library.io) 'engine_factory_io.dart';
