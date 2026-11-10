import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/ui/chat/intelligent_ui/intelligent_ui_bridge.dart';

void main() {
  group('parseIntelligentUiBridgeMessage', () {
    test('accepts a matching token and extracts fields', () {
      final message = parseIntelligentUiBridgeMessage(
        jsonEncode({
          'token': 't',
          'type': 'resize',
          'height': 321.5,
        }),
        't',
      );
      expect(message, isNotNull);
      expect(message!.type, 'resize');
      expect(message.height, 321.5);
    });

    test('rejects a wrong token and oversized payloads', () {
      expect(
        parseIntelligentUiBridgeMessage(jsonEncode({'token': 'x', 'type': 'ready'}), 't'),
        isNull,
      );
      expect(parseIntelligentUiBridgeMessage('x' * 32769, 't'), isNull);
    });

    test('rejects non-object JSON', () {
      expect(parseIntelligentUiBridgeMessage('[]', 't'), isNull);
    });
  });

  group('UiActionGuard', () {
    test('admits one action at a time and never replays an id', () {
      final guard = UiActionGuard();
      final t0 = DateTime(2026, 1, 1);
      expect(guard.admit(1, t0), 1);
      expect(guard.isCurrent(1), isTrue);
      expect(guard.submit(1), isTrue);
      expect(guard.submit(1), isFalse);
      expect(guard.admit(1, t0.add(const Duration(seconds: 2))), isNull);
      expect(guard.admit(2, t0.add(const Duration(milliseconds: 500))), isNull);
      expect(guard.admit(3, t0.add(const Duration(seconds: 2))), 3);
    });

    test('invalidates a pending action', () {
      final guard = UiActionGuard();
      final t0 = DateTime(2026, 1, 1);
      expect(guard.admit(1, t0), 1);
      guard.invalidate();
      expect(guard.isCurrent(1), isFalse);
    });
  });
}
