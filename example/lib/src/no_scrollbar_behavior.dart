part of '../grimoire_example_app.dart';

/// Hides scrollbars and lets pointer devices drag lists, matching the
/// prototype's thin/hidden scrollbars.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    final BuildContext context,
    final Widget child,
    final ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices {
    return <PointerDeviceKind>{
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.stylus,
    };
  }
}
