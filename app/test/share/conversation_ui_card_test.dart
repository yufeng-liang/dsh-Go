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
