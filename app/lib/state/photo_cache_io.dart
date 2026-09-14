import 'dart:io';

import 'package:path_provider/path_provider.dart';

const _imageSuffixes = ['.jpg', '.jpeg', '.png', '.heic', '.webp'];

/// Removes one working copy, once its text has been read.
Future<void> discardPhoto(String path) async {
  if (path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // A photo that cannot be deleted is not worth failing a scan over. The
    // sweep below will catch it later.
  }
}

/// Removes every leftover working copy from the app's caches.
///
/// Called by "Clear all data", which would otherwise wipe the receipts while
/// leaving the photographs of them behind.
Future<void> sweepPhotoCache() async {
  final directories = <Directory>[];
  try {
    directories.add(await getTemporaryDirectory());
  } catch (_) {
    // No temp directory on this platform.
  }
  try {
    final support = await getApplicationSupportDirectory();
    directories.add(support);
  } catch (_) {
    // Optional.
  }

  for (final dir in directories) {
    try {
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(recursive: true)) {
        if (entry is! File) continue;
        final lower = entry.path.toLowerCase();
        if (!_imageSuffixes.any(lower.endsWith)) continue;
        try {
          await entry.delete();
        } catch (_) {
          // Skip anything locked and carry on.
        }
      }
    } catch (_) {
      // Directory disappeared mid-sweep, or is not listable.
    }
  }
}
