// Native implementation of the open probe's environment access.
// Compiled for VM targets only (see open_probe_env.dart).

import 'dart:io';
import 'dart:typed_data';

/// Reads [key] from the process environment; null when unset.
///
/// On `flutter drive` desktop runs this carries the host's env vars. On
/// Android/iOS the app process has the DEVICE's (empty) environment —
/// configure those runs with `--dart-define` instead, which the probe
/// also honors.
String? openProbeEnv(final String key) => Platform.environment[key];

/// Reads the book at [path] (absolute, on the machine running the app).
Uint8List readBookFile(final String path) => File(path).readAsBytesSync();

/// The process resident set in bytes at call time (null never happens
/// on native targets; the nullable type keeps both platform files
/// signature-compatible).
int? currentRssBytes() => ProcessInfo.currentRss;
