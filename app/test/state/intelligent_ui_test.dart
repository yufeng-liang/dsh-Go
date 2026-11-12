import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/state/intelligent_ui.dart';

Map<String, Object?> _tree({String root = 'root'}) => {
  'root': root,
  'components': [
    {
      'id': root,
      'type': 'text',
      'props': {'text': 'hello'},
    },
  ],
};

ToolCallEvent _call(int seq, String callId, String name, Map<String, Object?> args) => ToolCallEvent(
  seq,
  DateTime(2026, 1, 1),
  const {},
  turn: 1,
  step: 1,
  callId: callId,
  name: name,
  arguments: _json(args),
);

ToolResultEvent _result(int seq, String callId, {Object? meta, bool isError = false}) => ToolResultEvent(
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
    isError: isError,
  ),
);

String _json(Object? value) => const JsonEncoder().convert(value);

AssistantMessageEvent _assistantWithToolCall(int seq, String callId, String name) => AssistantMessageEvent(
  seq,
  DateTime(2026, 1, 1),
  const {},
  turn: 1,
  step: 1,
  message: Message(
    id: 'm$seq',
    role: MessageRole.assistant,
    parts: [ToolCallPart(id: callId, name: name, arguments: '{}')],
    source: MessageSource('model', const {}),
  ),
);

void main() {
  group('IntelligentUiProjector', () {
    test('projects ui_render and applies a stale-safe patch', () {
      final events = <SessionLogEvent>[
        _call(1, 'call-a', 'ui_render', {'title': 'First', ..._tree()}),
        _result(
          2,
          'call-a',
          meta: {
            'ok': true,
            'policy': {'maxHeight': 320},
          },
        ),
        _call(3, 'call-b', 'ui_patch', {'uiId': 'call-a', 'baseVersion': 1, 'ops': []}),
        _result(
          4,
          'call-b',
          meta: {
            'ok': true,
            'ui': {'uiId': 'call-a', 'version': 2, ..._tree(root: 'next')},
          },
        ),
      ];
      final artifacts = IntelligentUiProjector.project(events, hostId: 'host', sessionId: 'session');
      expect(artifacts, hasLength(1));
      expect(artifacts.single.uiId, 'call-a');
      expect(artifacts.single.kind, IntelligentUiKind.declarative);
      expect(artifacts.single.version, 2);
      expect(artifacts.single.title, 'First');
      expect(artifacts.single.policy['maxHeight'], 320);
      expect(artifacts.single.definition['root'], 'next');
    });

    test('ignores a patch with the wrong base version', () {
      final events = <SessionLogEvent>[
        _call(1, 'call-a', 'ui_render', _tree()),
        _result(2, 'call-a', meta: {'ok': true}),
        _call(3, 'call-b', 'ui_patch', {'uiId': 'call-a', 'baseVersion': 2, 'ops': []}),
        _result(
          4,
          'call-b',
          meta: {
            'ok': true,
            'ui': {'uiId': 'call-a', 'version': 3, ..._tree()},
          },
        ),
      ];
      final artifacts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      expect(artifacts, hasLength(1));
      expect(artifacts.single.version, 1);
    });

    test('projects PTC dispatch sub-calls', () {
      final events = <SessionLogEvent>[
        UnknownEvent(1, DateTime(2026, 1, 1), 'tool/ptc-dispatch', {
          'name': 'ui_render',
          'subCallId': 'sub-a',
          'arguments': _tree(),
          'meta': {'ok': true},
        }),
      ];
      final artifacts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      expect(artifacts, hasLength(1));
      expect(artifacts.single.uiId, 'sub-a');
      expect(artifacts.single.version, 1);
    });

    test('maps PTC to the assistant message seq when the call is listed there', () {
      final events = <SessionLogEvent>[
        _assistantWithToolCall(1, 'root-a', 'run_code'),
        UnknownEvent(2, DateTime(2026, 1, 1), 'tool/ptc-dispatch', {
          'name': 'ui_render',
          'subCallId': 'sub-a',
          'rootCallId': 'root-a',
          'arguments': _tree(),
          'meta': {'ok': true},
        }),
      ];
      final artifacts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      expect(artifacts, hasLength(1));
      expect(artifacts.single.originSeq, 1);
    });

    test('patches one composition block without touching its siblings', () {
      final composition = {
        'title': 'Composition',
        'blocks': [
          {'id': 'text', 'type': 'markdown', 'text': 'intro'},
          {'id': 'card', 'type': 'catalog', ..._tree()},
        ],
      };
      final events = <SessionLogEvent>[
        _call(1, 'compose-a', 'ui_compose', composition),
        _result(2, 'compose-a', meta: {'ok': true}),
        _call(3, 'patch-a', 'ui_patch', {'uiId': 'compose-a#card', 'baseVersion': 1, 'ops': []}),
        _result(
          4,
          'patch-a',
          meta: {
            'ok': true,
            'ui': {'uiId': 'compose-a#card', 'version': 2, ..._tree(root: 'next')},
          },
        ),
      ];
      final artifacts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      expect(artifacts, hasLength(1));
      final definition = artifacts.single.definition;
      expect(artifacts.single.version, 2);
      expect((definition['blocks'] as List).length, 2);
      final updated = (definition['blocks'] as List)[1] as Map;
      expect(updated['root'], 'next');
      expect((definition['blocks'] as List)[0]['text'], 'intro');
    });

    test('incremental projection matches a full replay', () {
      final events = <SessionLogEvent>[
        _call(1, 'call-a', 'ui_render', {'title': 'First', ..._tree()}),
        _result(2, 'call-a', meta: {'ok': true}),
        _call(3, 'call-b', 'ui_patch', {'uiId': 'call-a', 'baseVersion': 1, 'ops': []}),
        _result(
          4,
          'call-b',
          meta: {
            'ok': true,
            'ui': {'uiId': 'call-a', 'version': 2, ..._tree(root: 'next')},
          },
        ),
      ];
      final full = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      final incremental = IntelligentUiProjection(hostId: 'h', sessionId: 's');
      incremental.applyAll(events.take(2));
      incremental.applyPending(events.skip(2));
      expect(
        incremental.artifacts.map((a) => '${a.uiId}:${a.version}:${a.definition['root']}'),
        full.map((a) => '${a.uiId}:${a.version}:${a.definition['root']}'),
      );
    });

    test('rejects widget html containing a script tag', () {
      final events = <SessionLogEvent>[
        _call(1, 'widget-a', 'ui_render_widget', {'html': '<script>alert(1)</script>'}),
        _result(2, 'widget-a', meta: {'ok': true}),
      ];
      expect(IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's'), isEmpty);
    });
  });
}
