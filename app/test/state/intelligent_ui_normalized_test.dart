import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/state/intelligent_ui.dart';

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

ToolResultEvent _result(int seq, String callId, {Map<String, Object?>? meta}) => ToolResultEvent(
      seq,
      DateTime(2026, 1, 1),
      {
        'meta': <String, Object?>{'ok': true, ...?meta},
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

Map<String, Object?> _tree(String text) => {
      'root': 'root',
      'components': [
        {
          'id': 'root',
          'type': 'text',
          'props': {'text': text},
        },
      ],
    };

void main() {
  group('IntelligentUiProjector normalized fallback', () {
    test('ui_render 优先使用合法 normalized（args 非法时）', () {
      final badArgs = <String, Object?>{
        'root': 'root',
        'components': [
          {
            'id': 'root',
            'type': 'text',
            'props': <Object?>[], // props 非 Map → _validTree 拒绝
          },
        ],
      };
      final normalized = _tree('from-normalized');
      final events = <SessionLogEvent>[
        _call(1, 'c1', 'ui_render', badArgs),
        _result(2, 'c1', meta: {'normalized': normalized}),
      ];
      final arts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      expect(arts, hasLength(1));
      final comps = arts.single.definition['components'] as List;
      expect((comps.single as Map)['props'], {'text': 'from-normalized'});
    });

    test('ui_render 同时合法时 normalized 取胜', () {
      final args = _tree('from-args');
      final normalized = _tree('from-normalized');
      final events = <SessionLogEvent>[
        _call(1, 'c2', 'ui_render', args),
        _result(2, 'c2', meta: {'normalized': normalized}),
      ];
      final arts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      final comps = arts.single.definition['components'] as List;
      expect((comps.single as Map)['props'], {'text': 'from-normalized'});
    });

    test('ui_compose 使用合法 normalized（args 非法时）', () {
      final badArgs = <String, Object?>{
        'blocks': [
          {'id': 'b1', 'type': 'bogus', 'text': 'x'}, // 未知 type → _validComposition 拒绝
        ],
      };
      final normalized = <String, Object?>{
        'title': 'T',
        'blocks': [
          {'id': 'b1', 'type': 'markdown', 'text': 'hello'},
        ],
      };
      final events = <SessionLogEvent>[
        _call(1, 'c3', 'ui_compose', badArgs),
        _result(2, 'c3', meta: {'normalized': normalized}),
      ];
      final arts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      expect(arts, hasLength(1));
      final blocks = arts.single.definition['blocks'] as List;
      expect((blocks.single as Map)['text'], 'hello');
    });

    test('normalized 非法时退回 args；都非法则不生成', () {
      final args = _tree('only-args');
      final badNormalized = <String, Object?>{
        'root': 'root',
        'components': <Object?>[],
      };
      final events = <SessionLogEvent>[
        _call(1, 'c4', 'ui_render', args),
        _result(2, 'c4', meta: {'normalized': badNormalized}),
      ];
      final arts = IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's');
      expect(arts, hasLength(1));
      final comps = arts.single.definition['components'] as List;
      expect((comps.single as Map)['props'], {'text': 'only-args'});

      final badArgs = <String, Object?>{
        'root': 'r',
        'components': <Object?>[],
      };
      final events2 = <SessionLogEvent>[
        _call(1, 'c5', 'ui_render', badArgs),
        _result(2, 'c5', meta: {'normalized': badNormalized}),
      ];
      expect(IntelligentUiProjector.project(events2, hostId: 'h', sessionId: 's'), isEmpty);
    });
  });
}
