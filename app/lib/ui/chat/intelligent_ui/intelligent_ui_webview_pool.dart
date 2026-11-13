import 'dart:async';
import 'dart:collection';

/// Limits how many intelligent-ui WebViews are initialized at once.
///
/// Chat rows are already built lazily by the scrolling list; this pool covers
/// the second half of the problem: a burst of newly visible cards must not
/// create all platform views in the same frame.
class IntelligentUiWebViewPool {
  IntelligentUiWebViewPool._();

  static final IntelligentUiWebViewPool instance = IntelligentUiWebViewPool._();
  static const int maxConcurrent = 3;

  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
}
