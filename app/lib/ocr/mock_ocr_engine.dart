import 'ocr_engine.dart';
import 'ocr_types.dart';

/// A synthetic receipt, laid out with real geometry so that the desktop and
/// web builds exercise the actual row grouper and parser rather than
/// short-circuiting to a canned list of lines.
///
/// This is the Trattoria Bella receipt from the design prototype, including
/// the misread "T1RAMISU 65.00" that makes the balance check fail, plus a
/// date and a phone number in the left column that the price-column filter
/// has to reject.
OcrResult mockReceipt() {
  final words = <OcrWord>[];
  var y = 0.0;

  void row(List<(String, double)> cells, {double height = 14}) {
    for (final (text, x) in cells) {
      words.add(
        OcrWord(
          text: text,
          box: OcrBox(
            left: x,
            top: y,
            right: x + text.length * 7.5,
            bottom: y + height,
          ),
        ),
      );
    }
    y += height + 9;
  }

  // Header noise.
  row([('TRATTORIA', 60), ('BELLA', 148)]);
  row([('14.09.26', 60), ('19:42', 132)]);
  row([('TEL', 60), ('01.234.5678', 92)]);

  // Items. The price column sits at roughly x = 300.
  row([('BURRATA', 20), ('8.00', 300)]);
  row([('MARGHERITA', 20), ('9.50', 300)]);
  row([('DIAVOLA', 20), ('11.00', 300)]);
  row([('2', 20), ('X', 34), ('PERONI', 52), ('330ML', 110), ('9.00', 300)]);
  row([('T1RAMISU', 20), ('65.00', 300)]);
  row([('SPARKLING', 20), ('WATER', 96), ('3.00', 300)]);

  // Footer.
  row([('SUBTOTAL', 20), ('47.00', 300)]);
  row([('SERVICE', 20), ('10%', 84), ('4.70', 300)]);
  row([('TOTAL', 20), ('51.70', 300)]);
  row([('CARD', 20), ('51.70', 300)]);
  row([('THANK', 60), ('YOU', 116)]);

  return OcrResult(words);
}

/// Used on desktop and web, where there is no camera and no ML Kit.
/// The delay matches the prototype's simulated scan.
OcrEngine mockEngine() =>
    FakeOcrEngine(mockReceipt(), delay: const Duration(milliseconds: 1700));
