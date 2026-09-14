Future<String?> loadRaw() async => null;
Future<void> saveRaw(String json) async {}
const bool persistenceAvailable = false;

/// No filesystem here, so there is nowhere to put a copy.
Future<void> saveCorrupt(String raw) async {}
