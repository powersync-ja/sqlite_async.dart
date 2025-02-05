import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:test/test.dart';

void main() {
  group('Update notifications', () {
    const timeout = Duration(seconds: 10);
    const halfTimeout = Duration(seconds: 5);

    group('throttle', () {
      test('can add initial', () {
        fakeAsync((control) {
          final source = StreamController<UpdateNotification>(sync: true);
          final events = <UpdateNotification>[];

          UpdateNotification.throttleStream(source.stream, timeout,
              addOne: UpdateNotification({'a'})).listen(events.add);

          control.flushMicrotasks();
          expect(events, hasLength(1));
          control.elapse(halfTimeout);

          source.add(UpdateNotification({'b'}));
          expect(events, hasLength(1)); // Still a delay from the initial one

          control.elapse(halfTimeout);
          expect(events, hasLength(2));
        });
      });

      test('sends events after initial throttle', () {
        fakeAsync((control) {
          final source = StreamController<UpdateNotification>(sync: true);
          final events = <UpdateNotification>[];

          UpdateNotification.throttleStream(source.stream, timeout)
              .listen(events.add);

          source.add(UpdateNotification({'a'}));
          control.elapse(halfTimeout);
          expect(events, isEmpty);

          control.elapse(halfTimeout);
          expect(events, hasLength(1));
        });
      });

      test('merges events', () {
        fakeAsync((control) {
          final source = StreamController<UpdateNotification>(sync: true);
          final events = <UpdateNotification>[];

          UpdateNotification.throttleStream(source.stream, timeout)
              .listen(events.add);

          source.add(UpdateNotification({'a'}));
          control.elapse(halfTimeout);
          expect(events, isEmpty);

          source.add(UpdateNotification({'b'}));
          control.elapse(halfTimeout);
          expect(events, [
            UpdateNotification({'a', 'b'})
          ]);
        });
      });

      test('forwards cancellations', () {
        fakeAsync((control) {
          var cancelled = false;
          final source = StreamController<UpdateNotification>(sync: true)
            ..onCancel = () => cancelled = true;

          final sub = UpdateNotification.throttleStream(source.stream, timeout)
              .listen((_) => fail('unexpected event'),
                  onDone: () => fail('unexpected done'));

          source.add(UpdateNotification({'a'}));
          control.elapse(halfTimeout);

          sub.cancel();
          control.flushTimers();

          expect(cancelled, isTrue);
          expect(control.pendingTimers, isEmpty);
        });
      });

      test('closes when source closes', () {
        fakeAsync((control) {
          final source = StreamController<UpdateNotification>(sync: true)
            ..onCancel = () => Future.value();
          final events = <UpdateNotification>[];
          var done = false;

          UpdateNotification.throttleStream(source.stream, timeout)
              .listen(events.add, onDone: () => done = true);

          source
            // These two are combined due to throttleFirst
            ..add(UpdateNotification({'a'}))
            ..add(UpdateNotification({'b'}))
            ..close();

          control.flushTimers();
          expect(events, [
            UpdateNotification({'a', 'b'})
          ]);
          expect(done, isTrue);
          expect(control.pendingTimers, isEmpty);
        });
      });
    });

    test('filter tables', () async {
      final source = StreamController<UpdateNotification>(sync: true);
      final events = <UpdateNotification>[];
      final subscription = UpdateNotification.filterTablesTransformer(['a'])
          .bind(source.stream)
          .listen(events.add);

      source.add(UpdateNotification({'a', 'b'}));
      expect(events, hasLength(1));

      source.add(UpdateNotification({'b'}));
      expect(events, hasLength(1));

      await subscription.cancel();
      expect(source.hasListener, isFalse);
    });
  });
}
