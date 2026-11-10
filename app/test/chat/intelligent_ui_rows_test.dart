import 'dart:convert';

import 'package:dsh_app/state/intelligent_ui.dart';
import 'package:dsh_app/ui/chat/chat_rows.dart';
import 'package:dsh_app/ui/chat/tool_view.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 11, 10, 10);

TurnTrace _trace(int startSeq, int endSeq) => TurnTrace(
  turn: startSeq,
  startSeq: startSeq,
  start: _t0,
  spans: const [],
  endSeq: endSeq,
  end: _t0.add(const Duration(seconds: 10)),
  endReason: TurnEndReason('completed'),
);

void main() {
  test('intelligent UI cards stay outside a folded turn', () {
    final artifact = IntelligentUiArtifact(
      kind: IntelligentUiKind.declarative,
      hostId: 'local',
      sessionId: 's1',
      uiId: 'call-1',
      version: 1,
      definition: const {'root': 'root', 'components': []},
      seq: 1,
    );
    final tool = ToolChatItem(
      callId: 'call-1',
      name: 'ui_render',
      arguments: jsonEncode(const {'root': 'root', 'components': []}),
      status: ToolStatus.succeeded,
      seq: 1,
    );
    final assistant = AssistantChatItem(
      id: 'a2',
      text: 'done',
      reasoning: '',
      seq: 2,
    );

    final rows = deriveRows(
      items: [tool, assistant],
      turns: [_trace(1, 2)],
      foldTurns: true,
      intelligentUis: [artifact],
    );

    final cardRows = rows.whereType<ToolCallRow>().where((row) => row.uiArtifact != null).toList();
    expect(cardRows, hasLength(1));
    expect(cardRows.single.card, ToolCardPlacement.cardOnly);
    expect(rows.whereType<TurnProcessRow>(), hasLength(1));
  });
}
