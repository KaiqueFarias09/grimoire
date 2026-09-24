import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:unseal/unseal.dart';

void main() {
  DemoFixture fixtureOf(final String asset) =>
      demoFixtures.firstWhere((final fixture) => fixture.asset.endsWith(asset));

  LoadedBook bookWithDescription(final DemoFixture fixture, final String? description) =>
      LoadedBook.fromMetadata(
        fixture,
        BookMetadata(format: BookFormat.epub, description: description),
      );

  test('a synopsis stored as escaped HTML is shown as plain text', () {
    // What Unseal returns: the OPF's dc:description after XML entity
    // decoding, still an HTML fragment.
    final book = bookWithDescription(
      fixtureOf('pride-and-prejudice.epub'),
      '\n\t\t\t<p><i>Pride and Prejudice</i> may today be one of '
      '<a href="https://standardebooks.org/ebooks/jane-austen">Jane Austen\u2019s</a> '
      'most enduring novels.</p>\n\t\t',
    );

    expect(
      book.description,
      'Pride and Prejudice may today be one of Jane Austen\u2019s most enduring novels.',
    );
  });

  test('a description without markup passes through with entities decoded', () {
    final book = bookWithDescription(
      fixtureOf('dom-casmurro.epub'),
      'R&amp;D veio antes &lt;depois&gt; do romance.',
    );

    expect(book.description, 'R&D veio antes <depois> do romance.');
  });

  test('a book without a description falls back to the fixture text', () {
    final fixture = fixtureOf('dom-casmurro.epub');
    final book = bookWithDescription(fixture, null);

    expect(book.description, fixture.descriptionFallback);
  });

  test('a description that strips to nothing falls back to the fixture text', () {
    final fixture = fixtureOf('dom-casmurro.epub');
    final book = bookWithDescription(fixture, '<p>   </p>');

    expect(book.description, fixture.descriptionFallback);
  });
}
