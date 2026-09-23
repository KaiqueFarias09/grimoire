/// Route path constants and builders, one canonical home for every
/// navigable URI in the demo (Kiwi Manga's `app_routes.dart` pattern).
library;

class AppRoutes {
  const AppRoutes._();

  /// Ler agora: the shelf home.
  static const home = '/';

  /// Book detail; the id is a demo fixture id (`alice`, `pdf`, ...).
  static const book = '/book';
  static String bookPath(final String id) => '$book/$id';

  /// The full-screen reader.
  static const reader = '/read';
  static String readerPath(final String id) => '$reader/$id';
}
