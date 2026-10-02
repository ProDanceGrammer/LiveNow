import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;

/// Drops a list event that equals the previous one (element-wise `==`), so a
/// write that does not change a query's result causes no rebuild.
Stream<List<T>> distinctList<T>(Stream<List<T>> source) =>
    source.distinct((a, b) => listEquals(a, b));

/// Rate-limits [source]: the first event is forwarded immediately, later ones
/// are held until [quiet] has passed without a newer event and then only the
/// LAST one is emitted — a burst of writes becomes a single rebuild.
///
/// Cancel-safe: cancelling the returned subscription cancels the pending
/// timer and the source subscription; a pending event is dropped on cancel,
/// and flushed (not lost) when the source completes.
Stream<T> debounced<T>(Stream<T> source, Duration quiet) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  Timer? timer;
  var first = true;
  T? pending;
  var hasPending = false;

  void flush() {
    timer?.cancel();
    timer = null;
    if (hasPending) {
      final value = pending as T;
      pending = null;
      hasPending = false;
      controller.add(value);
    }
  }

  controller = StreamController<T>(
    onListen: () {
      sub = source.listen(
        (event) {
          if (first) {
            first = false;
            controller.add(event);
            return;
          }
          pending = event;
          hasPending = true;
          timer?.cancel();
          timer = Timer(quiet, flush);
        },
        onError: controller.addError,
        onDone: () {
          flush();
          controller.close();
        },
      );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      timer?.cancel();
      timer = null;
      hasPending = false;
      pending = null;
      await sub?.cancel();
    },
  );
  return controller.stream;
}
