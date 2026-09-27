// Browser stub of the open probe's environment access: Chrome has no
// process environment, no file system and no resident-set counter, so
// the probe reports null RSS and ignores path configuration there.

import 'dart:typed_data';

/// Null on the web; `--dart-define` configuration still works there.
String? openProbeEnv(String key) => null;

/// Unsupported on the web; use the bundled asset instead.
Uint8List readBookFile(String path) =>
    throw UnsupportedError('E2E_OPEN_BOOK_PATH requires a native target');

/// Null on the web: RSS sampling is a native-only signal.
int? currentRssBytes() => null;
