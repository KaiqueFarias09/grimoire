// Platform split for the open probe's environment access: native
// targets (macOS/Android/iOS profile builds) read process env vars,
// absolute file paths and the resident set; the browser target has
// none of those and reports nulls so the probe falls back to the
// bundled asset. The default export is the stub, mirroring Unseal's
// own `web/... if (dart.library.io)` convention.
export 'open_probe_env_stub.dart' if (dart.library.io) 'open_probe_env_io.dart';
