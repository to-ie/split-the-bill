/// Camera and gallery access, kept behind a conditional import for the same
/// reason ML Kit is: neither plugin exists on the web.
library;

export 'capture_stub.dart' if (dart.library.io) 'capture_io.dart';
