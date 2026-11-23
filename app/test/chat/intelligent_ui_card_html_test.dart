import 'package:dsh_app/ui/chat/intelligent_ui/intelligent_ui_card.dart';
import 'package:flutter_test/flutter_test.dart';

String _html({bool allowNewSession = false}) => buildIntelligentUiHtml(
  rendererCode: 'window.DshIntelligentUiRenderer={mount:function(){}};',
  token: 't',
  allowNewSession: allowNewSession,
);

void main() {
  test('host 默认不暴露新会话动作', () {
    final html = _html();
    expect(html, isNot(contains('sendNewSession')));
  });

  test('host 按开关暴露新会话动作', () {
    final html = _html(allowNewSession: true);
    expect(html, contains('sendNewSession:function(text,nodeId)'));
    expect(html, contains("send('newSession'"));
    expect(html, contains("nodeId:String(nodeId||'')"));
  });
}
