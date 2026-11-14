import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/state/intelligent_ui.dart';
import 'package:dsh_app/ui/theme/app_theme.dart';
import 'package:dsh_app/ui/chat/intelligent_ui/intelligent_ui_native.dart';

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

    test('incremental PTC dispatch anchors to the assistant message seq', () {
      // 实时流里增量投影只喂 assistant 锚点 + ptc-dispatch（chat_state 只收集
      // 这些进增量队列）；originSeq 必须与全量重放一致，否则子卡挂不上工具行。
      final assistant = _assistantWithToolCall(1, 'root-a', 'run_code');
      final dispatch = UnknownEvent(2, DateTime(2026, 1, 1), 'tool/ptc-dispatch', {
        'name': 'ui_render',
        'subCallId': 'sub-a',
        'rootCallId': 'root-a',
        'arguments': _tree(),
        'meta': {'ok': true},
      });
      final incremental = IntelligentUiProjection(hostId: 'h', sessionId: 's');
      incremental.applyAll([assistant]);
      incremental.applyPending([dispatch]);
      expect(incremental.artifacts, hasLength(1));
      expect(incremental.artifacts.single.originSeq, 1);
    });

    test('rejects widget html containing a script tag', () {
      final events = <SessionLogEvent>[
        _call(1, 'widget-a', 'ui_render_widget', {'html': '<script>alert(1)</script>'}),
        _result(2, 'widget-a', meta: {'ok': true}),
      ];
      expect(IntelligentUiProjector.project(events, hostId: 'h', sessionId: 's'), isEmpty);
    });
  });
  group('PortableUiAdapter', () {
    ToolChatItem item(Object? meta) => ToolChatItem(
      callId: 'call-portable',
      name: 'render_ui',
      arguments: '{}',
      status: ToolStatus.succeeded,
      seq: 9,
      resultParts: const [],
      meta: meta,
    );

    test('adapts a dsh-go/portable html envelope to a widget artifact', () {
      final artifact = PortableUiAdapter.fromTool(
        item({
          'dsh-go/portable': {'kind': 'html', 'title': 'Portable card', 'html': '<p>hello</p>'},
        }),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.kind, IntelligentUiKind.widget);
      expect(artifact.definition['html'], '<p>hello</p>');
      expect(artifact.title, 'Portable card');
    });

    test('rejects scripts and unknown portable kinds', () {
      expect(
        PortableUiAdapter.fromTool(
          item({
            'dsh-go/portable': {'kind': 'html', 'html': '<script>x</script>'},
          }),
        ),
        isNull,
      );
      expect(
        PortableUiAdapter.fromTool(
          item({
            'dsh-go/portable': {'kind': 'react', 'html': '<p>x</p>'},
          }),
        ),
        isNull,
      );
    });

    test('adapts a bare html meta to a widget artifact', () {
      final artifact = PortableUiAdapter.fromTool(
        item({'html': '<p>plain html</p>'}),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.kind, IntelligentUiKind.widget);
      expect(artifact.definition['html'], contains('<p>plain html</p>'));
      expect(artifact.definition['initialHeight'], 48);
      expect(artifact.uiId, 'call-portable');
      expect(artifact.version, 1);
      expect(artifact.seq, 9);
      expect(artifact.originSeq, 9);
    });

    test('adapts a meta.widget html with css and title', () {
      final artifact = PortableUiAdapter.fromTool(
        item({
          'widget': {
            'html': '<div class="w">widget body</div>',
            'css': '.w{color:#123456}',
            'title': 'Widget title',
          },
        }),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.definition['html'], contains('<div class="w">widget body</div>'));
      expect(artifact.definition['css'], '.w{color:#123456}');
      expect(artifact.title, 'Widget title');
    });

    test('adapts a meta.fragment as html', () {
      final artifact = PortableUiAdapter.fromTool(
        item({'fragment': '<section>fragment body</section>'}),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.definition['html'], contains('<section>fragment body</section>'));
    });

    test('renders a meta.card structured payload', () {
      final artifact = PortableUiAdapter.fromTool(
        item({
          'card': {
            'title': 'Card title',
            'fields': [
              {'label': 'Region', 'value': 'APAC'},
            ],
            'metrics': [
              {'label': 'Requests', 'value': '1,204', 'delta': '+12%', 'trend': 'up'},
              {'label': 'Errors', 'value': '3', 'delta': '-9%', 'trend': 'down'},
              {'label': 'Ratio', 'value': '99.9%', 'trend': 'flat'},
            ],
            'tables': [
              {
                'title': '明细表',
                'columns': ['Host', 'Count'],
                'rows': [
                  ['a.example', 12],
                  ['b.example', 3],
                ],
              },
            ],
            'items': [
              'first item',
              {'label': 'Paired', 'value': 'yes'},
            ],
            'markdown':
                '# 一级标题\n\n<b>x</b> **粗体** *斜体* `code`\n\n'
                '- 无序项\n\n1. 有序项\n\n'
                '```\nfence\n```\n\n[链接](https://example.com)',
          },
        }),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.definition['css'], contains('dsh-portable'));
      final html = artifact.definition['html'] as String;
      // 各字段渲染成对应标签
      expect(html, contains('<h2'));
      expect(html, contains('Card title'));
      expect(html, contains('Region'));
      expect(html, contains('APAC'));
      expect(html, contains('dsh-portable-metrics'));
      expect(html, contains('Requests'));
      expect(html, contains('1,204'));
      expect(html, contains('up'));
      expect(html, contains('down'));
      expect(html, contains('<table'));
      expect(html, contains('a.example'));
      expect(html, contains('<li'));
      expect(html, contains('first item'));
      expect(html, contains('<h1'));
      expect(html, contains('<strong'));
      expect(html, contains('<em'));
      expect(html, contains('<code'));
      expect(html, contains('<ul'));
      expect(html, contains('<ol'));
      expect(html, contains('href="https://example.com"'));
      // 文本先转义再套标签：<b>x</b> 不得原样透传
      expect(html, contains('&lt;b&gt;x&lt;/b&gt;'));
      expect(html, isNot(contains('<b>')));
    });

    test('renders a top-level kind=card payload', () {
      final artifact = PortableUiAdapter.fromTool(
        item({
          'kind': 'card',
          'title': 'Top card',
          'fields': [
            {'label': 'Count', 'value': '7'},
          ],
        }),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.definition['html'], contains('<h2'));
      expect(artifact.definition['html'], contains('Top card'));
      expect(artifact.definition['html'], contains('Count'));
      expect(artifact.definition['html'], contains('7'));
    });

    test('skips metas that already carry an intelligent-ui envelope', () {
      for (final meta in <Map<String, Object?>>[
        {'dsh-go/view': {'root': 'root'}, 'html': '<p>x</p>'},
        {'dsh-go/media': {'kind': 'image'}, 'html': '<p>x</p>'},
        {'ui': {'root': 'root'}, 'html': '<p>x</p>'},
        {'dsh-go/view': {'root': 'root'}, 'card': {'title': 'T'}},
      ]) {
        expect(PortableUiAdapter.fromTool(item(meta), hostId: 'h', sessionId: 's'), isNull);
      }
      // 键存在但值为 null 不算被占用，仍按 html 识别。
      final artifact = PortableUiAdapter.fromTool(
        item({'ui': null, 'html': '<p>kept</p>'}),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.definition['html'], contains('kept'));
    });

    test('prefers dsh-go/portable over a bare html meta', () {
      final artifact = PortableUiAdapter.fromTool(
        item({
          'html': '<p>loose html</p>',
          'dsh-go/portable': {
            'kind': 'html',
            'html': '<p>portable html</p>',
            'policy': {'allowMedia': false},
          },
        }),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.definition['html'], contains('portable html'));
      expect(artifact.definition['html'], isNot(contains('loose html')));
      expect(artifact.policy['allowMedia'], isFalse);
    });

    test('rejects scripts in html, widget html and fragment', () {
      for (final meta in <Map<String, Object?>>[
        {'html': '<p>x</p><script>alert(1)</script>'},
        {
          'widget': {'html': '<SCRIPT>alert(1)</SCRIPT>'},
        },
        {'fragment': '<script\nalert(1)</script>'},
      ]) {
        expect(PortableUiAdapter.fromTool(item(meta), hostId: 'h', sessionId: 's'), isNull);
      }
    });

    test('caps structured tables at 50 rows and 12 columns', () {
      final artifact = PortableUiAdapter.fromTool(
        item({
          'card': {
            'tables': [
              {
                'columns': List<String>.generate(13, (c) => 'col$c'),
                'rows': [
                  for (var r = 0; r < 60; r++) ['row$r', ...List<Object?>.generate(13, (c) => 'v$r-$c')],
                ],
              },
            ],
          },
        }),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      final html = artifact!.definition['html'] as String;
      expect(html, contains('row0'));
      expect(html, contains('row49'));
      expect(html, isNot(contains('row50')));
      expect(html, contains('v0-10'));
      expect(html, isNot(contains('v0-11')));
    });

    test('returns null when there is nothing to render', () {
      // 结构化数据一个字段都没有
      expect(PortableUiAdapter.fromTool(item({'dsh-go/portable': {'kind': 'structured'}})), isNull);
      expect(PortableUiAdapter.fromTool(item({'card': const {}})), isNull);
      expect(PortableUiAdapter.fromTool(item({'kind': 'card', 'title': ''})), isNull);
      // 空串 html / widget / fragment 继续往下找，找不到任何内容时返回 null
      expect(PortableUiAdapter.fromTool(item({'html': ''})), isNull);
      expect(PortableUiAdapter.fromTool(item({'widget': {'html': ''}})), isNull);
      expect(PortableUiAdapter.fromTool(item({'fragment': '', 'html': ''})), isNull);
      expect(PortableUiAdapter.fromTool(item(const {})), isNull);
      expect(PortableUiAdapter.fromTool(item(null)), isNull);
      // 空串 html 跳过，后面的 fragment 仍然生效
      final artifact = PortableUiAdapter.fromTool(
        item({'html': '', 'fragment': '<p>fallback</p>'}),
        hostId: 'h',
        sessionId: 's',
      );
      expect(artifact, isNotNull);
      expect(artifact!.definition['html'], contains('fallback'));
    });
  });

  group('IntelligentUiNativePreview', () {
    IntelligentUiArtifact artifact(List<Map<String, Object?>> components, String root) => IntelligentUiArtifact(
      kind: IntelligentUiKind.declarative,
      hostId: 'h',
      sessionId: 's',
      uiId: 'native',
      version: 1,
      definition: {'root': root, 'components': components},
      seq: 1,
    );

    test('accepts a simple Text/Stat/Table tree', () {
      expect(
        IntelligentUiNativePreview.supports(
          artifact([
            {
              'id': 'root',
              'type': 'Stack',
              'children': ['title', 'stat'],
            },
            {
              'id': 'title',
              'type': 'Text',
              'props': {'text': 'Title'},
            },
            {
              'id': 'stat',
              'type': 'Stat',
              'props': {'label': 'Users', 'value': '42'},
            },
          ], 'root'),
        ),
        isTrue,
      );
    });

    test('rejects charts and unsupported nodes', () {
      expect(
        IntelligentUiNativePreview.supports(
          artifact([
            {
              'id': 'root',
              'type': 'Chart',
              'props': {'kind': 'bar'},
            },
          ], 'root'),
        ),
        isFalse,
      );
    });

    testWidgets('renders Text markdown instead of raw link syntax', (tester) async {
      final ui = artifact([
        {
          'id': 'root',
          'type': 'Text',
          'props': {'text': '正文包含一个 Markdown 链接：[Example](https://example.com)'},
        },
      ], 'root');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(body: Builder(builder: (context) => IntelligentUiNativePreview.tryBuild(context, ui)!)),
        ),
      );
      expect(
        find.byWidgetPredicate((widget) => widget is Text && (widget.data?.contains('[Example]') ?? false)),
        findsNothing,
      );
    });
  });
}
