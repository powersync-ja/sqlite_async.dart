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

      test('increases delay after pause', () {
        fakeAsync((control) {
          final source = StreamController<UpdateNotification>(sync: true);
          final events = <UpdateNotification>[];

          final sub = UpdateNotification.throttleStream(source.stream, timeout)
              .listen(null);
          sub.onData((event) {
            events.add(event);
            sub.pause();
          });

          source.add(UpdateNotification({'a'}));
          control.elapse(timeout);
          expect(events, hasLength(1));

          // Assume the stream stays paused for the timeout window that would
          // be created after emitting the notification.
          control.elapse(timeout * 2);
          source.add(UpdateNotification({'b'}));
          control.elapse(timeout * 2);

          // A full timeout needs to pass after resuming before a new item is
          // emitted.
          sub.resume();
          expect(events, hasLength(1));

          control.elapse(halfTimeout);
          expect(events, hasLength(1));
          control.elapse(halfTimeout);
          expect(events, hasLength(2));
        });
      });

      test('does not introduce artificial delay in pause', () {
        fakeAsync((control) {
          final source = StreamController<UpdateNotification>(sync: true);
          final events = <UpdateNotification>[];

          final sub = UpdateNotification.throttleStream(source.stream, timeout)
              .listen(events.add);

          // Await the initial delay
          control.elapse(timeout);

          sub.pause();
          source.add(UpdateNotification({'a'}));
          // Resuming should not introduce a timeout window because no window
          // was active when the stream was paused.
          sub.resume();
          control.flushMicrotasks();
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

      test('closes when source closes after delay', () {
        fakeAsync((control) {
          final source = StreamController<UpdateNotification>(sync: true)
            ..onCancel = () => Future.value();
          final events = <UpdateNotification>[];
          var done = false;

          UpdateNotification.throttleStream(source.stream, timeout)
              .listen(events.add, onDone: () => done = true);

          control.elapse(const Duration(hours: 1));
          source.close();

          control.flushTimers();
          expect(events, isEmpty);
          expect(done, isTrue);
          expect(control.pendingTimers, isEmpty);
        });
      });

      group('without timeout', () {
        test('can forward notifications unchanged', () {
          fakeAsync((control) {
            final source = StreamController<UpdateNotification>(sync: true);
            final a = UpdateNotification({'a'});
            final b = UpdateNotification({'b'});
            final c = UpdateNotification({'c'});

            final received = <UpdateNotification>[];
            UpdateNotification.throttleStream(source.stream, null)
                .listen(received.add);
            expect(received, isEmpty);

            source.add(a);
            expect(identical(received.last, a), isTrue);
            source.add(b);
            expect(identical(received.last, b), isTrue);
            source.add(c);
            expect(identical(received.last, c), isTrue);
          });
        });

        test('can accumulate results while listener is paused', () {
          fakeAsync((control) {
            final source = StreamController<UpdateNotification>(sync: true);
            final received = <UpdateNotification>[];
            final subscription =
                UpdateNotification.throttleStream(source.stream, null)
                    .listen(received.add);
            expect(source.hasListener, isTrue);

            subscription.pause();
            // We should keep the source subscription active since we want to
            // buffer update notifications in throttleStream.
            expect(source.isPaused, isFalse);

            source.add(UpdateNotification({'a'}));
            source.add(UpdateNotification({'a', 'b'}));
            source.add(UpdateNotification({'a'}));

            control.flushTimers();
            expect(received, isEmpty);

            subscription.resume();
            expect(received, isEmpty);
            control.flushMicrotasks();
            expect(received, [
              UpdateNotification({'a', 'b'})
            ]);
          });
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
