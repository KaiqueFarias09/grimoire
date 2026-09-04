/// Platform-neutral book host.
///
/// The IO variant serves book files over a loopback HTTP server; the
/// web variant maps them to same-origin blob URLs. Both expose the
/// same `BookServer` contract. Conditional export picks the variant.
library;

export 'book_server_web.dart' if (dart.library.io) 'book_server_io.dart';
