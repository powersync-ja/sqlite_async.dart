# Reproduce a deadlock during native shutdown

Run this command from `packages/sqlite_async`:

```sh
dart run example/close_deadlock/bin/close_deadlock.dart
```

The example uses two clients for one temporary database file.
The first client holds a read snapshot and then writes its output.
The second client closes while that snapshot remains active.
The example uses no Flutter, Drift, network, or external data.

In `sqlite_async` 0.14.6, shutdown requests exclusive access to the shared native pool.
That request reserves the writer and waits for the snapshot's reader.
The snapshot then waits for the reserved writer.
The two operations cannot finish.

The example sets a one-second timeout on the writer request so it can release the snapshot and clean up.
The affected version reports the deadlock and exits with code 1.
Without that timeout, the writer request waits indefinitely.

With the fix, shutdown releases only the second client's requests.
The first client commits its output and prints the stored value, `43`.
The example then exits with code 0.
