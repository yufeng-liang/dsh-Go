import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/state/intelligent_ui.dart';
import 'package:dsh_app/ui/share/share_intelligent_ui.dart';

IntelligentUiArtifact _card({
  IntelligentUiKind kind = IntelligentUiKind.declarative,
  String title = 'Text Card',
  required Map<String, Object?> definition,
}) => IntelligentUiArtifact(
  kind: kind,
  hostId: 'host',
  sessionId: 'session',
  uiId: 'ui-1',
  version: 1,
  definition: definition,
  seq: 2,
  title: title,
  originSeq: 2,
);

void main() {
  test('renders a declarative text card', () {
    final markdown = shareIntelligentUiMarkdown(
      [
        _card(
          definition: {
            'root': 'root',
            'components': [
              {'id': 'root', 'type': 'text', 'props': {'text': 'Long press this text to select it'}},
            ],
          },
        ),
      ],
      startSeq: 1,
    );
    expect(markdown, isNotNull);
    expect(markdown, contains('Text Card'));
    expect(markdown, contains('Long press this text to select it'));
  });

  test('renders composition markdown and catalog blocks', () {
    final markdown = shareIntelligentUiMarkdown(
      [
        _card(
          kind: IntelligentUiKind.composition,
          title: 'Report',
          definition: {
            'title': 'Report',
            'blocks': [
              {'id': 'intro', 'type': 'markdown', 'text': 'intro text'},
              {
                'id': 'card',
                'type': 'catalog',
                'root': 'root',
                'components': [
                  {'id': 'root', 'type': 'stat', 'props': {'label': 'Done', 'value': 42}},
                ],
              },
            ],
          },
        ),
      ],
      startSeq: 1,
    );
    expect(markdown, contains('intro text'));
    expect(markdown, contains('**Done**'));
    expect(markdown, contains('42'));
  });

  test('leaves out cards from other turns', () {
    final markdown = shareIntelligentUiMarkdown(
      [
        _card(
          definition: {
            'root': 'root',
            'components': [
              {'id': 'root', 'type': 'text', 'props': {'text': 'not this turn'}},
            ],
          },
        ),
      ],
      startSeq: 10,
      endSeq: 20,
    );
    expect(markdown, isNull);
  });
}