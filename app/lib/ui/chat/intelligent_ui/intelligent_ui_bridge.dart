import 'dart:convert';

/// WebView 页面发回给 Flutter 的一条消息。
class IntelligentUiBridgeMessage {
  const IntelligentUiBridgeMessage({required this.token, required this.type, required this.data});

  final String token;
  final String type;
  final Map<String, Object?> data;

  int? get id => switch (data['id']) {
    final int value when value >= 0 => value,
    final num value when value >= 0 => value.toInt(),
    _ => null,
  };

  String? get text => data['text'] is String ? data['text'] as String : null;
  String? get name => data['name'] is String ? data['name'] as String : null;
  String? get url => data['url'] is String ? data['url'] as String : null;
  double? get height => switch (data['height']) {
    final num value => value.toDouble(),
    _ => null,
  };
}

/// 解析并校验页面回传的 JSON。规则与 remote 的
/// `parseUiBridgeMessage` 保持一致：限制消息长度，必须是对象，token 必须匹配。
IntelligentUiBridgeMessage? parseIntelligentUiBridgeMessage(Object? raw, String token, {bool allowAnyToken = false}) {
  if (raw is! String || raw.length > 32768) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final data = <String, Object?>{
    for (final entry in decoded.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  if (!allowAnyToken && data['token'] != token) return null;
  final actualToken = data['token'] is String ? data['token'] as String : token;
  final type = data['type'];
  if (type is! String || type.isEmpty) return null;
  return IntelligentUiBridgeMessage(token: actualToken, type: type, data: data);
}

/// `ui_render` 卡片里的动作闸门。
///
/// 每个动作必须带严格递增的 id；同一时刻只允许一个动作等待，且两次 admit
/// 至少间隔 [minInterval]。id 在节流/忙时也会被消费，避免页面重复提交旧 id。
class UiActionGuard {
  UiActionGuard({this.minInterval = const Duration(seconds: 1)});

  final Duration minInterval;
  int _lastId = 0;
  DateTime? _lastAdmittedAt;
  int? _pending;

  int? admit(int id, DateTime now) {
    if (id < 0 || id <= _lastId) return null;
    _lastId = id;
    if (_pending != null) return null;
    final last = _lastAdmittedAt;
    if (last != null && now.difference(last) < minInterval) return null;
    _lastAdmittedAt = now;
    _pending = id;
    return id;
  }

  bool isCurrent(int id) => _pending == id;

  bool submit(int id) {
    if (_pending != id) return false;
    _pending = null;
    return true;
  }

  void invalidate() {
    _pending = null;
  }

  /// Clears all replay state when the renderer document reloads.
  void reset() {
    _lastId = 0;
    _lastAdmittedAt = null;
    _pending = null;
  }
}
