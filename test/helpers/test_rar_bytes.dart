import 'dart:typed_data';

/// Minimal stored-RAR4 archive builder for grimoire's session tests.
///
/// Provenance: byte-packing adapted (simplified to the stored method
/// only) from Unseal's `test/support/rar_fixtures.dart` (`buildRar4`),
/// MIT-licensed like this package. Grimoire's tests cannot import the
/// sibling Unseal checkout, so the ~40 lines needed to produce a valid
/// comic container live here.
///
/// Layout: `Rar!` signature, one stored file header + payload per
/// entry, end-of-archive block. File CRC stays 0 — the session skips
/// CRC verification for CRC-less entries, mirroring the eager reader.
Uint8List buildTestRar({
  final List<String> names = const ['page_001.jpg', 'page_002.jpg', 'page_003.jpg'],
  final List<int> page = const [0xFF, 0xD8, 0xFF, 0xE0, 0, 1, 2, 3, 0xFF, 0xD9],
}) {
  final builder = BytesBuilder(copy: false);
  builder.add([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]); // "Rar!\x1a\x07\x00"

  for (final name in names) {
    final nameBytes = name.codeUnits;
    final header = ByteData(32 + nameBytes.length);
    var f = 0;
    header.setUint16(f, 0, Endian.little);
    f += 2; // header crc (unchecked)
    header.setUint8(f, 0x74);
    f += 1; // block type: file header
    header.setUint16(f, 0x8000, Endian.little);
    f += 2; // flags
    header.setUint16(f, header.lengthInBytes, Endian.little);
    f += 2; // header size
    header.setUint32(f, page.length, Endian.little);
    f += 4; // packed size
    header.setUint32(f, page.length, Endian.little);
    f += 4; // unpacked size
    header.setUint8(f, 0);
    f += 1; // host OS
    header.setUint32(f, 0, Endian.little);
    f += 4; // file crc (0: never verified)
    header.setUint32(f, 0, Endian.little);
    f += 4; // file time
    header.setUint8(f, 29);
    f += 1; // unpack version
    header.setUint8(f, 0x30);
    f += 1; // method: stored
    header.setUint16(f, nameBytes.length, Endian.little);
    f += 2; // name size
    header.setUint32(f, 0x20, Endian.little);
    f += 4; // attributes
    // The name lives INSIDE the header block: headSize covers header
    // + name, and the reader computes dataStart = offset + headSize.
    header.buffer.asUint8List().setRange(f, f + nameBytes.length, nameBytes);
    builder.add(header.buffer.asUint8List());
    builder.add(page);
  }

  final end = ByteData(7);
  end.setUint8(2, 0x7B); // block type: end of archive
  end.setUint16(3, 0x4000, Endian.little); // flags
  end.setUint16(5, 7, Endian.little); // block size
  builder.add(end.buffer.asUint8List());

  return builder.takeBytes();
}
