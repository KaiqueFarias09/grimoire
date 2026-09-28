import 'dart:typed_data';

/// Assembles minimal-but-valid PDF documents byte by byte, derived
/// from Unseal's `test/tests/pdf/pdf_fixture_builder.dart` (MIT,
/// deterministic generator; trimmed to the classic-xref, plain-stream
/// subset grimoire's viewer tests need so no extra dependency crosses
/// over). Provenance: generated in-test, never a shipped creative
/// work — the prose lines are original test markers.
class TestPdfBuilder {
  final Map<int, String> _bodies = <int, String>{};
  final Map<int, String> _streamEntries = <int, String>{};
  final Map<int, List<int>> _streamData = <int, List<int>>{};

  /// Adds a plain indirect object whose [body] sits between `obj` and
  /// `endobj` — e.g. `<< /Type /Catalog /Pages 2 0 R >>`.
  void addObject(final int number, final String body) {
    _bodies[number] = body;
  }

  /// Adds a stream object; [extraEntries] appends to the dictionary
  /// and [data] is the raw payload.
  void addStreamObject(final int number, final String extraEntries, final List<int> data) {
    _streamEntries[number] = extraEntries;
    _streamData[number] = List<int>.of(data);
  }

  /// Builds the document with a classic cross-reference table.
  Uint8List build() {
    final out = BytesBuilder(copy: false);
    out.add('%PDF-1.7\n%'.codeUnits);
    out.add(const [0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    final offsets = <int, int>{};
    final numbers = <int>[..._bodies.keys, ..._streamData.keys]..sort();
    for (final number in numbers) {
      offsets[number] = out.length;
      out.add('$number 0 obj\n'.codeUnits);
      final data = _streamData[number];
      if (data != null) {
        out.add('<< /Length ${data.length}${_streamEntries[number]} >>\n'.codeUnits);
        out.add('stream\n'.codeUnits);
        out.add(data);
        out.add('\nendstream\n'.codeUnits);
      } else {
        out.add('${_bodies[number]}\n'.codeUnits);
      }
      out.add('endobj\n'.codeUnits);
    }

    final maxNumber = numbers.isEmpty ? 0 : numbers.last;
    final xrefOffset = out.length;
    out.add('xref'.codeUnits);
    out.add('\n0 ${maxNumber + 1}\n'.codeUnits);
    out.add('0000000000 65535 f \n'.codeUnits);
    for (var number = 1; number <= maxNumber; number++) {
      final offset = offsets[number];
      out.add(
        offset == null
            ? '0000000000 65535 f \n'.codeUnits
            : '${offset.toString().padLeft(10, '0')} 00000 n \n'.codeUnits,
      );
    }
    out.add('trailer\n<< /Size ${maxNumber + 1} /Root 1 0 R >>\n'.codeUnits);
    out.add('startxref\n$xrefOffset\n%%EOF'.codeUnits);

    return out.toBytes();
  }
}

/// A [pageCount]-page fixture with no text at all: empty content
/// streams only, the scanned-document shape the facsimile path owns.
TestPdfBuilder scannedPagesFixture({final int pageCount = 2}) {
  final fixture = TestPdfBuilder()..addObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  const firstPageObject = 10;
  final kids = <String>[];
  for (var i = 0; i < pageCount; i++) {
    final page = firstPageObject + i * 2;
    final contents = page + 1;
    kids.add('$page 0 R');
    fixture
      ..addObject(
        page,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents $contents 0 R '
        '/Resources << >> >>',
      )
      ..addStreamObject(contents, '', 'BT ET'.codeUnits);
  }
  fixture.addObject(2, '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${kids.length} >>');

  return fixture;
}

/// A [pageCount]-page fixture with real body text on every page: a
/// standard-14 Helvetica, two flush-left body lines and a distinctive
/// searchable marker line per page — one exact marker hit per page
/// for search-parity checks.
TestPdfBuilder multipageTextFixture({
  final int pageCount = 3,
  final String marker = 'quixoticmarker',
}) {
  final fixture = TestPdfBuilder()
    ..addObject(1, '<< /Type /Catalog /Pages 2 0 R >>')
    ..addObject(
      3,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    );
  const firstPageObject = 10;
  final kids = <String>[];
  for (var i = 0; i < pageCount; i++) {
    final page = firstPageObject + i * 2;
    final contents = page + 1;
    kids.add('$page 0 R');
    fixture.addObject(
      page,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents $contents 0 R '
      '/Resources << /Font << /F1 3 0 R >> >> >>',
    );
    final body = StringBuffer()
      ..write('BT /F1 12 Tf 72 720 Td (Page $i opens with a plain body line of) Tj ET\n')
      ..write('BT /F1 12 Tf 72 705 Td (generous width so the reflow has) Tj ET\n')
      ..write('BT /F1 12 Tf 72 690 Td (plenty to hold together across the line breaks.) Tj ET\n')
      ..write('BT /F1 12 Tf 72 660 Td (The $marker appears exactly once per page.) Tj ET\n');
    fixture.addStreamObject(contents, '', body.toString().codeUnits);
  }
  fixture.addObject(2, '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${kids.length} >>');

  return fixture;
}
