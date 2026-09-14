/// Local persistence. No network, no accounts: the whole store is one JSON
/// file in the app's documents directory, per the brief.
///
/// Web has no such directory. The web build is a viewing target only, so it
/// keeps state in memory for the session and says so in Settings.
library;

export 'store_stub.dart'
    if (dart.library.io) 'store_io.dart'
    if (dart.library.js_interop) 'store_web.dart';
