import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Small Android surfaces render independently of Flutter's frame scheduler.
abstract final class NativeAnimationChannel {
  static const channel = MethodChannel('dsh/native_animation');
  static final available = ValueNotifier(false);
  static Future<bool>? _capability;
  static bool _availabilityChecked = false;

  /// Tests replace device capability queries without registering a platform binding.
  @visibleForTesting
  static Future<bool> Function() queryAvailability = _queryPlatform;

  static bool get availabilityChecked => _availabilityChecked;

  static Future<bool> _queryPlatform() async => await channel.invokeMethod<bool>('isAvailable') ?? false;
  static final _listeners = <int, ValueChanged<Map<String, Object?>>>{};
  static int _nextId = 0;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> ensureAvailable() => _capability ??= _probe();

  static Future<bool> _probe() async {
    var result = false;
    try {
      result = supported && await queryAvailability();
    } on MissingPluginException {
      // Desktop embeddings and widget tests do not register the Android plugin.
      result = false;
    } finally {
      _availabilityChecked = true;
    }
    if (result) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'reset') {
          for (final listener in _listeners.values.toList()) {
            listener({'type': 'reset'});
          }
          return;
        }
        if (call.method != 'event') return;
        final event = Map<String, Object?>.from(call.arguments as Map);
        _listeners[event['id']]?.call(event);
      });
    }
    available.value = result;
    return result;
  }

  static int register(ValueChanged<Map<String, Object?>> listener) {
    final id = ++_nextId;
    _listeners[id] = listener;
    return id;
  }

  static void unregister(int id) => _listeners.remove(id);

  static Future<void> upsert(Map<String, Object?> config) => channel.invokeMethod<void>('upsert', config);
  static Future<void> remove(int id) => channel.invokeMethod<void>('remove', {'id': id});

  @visibleForTesting
  static void resetForTesting() {
    _capability = null;
    _availabilityChecked = false;
    queryAvailability = _queryPlatform;
    available.value = false;
    _listeners.clear();
    channel.setMethodCallHandler(null);
  }
}
