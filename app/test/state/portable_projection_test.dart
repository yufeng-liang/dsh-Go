import 'package:dsh_app/state/intelligent_ui.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 工具调用事件夹具：口径与 intelligent_ui_test.dart 中的 _call 保持一致。
ToolCallEvent _call(int seq, String callId, String name) => ToolCallEvent(
  seq,
  DateTime(2026, 1, 1),
  const {},
  turn: 1,
  step: 1,
  callId: callId,
  name: name,
  arguments: '{}',
);

/// 工具结果事件夹具：data 里只放 presentationMeta。
ToolResultEvent _result(int seq, String callId, Map<String, Object?> meta) => ToolResultEvent(
  seq,
  DateTime(2026, 1, 1),
  {'meta': meta},
  turn: 1,
  step: 1,
  message: Message(
    id: 'm$seq',
    role: MessageRole.tool,
    parts: const [],
    source: MessageSource('tool', {'callId': callId}),
    toolCallId: callId,
  ),
);

void main() {
  group('IntelligentUiProjection portable cards', () {
    test('merges a portable card from a non-ui tool result into artifacts', () {
      final events = <SessionLogEvent>[
        _call(1, 'c1', 'render_data'),
        _result(2, 'c1', {'html': '<p>hi</p>'}),
      ];
      final projection = IntelligentUiProjection(hostId: 'h', sessionId: 's')..applyAll(events);

      expect(projection.artifacts, hasLength(1));
      final card = projection.artifacts.single;
      expect(card.uiId, 'c1');
      expect(card.hostId, 'h');
      expect(card.sessionId, 's');
      expect(card.kind, IntelligentUiKind.widget);
      expect(card.definition['html'], '<p>hi</p>');
      // 结果事件的 seq 是卡片自己的 seq，调用事件的 seq 用来把卡片挂回父工具行。
      expect(card.seq, 2);
      expect(card.originSeq, 1);
    });

    test('adds no portable card when the call name belongs to a ui_* tool', () {
      final events = <SessionLogEvent>[
        _call(1, 'c1', 'ui_render'),
        _result(2, 'c1', {'html': '<p>hi</p>'}),
      ];
      final projection = IntelligentUiProjection(hostId: 'h', sessionId: 's')..applyAll(events);

      expect(projection.artifacts.where((card) => card.uiId == 'c1'), isEmpty);
    });
  });
}
