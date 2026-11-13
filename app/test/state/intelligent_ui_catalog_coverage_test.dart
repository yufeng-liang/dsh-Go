import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/state/intelligent_ui.dart';

const _catalogTypes = <String>[
  'Card',
  'Stack',
  'Grid',
  'Tabs',
  'Text',
  'Code',
  'Alert',
  'Badge',
  'Divider',
  'Stat',
  'Progress',
  'List',
  'Table',
  'Chart',
  'Scatter',
  'Heatmap',
  'CodeDiff',
  'FileTree',
  'JsonView',
  'Map',
  'Image',
  'Gallery',
  'Video',
  'Button',
  'Choice',
  'Form',
  'Timeline',
  'Plot',
  'Math',
  'Mermaid',
];

String _json(Object? value) => const JsonEncoder().convert(value);

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

ToolResultEvent _result(int seq, String callId) => ToolResultEvent(
  seq,
  DateTime(2026, 1, 1),
  const {
    'meta': {'ok': true},
  },
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
  test('the portable renderer catalog has a valid tree for every type', () {
    final children = <Map<String, Object?>>[];
    for (var i = 0; i < _catalogTypes.length; i++) {
      children.add({'id': 'c$i', 'type': _catalogTypes[i], 'props': <String, Object?>{}});
    }
    final tree = <String, Object?>{
      'root': 'root',
      'components': [
        {
          'id': 'root',
          'type': 'Stack',
          'props': <String, Object?>{},
          'children': children.map((c) => c['id']).toList(),
        },
        ...children,
      ],
    };
    final events = <SessionLogEvent>[_call(1, 'call-catalog', 'ui_render', tree), _result(2, 'call-catalog')];

    final artifacts = IntelligentUiProjector.project(events, hostId: 'host', sessionId: 'session');
    expect(artifacts, hasLength(1));
    final components = artifacts.single.definition['components'] as List;
    expect(components, hasLength(_catalogTypes.length + 1));
    for (final type in _catalogTypes) {
      expect(components.whereType<Map>().where((node) => node['type'] == type), isNotEmpty, reason: type);
    }
  });
}
