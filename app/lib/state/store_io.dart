import 'dart:io';

import 'package:path_provider/path_provider.dart';

const bool persistenceAvailable = true;

Future<File> _file() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/bill_store.json');
}

Future<String?> loadRaw() async {
  try {
    final f = await _file();
    if (!await f.exists()) return null;
    return await f.readAsString();
  } catch (_) {
    return null;
  }
}

/// Keeps a copy of a store file that could not be parsed.
///
/// Without this, one bad write or a truncated file meant the next launch
/// silently started from nothing and the first edit overwrote the evidence.
/// The copy is local, like everything else, and can be inspected or renamed
/// back by hand.
Future<void> saveCorrupt(String raw) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await File('${dir.path}/bill_store.unreadable.$stamp.json')
        .writeAsString(raw, flush: true);
  } catch (_) {
    // Nothing useful to do; the in-memory state is still correct.
  }
}

Future<void> saveRaw(String json) async {
  try {
    final f = await _file();
    await f.writeAsString(json, flush: true);
  } catch (_) {
    // A failed write must never take the app down. The user still has the
    // data on screen; it is the next write that will recover it.
  }
}
