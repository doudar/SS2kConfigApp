/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

/// Extension methods for Stream to add common reactive operators
/// without requiring external dependencies like rxdart
extension StreamExtensions<T> on Stream<T> {
  /// Debounces the stream by emitting an item from the source Stream
  /// only after a particular timespan has passed without the Stream emitting
  /// any other items.
  ///
  /// This is useful for preventing rapid-fire UI updates when characteristic
  /// changes come in quick succession.
  ///
  /// Example:
  /// ```dart
  /// stream.debounce(Duration(milliseconds: 500)).listen((event) {
  ///   // Handle debounced event
  /// });
  /// ```
  Stream<T> debounce(Duration duration) {
    StreamController<T>? controller;
    StreamSubscription<T>? subscription;
    Timer? timer;

    void onListen() {
      subscription = this.listen(
        (T data) {
          timer?.cancel();
          timer = Timer(duration, () {
            controller?.add(data);
          });
        },
        onError: controller?.addError,
        onDone: () {
          timer?.cancel();
          controller?.close();
        },
      );
    }

    void onCancel() {
      timer?.cancel();
      subscription?.cancel();
    }

    controller = StreamController<T>(
      onListen: onListen,
      onCancel: onCancel,
      sync: true,
    );

    return controller.stream;
  }
}
