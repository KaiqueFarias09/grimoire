import 'package:fake_async/fake_async.dart';

/// Drains the microtask chains of controller events inside a
/// synchronous fakeAsync body: engine evaluations and ready handshakes
/// are microtask-chained, never wall-clock waits.
void flushControllerEvents(final FakeAsync async) {
  for (var i = 0; i < 6; i++) {
    async.flushMicrotasks();
  }
}
