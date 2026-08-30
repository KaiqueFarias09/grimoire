
import 'package:e_livre_viewer/src/bridge/viewer_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes every event type', () async {
    final bridge = ViewerBridge();
    addTearDown(bridge.dispose);

    final events = <ViewerEvent>[];
    final subscription = bridge.events.listen(events.add);
    addTearDown(subscription.cancel);

    bridge.accept('{"type":"ready","chars":120,"columns":8}');
    bridge.accept(
      '{"type":"positionChanged","column":2,"columns":8,"offset":40,'
      '"chars":120,"frac":0.25}',
    );
    bridge.accept('{"type":"fileBoundary","direction":1}');
    bridge.accept('{"type":"selectionChanged","text":"hi","start":3,"end":5}');
    bridge.accept('{"type":"linkTap","href":"https://x.dev","external":true}');
    bridge.accept('{"type":"chromeToggle"}');

    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(6));
    expect(events[0], isA<ReadyEvent>());
    expect((events[0] as ReadyEvent).chars, 120);
    expect(events[1], isA<PositionEvent>());
    expect((events[1] as PositionEvent).frac, 0.25);
    expect((events[2] as BoundaryEvent).direction, 1);
    expect((events[3] as SelectionEvent).text, 'hi');
    expect((events[4] as LinkTapEvent).external, isTrue);
    expect(events[5], isA<ChromeToggleEvent>());
  });

  test('tolerates malformed payloads', () async {
    final bridge = ViewerBridge();
    addTearDown(bridge.dispose);
    final events = <ViewerEvent>[];
    final subscription = bridge.events.listen(events.add);
    addTearDown(subscription.cancel);

    bridge.accept('not json');
    bridge.accept('{"type":"unknown"}');
    bridge.accept('[1,2,3]');
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });

  test('numeric fields arrive as strings too', () async {
    final bridge = ViewerBridge();
    addTearDown(bridge.dispose);
    final events = <ViewerEvent>[];
    final subscription = bridge.events.listen(events.add);
    addTearDown(subscription.cancel);

    bridge.accept(
      '{"type":"positionChanged","column":"3","columns":"9",'
      '"offset":"12","chars":"999","frac":"0.5"}',
    );
    await Future<void>.delayed(Duration.zero);
    final position = events.single as PositionEvent;
    expect(position.column, 3);
    expect(position.columns, 9);
    expect(position.frac, 0.5);
  });
}
