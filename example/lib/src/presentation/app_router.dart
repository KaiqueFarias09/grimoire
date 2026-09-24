/// The demo's declarative routes: one GoRouter, the prototype's
/// fade-through as the page transition, feature views resolved per
/// route. Screens read state through Riverpod controllers, so pages
/// need no host and no revision listener.
library;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/demo_flags.dart';
import '../features/library/presentation/views/detail_page/detail_page.dart';
import '../features/library/presentation/views/reading_page/reading_page.dart';
import '../features/reader/presentation/views/reader_screen/reader_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';

class AppRouter {
  AppRouter();

  final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'root navigator',
  );

  late final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: _startLocation,
    routes: [
      // The shell chrome (backdrop, overlay hosts, toast) wraps every
      // matched route, so sheets and toasts ride above whatever screen
      // is up while staying inside the navigator's Overlay.
      ShellRoute(
        builder: (final context, final state, final child) => AppShell(child: child),
        routes: _routes(),
      ),
    ],
  );

  /// `UB_START=detail:<id>|reader:<id>` puts screenshot runs straight
  /// on a route (parsed in core/demo_flags).
  String get _startLocation {
    final parts = ubStart.split(':');
    if (parts.first.isEmpty) {
      return AppRoutes.home;
    }

    return switch (parts.first) {
      'detail' => AppRoutes.bookPath(parts.length > 1 ? parts[1] : 'alice'),
      'reader' => AppRoutes.readerPath(parts.length > 1 ? parts[1] : 'alice'),
      _ => AppRoutes.home,
    };
  }

  List<RouteBase> _routes() {
    return [
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (final context, final state) => _page(state, const ReadingPage()),
        routes: [
          GoRoute(
            path: 'book/:id',
            pageBuilder: (final context, final state) =>
                _page(state, DetailPage(bookId: state.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'read/:id',
            pageBuilder: (final context, final state) =>
                _page(state, ReaderScreen(bookId: state.pathParameters['id']!)),
          ),
        ],
      ),
    ];
  }

  /// The prototype's fade-through page change, kept as the route
  /// transition so navigation feels identical to the old state
  /// machine.
  CustomTransitionPage<void> _page(final GoRouterState state, final Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (final context, final animation, final secondaryAnimation, final child) {
        return FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          fillColor: Colors.transparent,
          child: child,
        );
      },
    );
  }
}
