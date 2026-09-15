import 'dart:io';

import 'package:path_provider/path_provider.dart';

const bool persistenceAvailable = true;

Future<File> _file() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/bill_store.json');
}

/// Reads the store, or returns null if there simply is not one yet.
///
/// Errors are deliberately NOT swallowed. Returning null for a failed read
/// made a broken or briefly unavailable file indistinguishable from a first
/// run: the app seeded itself empty and the next save wrote that emptiness
/// over the top. The caller needs to be able to tell the two apart.
Future<String?> loadRaw() async {
  final f = await _file();
  if (!await f.exists()) return null;
  return f.readAsString();
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

/// Writes the store, via a temporary file.
///
/// Writing in place meant a process killed part way through left a truncated
/// file, which the next launch could not parse - so the rename is what makes
/// the previous store survive an interrupted save.
Future<void> saveRaw(String json) async {
  try {
    final f = await _file();
    final temp = File('${f.path}.writing');
    await temp.writeAsString(json, flush: true);
    await temp.rename(f.path);
  } catch (_) {
    // A failed write must never take the app down. The user still has the
    // data on screen; it is the next write that will recover it.
  }
}

/// Deletes the copies kept of stores that could not be read.
///
/// Each of those is a complete dump of the receipts, the names and the PIN
/// hash. "Clear all data" used to leave every one of them sitting in the
/// documents directory, which made the setting a lie. They also accumulated,
/// one per failed parse, with nothing ever removing them.
Future<void> sweepQuarantinedStores() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.startsWith('bill_store.unreadable.')) continue;
      try {
        await entry.delete();
      } catch (_) {
        // Locked or already gone; nothing useful to do.
      }
    }
  } catch (_) {
    // No documents directory on this platform.
  }
}
