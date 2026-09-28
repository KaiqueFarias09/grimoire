import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/features/search/search_generation.dart';

void main() {
  test('an older overlapping search cannot publish after the newer search', () async {
    final generation = SearchGeneration();
    final published = <String>[];

    Future<void> publishWhenReady(final int token, final Future<String> result) async {
      final value = await result;
      generation.commitIfCurrent(token, () => published.add(value));
    }

    final olderResult = Completer<String>();
    final older = publishWhenReady(generation.begin(), olderResult.future);
    final newerResult = Completer<String>();
    final newer = publishWhenReady(generation.begin(), newerResult.future);

    // Complete the new request first, then deliver the stale request.
    newerResult.complete('new query');
    await newer;
    olderResult.complete('old query');
    await older;

    expect(published, ['new query']);
  });
}
