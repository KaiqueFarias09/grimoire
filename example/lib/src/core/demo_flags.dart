/// Screenshot and QA automation hooks, parsed once from dart-defines.
///
/// These exist for the side-by-side prototype checks and emulator QA
/// runs; the app itself never branches on them outside the shell's
/// startup and the fullscreen media-query override.
library;

/// `UB_START=detail:<id>|reader:<id>` puts a screenshot run straight on
/// a route; empty means the shelf home.
const String ubStart = String.fromEnvironment('UB_START');

/// `UB_OVERLAY=add|note|search|collections|summary|settings` pre-opens
/// an overlay on the first frame.
const String ubOverlay = String.fromEnvironment('UB_OVERLAY');

/// `UB_FULLSCREEN=true` strips the safe-area insets so screenshots line
/// up 1:1 with the browser-rendered prototype.
const bool ubFullscreen = bool.fromEnvironment('UB_FULLSCREEN');
