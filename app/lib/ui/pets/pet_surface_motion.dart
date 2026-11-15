import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// One finite movement, sampled by Android without asking Flutter for frames.
/// Offsets are relative to the sprite's final canvas position, in logical pixels.
class PetSurfaceMotion {
  PetSurfaceMotion({
    required this.serial,
    required this.kind,
    required this.duration,
    required this.from,
    this.to = Offset.zero,
    this.height = 0,
  });

  final int serial;
  final String kind;
  final Duration duration;
  final Offset from;
  final Offset to;
  final double height;
  final Stopwatch _clock = Stopwatch()..start();
  Duration _elapsed = Duration.zero;

  /// Native reports only start/pause/resume, never one message per frame.
  /// Keep interruption sampling on its paused clock while offscreen.
  void synchronize(Duration elapsed, {required bool active}) {
    _elapsed = elapsed;
    _clock
      ..stop()
      ..reset();
    if (active) _clock.start();
  }

  double get progress => ((_elapsed + _clock.elapsed).inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);

  Offset get offset => at(progress);

  Offset at(double t) {
    final eased = switch (kind) {
      'hop' => Curves.easeInOut.transform(t),
      'drop' => Curves.easeIn.transform(t),
      _ => t,
    };
    return Offset.lerp(from, to, eased)! + Offset(0, kind == 'hop' ? -4 * height * t * (1 - t) : 0);
  }

  /// A small canvas containing the whole path; no full-screen transparent layer.
  Rect envelope(Size canvas, {Rect? paintedBounds}) {
    final bounds = paintedBounds ?? (Offset.zero & canvas);
    final left = bounds.left + math.min(0.0, math.min(from.dx, to.dx));
    final top = bounds.top + math.min(0.0, math.min(from.dy, to.dy) - height);
    final right = bounds.right + math.max(0.0, math.max(from.dx, to.dx));
    final bottom = bounds.bottom + math.max(0.0, math.max(from.dy, to.dy));
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Map<String, Object?> toConfig(double dpr) => {
    'serial': serial,
    'kind': kind,
    'durationMs': duration.inMilliseconds,
    'from': [from.dx * dpr, from.dy * dpr],
    'to': [to.dx * dpr, to.dy * dpr],
    'height': height * dpr,
  };
}
