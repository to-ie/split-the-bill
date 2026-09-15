import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Every character the interface draws has to exist in the font that draws it.
///
/// A missing one renders as an empty box - which is how "square → owes €30.00"
/// reached a screenshot with a tofu block in the middle of it. The fonts are
/// bundled, so this is checkable rather than a thing to notice by eye later.
Set<int> codepointsIn(File font) {
  final bytes = font.readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  int u16(int o) => data.getUint16(o);
  int u32(int o) => data.getUint32(o);

  final numTables = u16(4);
  var cmapOffset = -1;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(rec, rec + 4));
    if (tag == 'cmap') cmapOffset = u32(rec + 8);
  }
  if (cmapOffset < 0) return {};

  // Pick a Unicode subtable: format 4 (BMP) or format 12 (full).
  final numSub = u16(cmapOffset + 2);
  var best = -1;
  var bestFormat = -1;
  for (var i = 0; i < numSub; i++) {
    final rec = cmapOffset + 4 + i * 8;
    final platform = u16(rec);
    final encoding = u16(rec + 2);
    final offset = cmapOffset + u32(rec + 4);
    final unicode = platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
    if (!unicode) continue;
    final format = u16(offset);
    if (format == 12 || (format == 4 && bestFormat != 12)) {
      best = offset;
      bestFormat = format;
    }
  }
  if (best < 0) return {};

  final out = <int>{};
  if (bestFormat == 4) {
    final segX2 = u16(best + 6);
    final segs = segX2 ~/ 2;
    final endBase = best + 14;
    final startBase = endBase + segX2 + 2;
    for (var s = 0; s < segs; s++) {
      final end = u16(endBase + s * 2);
      final start = u16(startBase + s * 2);
      if (start > end || end == 0xFFFF) continue;
      for (var cp = start; cp <= end; cp++) {
        out.add(cp);
      }
    }
  } else {
    final groups = u32(best + 12);
    for (var g = 0; g < groups; g++) {
      final rec = best + 16 + g * 12;
      final start = u32(rec);
      final end = u32(rec + 4);
      for (var cp = start; cp <= end && cp - start < 0x10000; cp++) {
        out.add(cp);
      }
    }
  }
  return out;
}

void main() {
  test('every character the app draws exists in the bundled fonts', () {
    final fonts = {
      'Nunito': File('assets/fonts/Nunito.ttf'),
      'RobotoMono': File('assets/fonts/RobotoMono.ttf'),
    };
    for (final f in fonts.values) {
      expect(f.existsSync(), isTrue, reason: '${f.path} is missing');
    }
    final coverage = {
      for (final e in fonts.entries) e.key: codepointsIn(e.value),
    };

    // Everything non-ASCII that appears in a string literal under lib/.
    final used = <int, List<String>>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Comments are not drawn. Strip them, or a "✕" in a doc comment
      // describing a button reads as a rendering fault.
      final text = file
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            if (i < 0) return l;
            // Only strip when the // is not inside a string literal.
            final before = l.substring(0, i);
            final quotes = "'".allMatches(before).length +
                '"'.allMatches(before).length;
            return quotes.isEven ? before : l;
          })
          .join('\n');

      for (final rune in text.runes) {
        if (rune < 0x80) continue;
        (used[rune] ??= []).add(file.path);
      }
    }

    final missing = <String>[];
    used.forEach((rune, files) {
      final ch = String.fromCharCode(rune);
      final absent = coverage.entries
          .where((e) => !e.value.contains(rune))
          .map((e) => e.key)
          .toList();
      if (absent.isNotEmpty) {
        missing.add('U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}'
            ' "$ch" missing from ${absent.join(", ")}'
            ' (${files.toSet().map((p) => p.split("/").last).take(3).join(", ")})');
      }
    });

    expect(
      missing,
      isEmpty,
      reason: 'these draw as empty boxes:\n${missing.join("\n")}',
    );
  });
}
