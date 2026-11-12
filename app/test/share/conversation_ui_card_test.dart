import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/share_code/conversation_share.dart';

void main() {
  test('round-trips a UI card', () {
    const card = ConversationUiCard(title: 'Text Card', markdown: 'Long press this text');
    final json = card.toJson();
    final again = ConversationUiCard.fromJson(json);
    expect(again, isNotNull);
    expect(again!.title, 'Text Card');
    expect(again.markdown, 'Long press this text');
  });

  test('round-trips a widget card for high-fidelity replay', () {
    const card = ConversationUiCard(
      title: 'Typography specimen',
      markdown: 'body',
      widget: {'html': '<p style="font-family: serif">serif</p>', 'css': 'p{font-size:20px}'},
    );
    final again = ConversationUiCard.fromJson(card.toJson());
    expect(again, isNotNull);
    expect(again!.widget, {'html': '<p style="font-family: serif">serif</p>', 'css': 'p{font-size:20px}'});
  });

  test('round-trips a full artifact for complex cards', () {
    const card = ConversationUiCard(
      title: 'Dashboard',
      markdown: 'body',
      artifact: {
        'kind': 'composition',
        'definition': {
          'title': 'Dashboard',
          'blocks': [
            {'id': 'intro', 'type': 'markdown', 'text': 'intro'},
          ],
        },
        'policy': {'maxHeight': 2400},
      },
    );
    final again = ConversationUiCard.fromJson(card.toJson());
    expect(again, isNotNull);
    expect(again!.artifact, card.artifact);
  });

  test('rejects a malformed artifact for complex cards', () {
    final card = ConversationUiCard.fromJson({
      'md': 'body',
      'artifact': {'kind': 'unknown', 'definition': <String, Object?>{}},
    });
    expect(card, isNotNull);
    expect(card!.artifact, isNull);
  });

  test('rejects a widget definition with a script tag', () {
    final card = ConversationUiCard.fromJson({
      'md': 'body',
      'widget': {'html': '<script>alert(1)</script>'},
    });
    expect(card, isNotNull);
    expect(card!.widget, isNull);
  });

  test('strips inline event handlers from widget html', () {
    final card = ConversationUiCard.fromJson({
      'md': 'body',
      'widget': {'html': '<p onclick="steal()">hello</p>'},
    });
    expect(card, isNotNull);
    expect(card!.widget!['html'], isNot(contains('onclick')));
    expect(card.widget!['html'], contains('hello'));
  });

  test('drops an empty card and keeps a title-less one', () {
    expect(ConversationUiCard.fromJson({'md': ''}), isNull);
    expect(ConversationUiCard.fromJson({'md': 42}), isNull);
    final card = ConversationUiCard.fromJson({'md': 'body'});
    expect(card, isNotNull);
    expect(card!.title, isNull);
    expect(card.markdown, 'body');
  });

  test('a reply carries its UI cards in JSON', () {
    const entry = ReplyEntry(
      t: 10,
      text: 'answer',
      ui: [ConversationUiCard(title: 'Text Card', markdown: 'body')],
    );
    final json = entry.toJson();
    expect(json['ui'], [
      {'title': 'Text Card', 'md': 'body'},
    ]);
  });

  test('a reply without UI cards leaves the field out', () {
    const entry = ReplyEntry(t: 10, text: 'answer');
    expect(entry.toJson().containsKey('ui'), isFalse);
  });
}
