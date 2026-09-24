/// The demo's declarative routes: one GoRouter, the prototype's
/// fade-through as the page transition, screens resolved per route.
library;

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:grimoire_example/src/pages/detail_page.dart';
import 'package:grimoire_example/src/pages/reader_screen.dart';
import 'package:grimoire_example/src/pages/reading_page.dart';
import 'package:grimoire_example/src/app/app_routes.dart';
import 'package:grimoire_example/src/app/app_state.dart';
import 'package:grimoire_example/src/app/app_shell.dart';

class AppRouter {
  AppRouter({required String initialLocation, required this.revision, required this.shell})
    : _initialLocation = initialLocation;

  final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'root navigator',
  );

  final String _initialLocation;

  /// Host state revisions. Route pages are cached by the navigator,
  /// so each page rebuilds inside this listenable whenever the host
  /// mutates its state.
  final ValueListenable<int> revision;

  /// The shell configuration; its host chrome wraps every route.
  final BooksAppShell shell;

  late final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: _initialLocation,
    routes: [
      // The shell chrome (backdrop, overlay hosts, host scope) wraps
      // every matched route, so sheets and toasts ride above whatever
      // screen is up while staying inside the navigator's Overlay.
      ShellRoute(
        builder: (final context, final state, final child) =>
            BooksAppShellHost(shell: shell, child: child),
        routes: _routes(),
      ),
    ],
  );

  List<RouteBase> _routes() {
    return [
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (final context, final state) =>
            _page(state, () => ReadingPage(host: DemoHostScope.of(context))),
        routes: [
          GoRoute(
            path: 'book/:id',
            pageBuilder: (final context, final state) => _page(
              state,
              () =>
                  DetailPage(host: DemoHostScope.of(context), bookId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: 'read/:id',
            pageBuilder: (final context, final state) => _page(
              state,
              () => ReaderScreen(
                host: DemoHostScope.of(context),
                bookId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  /// The prototype's fade-through page change, kept as the route
  /// transition so navigation feels identical to the old state
  /// machine.
  CustomTransitionPage<void> _page(final GoRouterState state, final Widget Function() build) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: ListenableBuilder(listenable: revision, builder: (final context, _) => build()),
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
