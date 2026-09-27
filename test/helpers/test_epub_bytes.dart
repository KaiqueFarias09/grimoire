import 'dart:convert';
import 'dart:typed_data';

const String testEpubChapter1 =
    '<!DOCTYPE html><html><head><title>One</title></head><body>'
    '<p id="p1">Chapter one text here.</p>'
    '<p>More words to find &amp; search.</p>'
    '<p>See <a href="chapter2.xhtml#fn1">the note</a>.</p>'
    '</body></html>';

const String testEpubChapter2 =
    '<!DOCTYPE html><html><head><title>Two</title></head><body>'
    '<p>Chapter two content with émojis 📚 done.</p>'
    '<p id="fn1">The footnote body text.</p>'
    '</body></html>';

const String testEpubCss = 'p { margin: 0; }';

final Uint8List testEpubCoverPng = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);

/// Builds a small two-chapter EPUB 2 as raw zip bytes, so tests can
/// open it through Unseal's progressive session exactly like a real
/// file. Entries are stored (no deflate); text files are UTF-8
/// encoded and the CRC32 keeps the container's integrity guards
/// happy.
Uint8List buildTestEpubBytes() {
  Uint8List text(final String source) => Uint8List.fromList(utf8.encode(source));

  return buildStoredZip(<(String, Uint8List)>[
    ('mimetype', text('application/epub+zip')),
    ('META-INF/container.xml', text(_containerXml)),
    ('OEBPS/content.opf', text(_packageXml)),
    ('OEBPS/toc.ncx', text(_ncxXml)),
    ('OEBPS/chapter1.xhtml', text(testEpubChapter1)),
    ('OEBPS/chapter2.xhtml', text(testEpubChapter2)),
    ('OEBPS/style.css', text(testEpubCss)),
    ('OEBPS/images/cover.png', testEpubCoverPng),
  ]);
}

const String _containerXml =
    '<?xml version="1.0"?>'
    '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

const String _packageXml =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">'
    '<dc:title>Test Session Book</dc:title>'
    '<dc:language>en</dc:language>'
    '<dc:creator>Test Author</dc:creator>'
    '<dc:identifier id="uid">test-session-book</dc:identifier>'
    '</metadata>'
    '<manifest>'
    '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
    '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="css" href="style.css" media-type="text/css"/>'
    '<item id="img" href="images/cover.png" media-type="image/png"/>'
    '</manifest>'
    '<spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>'
    '</package>';

const String _ncxXml =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="test-session-book"/></head>'
    '<docTitle><text>Test Session Book</text></docTitle>'
    '<navMap>'
    '<navPoint id="n1" playOrder="1"><navLabel><text>Chapter One</text></navLabel>'
    '<content src="chapter1.xhtml"/></navPoint>'
    '<navPoint id="n2" playOrder="2"><navLabel><text>Chapter Two</text></navLabel>'
    '<content src="chapter2.xhtml"/></navPoint>'
    '</navMap></ncx>';

/// Builds a stored (uncompressed) zip archive from [entries]:
/// local file headers, central directory, end-of-central-directory.
Uint8List buildStoredZip(final List<(String, Uint8List)> entries) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;

  for (final (name, bytes) in entries) {
    final nameBytes = Uint8List.fromList(name.codeUnits);
    final crc = crc32(bytes);
    final local = ByteData(30);
    local.setUint32(0, 0x04034b50, Endian.little);
    local.setUint16(4, 20, Endian.little);
    local.setUint16(6, 0, Endian.little);
    local.setUint16(8, 0, Endian.little);
    local.setUint16(10, 0, Endian.little);
    local.setUint16(12, 0, Endian.little);
    local.setUint32(14, crc, Endian.little);
    local.setUint32(18, bytes.length, Endian.little);
    local.setUint32(22, bytes.length, Endian.little);
    local.setUint16(26, nameBytes.length, Endian.little);
    local.setUint16(28, 0, Endian.little);
    out.add(local.buffer.asUint8List());
    out.add(nameBytes);
    out.add(bytes);

    final dir = ByteData(46);
    dir.setUint32(0, 0x02014b50, Endian.little);
    dir.setUint16(4, 20, Endian.little);
    dir.setUint16(6, 20, Endian.little);
    dir.setUint16(8, 0, Endian.little);
    dir.setUint16(10, 0, Endian.little);
    dir.setUint16(12, 0, Endian.little);
    dir.setUint16(14, 0, Endian.little);
    dir.setUint32(16, crc, Endian.little);
    dir.setUint32(20, bytes.length, Endian.little);
    dir.setUint32(24, bytes.length, Endian.little);
    dir.setUint16(28, nameBytes.length, Endian.little);
    dir.setUint16(30, 0, Endian.little);
    dir.setUint16(32, 0, Endian.little);
    dir.setUint16(34, 0, Endian.little);
    dir.setUint16(36, 0, Endian.little);
    dir.setUint32(38, 0, Endian.little);
    dir.setUint32(42, offset, Endian.little);
    central.add(dir.buffer.asUint8List());
    central.add(nameBytes);

    offset += 30 + nameBytes.length + bytes.length;
  }

  final centralBytes = central.takeBytes();
  final eocd = ByteData(22);
  eocd.setUint32(0, 0x06054b50, Endian.little);
  eocd.setUint16(4, 0, Endian.little);
  eocd.setUint16(6, 0, Endian.little);
  eocd.setUint16(8, entries.length, Endian.little);
  eocd.setUint16(10, entries.length, Endian.little);
  eocd.setUint32(12, centralBytes.length, Endian.little);
  eocd.setUint32(16, offset, Endian.little);
  eocd.setUint16(20, 0, Endian.little);

  out.add(centralBytes);
  out.add(eocd.buffer.asUint8List());

  return out.takeBytes();
}

/// Standard CRC-32 (IEEE 802.3, reflected, init/final xor).
int crc32(final Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      final mask = -(crc & 1);
      crc = (crc >>> 1) ^ (0xedb88320 & mask);
    }
  }

  return (~crc) >>> 0;
}
