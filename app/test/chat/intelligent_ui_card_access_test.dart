import 'package:dsh_app/state/intelligent_ui.dart';
import 'package:dsh_app/ui/chat/intelligent_ui/intelligent_ui_card.dart';
import 'package:dsh_app/ui/chat/tool_view.dart';
import 'package:dsh_app/ui/chat/widgets/tool_row.dart';
import 'package:dsh_app/ui/theme/app_icons.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

IntelligentUiArtifact _artifact({String uiId = 'ui-card'}) => IntelligentUiArtifact(
  kind: IntelligentUiKind.declarative,
  hostId: 'h',
  sessionId: 's',
  uiId: uiId,
  version: 1,
  definition: const {
    'root': 'root',
    'components': [
      {
        'id': 'root',
        'type': 'Text',
        'props': {'text': '正文'},
      },
    ],
  },
  seq: 1,
);

Future<IntelligentUiNewSessionResult> _handler(String text, {required String uiId, String? nodeId}) async =>
    const IntelligentUiNewSessionResult(sent: true);

void main() {
  testWidgets('fullscreen page keeps readOnly and the new-session handler', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: IntelligentUiCard(
            artifact: _artifact(),
            allowFullscreen: true,
            readOnly: true,
            onSendNewSession: _handler,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(AppIcons.fullscreen), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.fullscreen));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<IntelligentUiCard>(find.byType(IntelligentUiCard)).toList();
    expect(cards, hasLength(1));
    expect(cards.last.readOnly, isTrue);
    expect(cards.last.onSendNewSession, same(_handler));
    expect(cards.last.immersive, isTrue);
    expect(cards.last.unboundedTables, isTrue);
  });

  testWidgets('ToolRow passes readOnly and the new-session handler to the card', (tester) async {
    usePhoneView(tester);
    final item = ToolChatItem(
      callId: 'call-1',
      name: 'ui_render',
      arguments: '{}',
      status: ToolStatus.succeeded,
      seq: 1,
    );
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: ToolRow(
            item: item,
            onRespond: (request, decision) async {},
            card: ToolCardPlacement.cardOnly,
            uiArtifact: _artifact(),
            readOnly: true,
            onSendNewSession: _handler,
          ),
        ),
      ),
    );
    await tester.pump();

    final card = tester.widget<IntelligentUiCard>(find.byType(IntelligentUiCard));
    expect(card.readOnly, isTrue);
    expect(card.onSendNewSession, same(_handler));
    expect(card.allowFullscreen, isTrue);
  });
}
