/// Web build: no filesystem, so state lives for the session only.
const bool persistenceAvailable = false;

String? _memory;

Future<String?> loadRaw() async => _memory;

Future<void> saveRaw(String json) async {
  _memory = json;
}

/// No filesystem here, so there is nowhere to put a copy.
Future<void> saveCorrupt(String raw) async {}
