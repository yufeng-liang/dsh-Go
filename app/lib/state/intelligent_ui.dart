import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';

/// `deepseek-harness-intelligent-ui` 便携渲染器使用的 UI 工件。
///
/// 与上游 `src/portable/artifacts.js` 的输出保持同构：WebView 只接受这个
/// 结构，由 renderer 负责具体的 catalog / widget / composition 渲染。
enum IntelligentUiKind { declarative, widget, composition }

/// Tools that create an intelligent-UI card. `ui_patch` updates an existing
/// card and never creates a new one.
const intelligentUiToolNames = <String>{'ui_render', 'ui_render_widget', 'ui_compose'};

bool isIntelligentUiTool(ToolChatItem item) =>
    item.status == ToolStatus.succeeded && intelligentUiToolNames.contains(item.name);

class IntelligentUiArtifact {
  const IntelligentUiArtifact({
    required this.kind,
    required this.hostId,
    required this.sessionId,
    required this.uiId,
    required this.version,
    required this.definition,
    required this.seq,
    this.title,
    this.policy = const {},
    this.turn,
    this.updatedTurn,
    this.originSeq,
  });

  final IntelligentUiKind kind;
  final String hostId;
  final String sessionId;
  final String uiId;
  final int version;
  final Map<String, Object?> definition;
  final int seq;
  final String? title;
  final Map<String, Object?> policy;
  final Object? turn;
  final Object? updatedTurn;

  /// 原始工具调用事件（或其 PTC 根调用）的 seq；用于把 PTC 产生的卡片挂回
  /// 父工具行。直接调用时等于调用事件 seq。
  final int? originSeq;

  Map<String, Object?> toRendererJson() => {
    'kind': kind.name,
    'uiId': uiId,
    'version': version,
    if (title != null) 'title': title,
    'definition': definition,
    if (policy.isNotEmpty) 'policy': policy,
  };

  IntelligentUiArtifact copyWith({
    int? version,
    Map<String, Object?>? definition,
    String? title,
    Map<String, Object?>? policy,
    Object? turn,
    Object? updatedTurn,
    int? seq,
  }) => IntelligentUiArtifact(
    kind: kind,
    hostId: hostId,
    sessionId: sessionId,
    uiId: uiId,
    version: version ?? this.version,
    definition: definition ?? this.definition,
    seq: seq ?? this.seq,
    title: title ?? this.title,
    policy: policy ?? this.policy,
    turn: turn ?? this.turn,
    updatedTurn: updatedTurn ?? this.updatedTurn,
    originSeq: originSeq,
  );
}

/// 从会话事件日志投影智能 UI 工件。
///
/// 对应上游 `src/portable/artifacts.js` 的 `projectNativeUiEvents`。每次都
/// 从完整日志重算，因此历史分页、重连快照和实时事件走同一条路径，不需要
/// 在客户端保存脆弱的增量状态。
/// 通用聊天 UI 适配器：把工具结果里的 presentationMeta 转成受限的 widget 卡。
///
/// 第三方插件不必依赖 intelligent-ui 的 renderer：只要在 presentationMeta 的
/// dsh-go/portable 里给出可序列化的 HTML/结构化字段，或者在 meta 上直接挂
/// html / widget.html / fragment / card，App 就能用现有的智能 UI 卡片壳渲染。
/// 识别顺序见 docs/plugins/portable-ui.md：优先级 1–3（dsh-go/view、
/// dsh-go/media、ui）由别的适配器负责，这里直接让位。
class PortableUiAdapter {
  const PortableUiAdapter._();

  /// 单张卡片的 HTML 上限：超了就整张放弃，不出半张卡。
  static const _maxHtmlChars = 60000;

  /// structured 表格的截断口径。
  static const _maxTableRows = 50;
  static const _maxTableColumns = 12;

  /// 卡片初始高度：真正的排版交给 WebView，先给最小值再由渲染器量高。
  static const _initialHeight = 48;

  /// 优先级 1–3 的 meta 键：任何一个非 null 都不该由 portable 出卡。
  static const _reservedKeys = ['dsh-go/view', 'dsh-go/media', 'ui'];

  /// 结构化字段共用的样式（.dsh-portable 一族）。
  static const _css =
      '.dsh-portable{font:13px sans-serif;line-height:1.45;padding:8px;word-break:break-word}'
      '.dsh-portable h2{font-size:15px;margin:0 0 8px}'
      '.dsh-portable h3{font-size:13px;margin:12px 0 6px}'
      '.dsh-portable p{margin:0 0 6px}'
      '.dsh-portable strong{font-weight:600}'
      '.dsh-portable-metrics{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0}'
      '.dsh-portable-metric{display:flex;flex-direction:column;gap:2px;min-width:88px;padding:8px 10px;'
      'border:1px solid rgba(127,127,127,.32);border-radius:8px}'
      '.dsh-portable-metric-label{font-size:12px;opacity:.72}'
      '.dsh-portable-metric-value{font-size:18px;font-weight:600}'
      '.dsh-portable-metric-delta{font-size:12px}'
      '.dsh-portable-trend-up .dsh-portable-metric-delta{color:#2e7d32}'
      '.dsh-portable-trend-down .dsh-portable-metric-delta{color:#c62828}'
      '.dsh-portable-trend-flat .dsh-portable-metric-delta{color:#757575}'
      '.dsh-portable-table{width:100%;border-collapse:collapse;margin:8px 0;font-size:12px}'
      '.dsh-portable-table th,.dsh-portable-table td{border:1px solid rgba(127,127,127,.32);padding:4px 6px;'
      'text-align:left;vertical-align:top}'
      '.dsh-portable-table th{font-weight:600;background:rgba(127,127,127,.12)}'
      '.dsh-portable-items{margin:8px 0;padding-left:18px}'
      '.dsh-portable-items li{margin:2px 0}'
      '.dsh-portable pre{background:rgba(127,127,127,.12);padding:8px;border-radius:6px;overflow:auto}'
      '.dsh-portable code{font-family:monospace}'
      '.dsh-portable a{color:#1a73e8}';

  /// 正文转义只处理会破坏文本节点的字符，斜杠保持原样。
  static const _escape = HtmlEscape(HtmlEscapeMode.element);

  /// 属性值转义额外处理双引号，链接不会截断 href。
  static const _attrEscape = HtmlEscape(HtmlEscapeMode.attribute);

  static final _script = RegExp(r'<script[\s>]', caseSensitive: false);
  static final _codeSpan = RegExp(r'\x60([^\x60]+)\x60');
  static final _link = RegExp(r'\[([^\]]+)\]\((https://[^\s()]+)\)');
  static final _bold = RegExp(r'\*\*([^*]+)\*\*');
  static final _italic = RegExp(r'\*([^*\n]+)\*');
  static final _heading = RegExp(r'^(#{1,3})\s+(.+)$');
  static final _bullet = RegExp(r'^[-*]\s+(.+)$');
  static final _ordered = RegExp(r'^\d+\.\s+(.+)$');
  static const _fence = '\x60\x60\x60';

  static IntelligentUiArtifact? fromTool(
    ToolChatItem item, {
    String hostId = '',
    String sessionId = '',
  }) {
    final meta = item.meta;
    final seq = item.seq;
    if (meta is! Map || seq == null) return null;
    // intelligent-ui 自己的工具由投影器出卡；再走 portable 会在同一行出两张。
    if (intelligentUiToolNames.contains(item.name)) return null;
    for (final key in _reservedKeys) {
      if (meta[key] != null) return null;
    }

    // 优先级 4：dsh-go/portable envelope。出现即终局：kind 不认识也不往下找。
    if (meta['dsh-go/portable'] is Map) {
      final map = IntelligentUiProjector._asMap(meta['dsh-go/portable'])!;
      return _artifact(
        item,
        seq,
        hostId,
        sessionId,
        definition: switch (IntelligentUiProjector._asString(map['kind'])) {
          'html' => _htmlDefinition(map),
          'structured' => _structuredDefinition(map),
          'media' => _mediaDefinition(map),
          _ => null,
        },
        title: IntelligentUiProjector._asString(map['title']),
        policy: IntelligentUiProjector._asMap(map['policy']) ?? const <String, Object?>{},
      );
    }

    final policy = IntelligentUiProjector._asMap(meta['policy']) ?? const <String, Object?>{};

    // 优先级 5：原始 html / widget.html / fragment，取第一个可用的。
    final fragment = _fragmentDefinition(meta);
    if (fragment != null) {
      return _artifact(
        item,
        seq,
        hostId,
        sessionId,
        definition: fragment.$1,
        title: fragment.$2,
        policy: policy,
      );
    }

    // 优先级 6：结构化卡片。card 是数据源本身，也可以整个 meta 就是一张卡。
    final card = _cardDefinition(meta);
    if (card == null) return null;
    return _artifact(
      item,
      seq,
      hostId,
      sessionId,
      definition: card.$1,
      title: card.$2,
      policy: policy,
    );
  }

  /// 统一产物：widget 卡，uiId 用调用 id，definition 必须过 widget 校验。
  static IntelligentUiArtifact? _artifact(
    ToolChatItem item,
    int seq,
    String hostId,
    String sessionId, {
    required Map<String, Object?>? definition,
    required String? title,
    required Map<String, Object?> policy,
  }) {
    if (definition == null || !IntelligentUiProjector._validWidget(definition)) return null;
    return IntelligentUiArtifact(
      kind: IntelligentUiKind.widget,
      hostId: hostId,
      sessionId: sessionId,
      uiId: item.callId,
      version: 1,
      definition: definition,
      seq: seq,
      title: title,
      policy: policy,
      originSeq: seq,
    );
  }

  static Map<String, Object?> _htmlCard(String html, {String? css}) => {
    'html': html,
    'css': css ?? '',
    'initialHeight': _initialHeight,
  };

  /// 插件给的 HTML 片段：必须是非空字符串且不含 script 标签。
  static String? _htmlOf(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return _script.hasMatch(value) ? null : value;
  }

  static Map<String, Object?>? _htmlDefinition(Map<String, Object?> map) {
    final html = _htmlOf(map['html']);
    if (html == null) return null;
    return _htmlCard(html, css: IntelligentUiProjector._asString(map['css']));
  }

  static Map<String, Object?>? _mediaDefinition(Map<String, Object?> map) {
    final url = IntelligentUiProjector._asString(map['url']);
    if (url == null || !url.startsWith('https://')) return null;
    final src = _text(url);
    return _htmlCard(
      '<img class="dsh-portable-media" src="$src" alt="">',
      css: '.dsh-portable-media{display:block;max-width:100%;height:auto;border-radius:8px}',
    );
  }

  /// 优先级 5：原始 html / widget.html / fragment，按顺序取第一个可用的；
  /// 空串、非字符串、带 script 的候选跳过，继续往下找。
  static (Map<String, Object?>, String?)? _fragmentDefinition(Map<Object?, Object?> meta) {
    final title = IntelligentUiProjector._asString(meta['title']);
    final html = _htmlOf(meta['html']);
    if (html != null) return (_htmlCard(html), title);
    if (meta['widget'] is Map) {
      final widget = IntelligentUiProjector._asMap(meta['widget'])!;
      final widgetHtml = _htmlOf(widget['html']);
      if (widgetHtml != null) {
        return (
          _htmlCard(widgetHtml, css: IntelligentUiProjector._asString(widget['css'])),
          IntelligentUiProjector._asString(widget['title']),
        );
      }
    }
    final fragment = _htmlOf(meta['fragment']);
    if (fragment != null) return (_htmlCard(fragment), title);
    return null;
  }

  /// 优先级 6：card 自带结构化数据；或 kind 标成 card，整个 meta 就是数据源。
  static (Map<String, Object?>, String?)? _cardDefinition(Map<Object?, Object?> meta) {
    final outerTitle = IntelligentUiProjector._asString(meta['title']);
    if (meta['card'] is Map) {
      final card = IntelligentUiProjector._asMap(meta['card'])!;
      final definition = _structuredDefinition(card);
      if (definition == null) return null;
      return (definition, IntelligentUiProjector._asString(card['title']) ?? outerTitle);
    }
    if (meta['kind'] == 'card') {
      final data = IntelligentUiProjector._asMap(meta)!;
      final definition = _structuredDefinition(data);
      if (definition == null) return null;
      return (definition, IntelligentUiProjector._asString(data['title']) ?? outerTitle);
    }
    return null;
  }

  static Map<String, Object?>? _structuredDefinition(Map<String, Object?> data) {
    final html = _structuredHtml(data);
    return html == null ? null : _htmlCard(html, css: _css);
  }

  /// 结构化数据转 HTML：title / fields / metrics / tables / items / markdown。
  /// 所有文本先转义再套标签，插件给的内容不会被当成标签解析。
  static String? _structuredHtml(Map<String, Object?> data) {
    final buffer = StringBuffer();
    final title = IntelligentUiProjector._asString(data['title']);
    if (title != null && title.isNotEmpty) buffer.write('<h2>${_text(title)}</h2>');

    for (final field in IntelligentUiProjector._asList(data['fields'])) {
      final map = IntelligentUiProjector._asMap(field);
      if (map == null) continue;
      final label = _cellText(map['label']) ?? '';
      final value = _cellText(map['value']) ?? '';
      if (label.isEmpty && value.isEmpty) continue;
      buffer.write('<p><strong>${_text(label)}</strong> ${_text(value)}</p>');
    }

    final metrics = StringBuffer();
    for (final metric in IntelligentUiProjector._asList(data['metrics'])) {
      final map = IntelligentUiProjector._asMap(metric);
      if (map == null) continue;
      final label = _cellText(map['label']) ?? '';
      final value = _cellText(map['value']) ?? '';
      if (label.isEmpty && value.isEmpty) continue;
      final delta = _cellText(map['delta']) ?? '';
      final trend = _trend(map['trend']);
      final className = trend == null ? 'dsh-portable-metric' : 'dsh-portable-metric dsh-portable-trend-$trend';
      metrics
        ..write('<div class="$className">')
        ..write('<span class="dsh-portable-metric-label">${_text(label)}</span>')
        ..write('<span class="dsh-portable-metric-value">${_text(value)}</span>');
      if (delta.isNotEmpty) metrics.write('<span class="dsh-portable-metric-delta">${_text(delta)}</span>');
      metrics.write('</div>');
    }
    if (metrics.isNotEmpty) buffer.write('<div class="dsh-portable-metrics">$metrics</div>');

    for (final table in IntelligentUiProjector._asList(data['tables'])) {
      final map = IntelligentUiProjector._asMap(table);
      if (map == null) continue;
      final columns = <String>[];
      for (final column in IntelligentUiProjector._asList(map['columns'])) {
        if (columns.length >= _maxTableColumns) break;
        columns.add(_cellText(column) ?? '');
      }
      if (columns.isEmpty) continue;
      final heading = IntelligentUiProjector._asString(map['title']);
      if (heading != null && heading.isNotEmpty) buffer.write('<h3>${_text(heading)}</h3>');
      buffer.write('<table class="dsh-portable-table"><thead><tr>');
      for (final column in columns) {
        buffer.write('<th>${_text(column)}</th>');
      }
      buffer.write('</tr></thead><tbody>');
      var shown = 0;
      for (final row in IntelligentUiProjector._asList(map['rows'])) {
        if (shown >= _maxTableRows) break;
        final cells = IntelligentUiProjector._asList(row);
        if (cells.isEmpty) continue;
        shown++;
        buffer.write('<tr>');
        // 每行按表头列数截断，表头和单元格的列数才一致。
        for (var i = 0; i < cells.length && i < columns.length; i++) {
          buffer.write('<td>${_text(_cellText(cells[i]) ?? '')}</td>');
        }
        buffer.write('</tr>');
      }
      buffer.write('</tbody></table>');
    }

    final items = StringBuffer();
    for (final entry in IntelligentUiProjector._asList(data['items'])) {
      if (entry is String) {
        if (entry.isEmpty) continue;
        items.write('<li>${_text(entry)}</li>');
        continue;
      }
      final map = IntelligentUiProjector._asMap(entry);
      if (map == null) continue;
      final label = _cellText(map['label']) ?? '';
      final value = _cellText(map['value']) ?? '';
      if (label.isEmpty && value.isEmpty) continue;
      items.write('<li><strong>${_text(label)}</strong>${value.isEmpty ? '' : ' ${_text(value)}'}</li>');
    }
    if (items.isNotEmpty) buffer.write('<ul class="dsh-portable-items">$items</ul>');

    final markdown = IntelligentUiProjector._asString(data['markdown']);
    if (markdown != null && markdown.trim().isNotEmpty) buffer.write(_markdownHtml(markdown));

    if (buffer.isEmpty) return null;
    final html = '<div class="dsh-portable">$buffer</div>';
    return html.length > _maxHtmlChars ? null : html;
  }

  /// 极简 Markdown：段落、#/##/### 标题、粗体、斜体、行内代码、围栏代码块、
  /// 无序/有序列表和 https 链接。先转义再套标签，原始标签不会透传。
  static String _markdownHtml(String markdown) {
    final lines = markdown.split('\n');
    final buffer = StringBuffer();
    final paragraph = <String>[];
    var list = '';

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      buffer.write('<p>${paragraph.join('<br>')}</p>');
      paragraph.clear();
    }

    void closeList() {
      if (list.isEmpty) return;
      buffer.write('</$list>');
      list = '';
    }

    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.startsWith(_fence)) {
        flushParagraph();
        closeList();
        index++;
        final code = <String>[];
        while (index < lines.length && !lines[index].trim().startsWith(_fence)) {
          code.add(lines[index]);
          index++;
        }
        // 跳过后面的围栏；文件末尾没闭合也照常输出。
        index++;
        buffer.write('<pre><code>${_text(code.join('\n'))}</code></pre>');
        continue;
      }
      if (trimmed.isEmpty) {
        flushParagraph();
        closeList();
        index++;
        continue;
      }
      final heading = _heading.firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        closeList();
        final level = heading.group(1)!.length;
        buffer.write('<h$level>${_inline(heading.group(2)!)}</h$level>');
        index++;
        continue;
      }
      final bullet = _bullet.firstMatch(trimmed);
      final ordered = bullet == null ? _ordered.firstMatch(trimmed) : null;
      if (bullet != null || ordered != null) {
        flushParagraph();
        final tag = bullet != null ? 'ul' : 'ol';
        if (list != tag) {
          closeList();
          buffer.write('<$tag>');
          list = tag;
        }
        buffer.write('<li>${_inline((bullet ?? ordered)!.group(1)!)}</li>');
        index++;
        continue;
      }
      closeList();
      paragraph.add(_inline(trimmed));
      index++;
    }
    flushParagraph();
    closeList();
    return buffer.toString();
  }

  /// 行内 Markdown：先按行内代码切分（代码里的星号不算强调），每段转义后
  /// 再套链接、粗体、斜体。
  static String _inline(String text) {
    final buffer = StringBuffer();
    var index = 0;
    for (final match in _codeSpan.allMatches(text)) {
      buffer.write(_linkify(text.substring(index, match.start)));
      buffer.write('<code>${_text(match.group(1)!)}</code>');
      index = match.end;
    }
    buffer.write(_linkify(text.substring(index)));
    return buffer.toString();
  }

  static String _linkify(String text) {
    final buffer = StringBuffer();
    var index = 0;
    for (final match in _link.allMatches(text)) {
      buffer.write(_emphasis(text.substring(index, match.start)));
      final href = _attrEscape.convert(match.group(2)!);
      buffer.write('<a href="$href">${_emphasis(match.group(1)!)}</a>');
      index = match.end;
    }
    buffer.write(_emphasis(text.substring(index)));
    return buffer.toString();
  }

  static String _emphasis(String text) => _text(text)
      .replaceAllMapped(_bold, (match) => '<strong>${match.group(1)!}</strong>')
      .replaceAllMapped(_italic, (match) => '<em>${match.group(1)!}</em>');

  static String _text(String value) => _escape.convert(value);

  /// 单元格 / 数值统一转文本；对象和数组不做渲染。
  static String? _cellText(Object? value) => switch (value) {
    null => null,
    final String text => text,
    final num number => '$number',
    final bool flag => '$flag',
    _ => null,
  };

  /// metrics 的 trend 只认 up / down / flat，其余按无趋势处理。
  static String? _trend(Object? value) {
    final trend = IntelligentUiProjector._asString(value);
    return trend == 'up' || trend == 'down' || trend == 'flat' ? trend : null;
  }
}

class IntelligentUiProjector {
  const IntelligentUiProjector._();

  static const _tools = {'ui_render', 'ui_render_widget', 'ui_compose', 'ui_patch'};

  /// Whether a tool call can produce a portable UI artifact.
  static bool isUiToolName(String name) => _tools.contains(name);
  static const _maxArgumentChars = 480000;
  static const _maxComponents = 300;
  static const _maxTreeDepth = 24;
  static const _maxCompositionBlocks = 24;
  static const _maxMarkdownChars = 60000;
  static const _maxCompositionChars = 200000;
  static final _blockId = RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$');

  static List<IntelligentUiArtifact> project(
    Iterable<SessionLogEvent> events, {
    required String hostId,
    required String sessionId,
  }) {
    final ordered = events.toList(growable: false)..sort((a, b) => a.seq.compareTo(b.seq));
    final rootTurns = <String, Object?>{};
    final rootSeqs = <String, int>{};
    final calls = <String, _UiCall>{};
    final settled = <_SettledCall>[];

    for (final event in ordered) {
      switch (event) {
        case AssistantMessageEvent(:final message, :final turn):
          for (final call in message.toolCalls) {
            rootTurns.putIfAbsent(call.id, () => turn);
            rootSeqs.putIfAbsent(call.id, () => event.seq);
          }
        case ToolCallEvent():
          rootTurns[event.callId] = event.turn;
          rootSeqs.putIfAbsent(event.callId, () => event.seq);
          if (!_tools.contains(event.name)) continue;
          final args = _argumentsOf(event.arguments);
          if (args != null) {
            calls[event.callId] = _UiCall(event.name, args, event.turn, event.seq);
          }
        case ToolResultEvent():
          final surfaceOp = event.surfaceOp;
          if (surfaceOp != null && surfaceOp != 'append') continue;
          final data = event.data;
          final id = _asString(event.message.source.raw['callId']) ?? _asString(data['callId']);
          if (id == null || id.isEmpty) continue;
          final call = calls[id];
          if (call == null) continue;
          final meta = _asMap(data['meta']);
          if (meta == null || meta['ok'] != true) continue;
          if (event.message.isError || data['isError'] == true || data['error'] != null) continue;
          settled.add(_SettledCall(id, call, meta, event.seq));
        case UnknownEvent() when event.type == 'tool/ptc-dispatch':
          final data = event.data;
          final name = _asString(data['name']);
          final subCallId = _asString(data['subCallId']);
          if (name == null || subCallId == null || !_tools.contains(name)) continue;
          if (data['isError'] == true || data['error'] != null) continue;
          final meta = _asMap(data['meta']);
          if (meta == null || meta['ok'] != true) continue;
          final args = _argumentsOf(data['arguments']);
          if (args == null) continue;
          final rootId = _asString(data['rootCallId']) ?? _asString(data['parentCallId']);
          final turn = data['turn'] ?? (rootId == null ? null : rootTurns[rootId]);
          final originSeq = rootId == null ? event.seq : (rootSeqs[rootId] ?? event.seq);
          if (turn != null) rootTurns[subCallId] = turn;
          rootSeqs[subCallId] = originSeq;
          settled.add(_SettledCall(subCallId, _UiCall(name, args, turn, originSeq), meta, event.seq));
        default:
          break;
      }
    }

    settled.sort((a, b) => a.seq.compareTo(b.seq));
    final latest = <String, IntelligentUiArtifact>{};
    final blockVersions = <String, int>{};

    for (final item in settled) {
      final args = item.call.args;
      switch (item.call.kind) {
        case 'ui_render':
          if (latest.containsKey(item.id) || !_validTree(args)) break;
          latest[item.id] = IntelligentUiArtifact(
            kind: IntelligentUiKind.declarative,
            hostId: hostId,
            sessionId: sessionId,
            uiId: item.id,
            version: 1,
            title: _asString(args['title']),
            definition: args,
            policy: _policyOf(item.meta),
            turn: item.call.turn,
            seq: item.seq,
            originSeq: item.call.originSeq,
          );
        case 'ui_render_widget':
          if (latest.containsKey(item.id) || !_validWidget(args)) break;
          latest[item.id] = IntelligentUiArtifact(
            kind: IntelligentUiKind.widget,
            hostId: hostId,
            sessionId: sessionId,
            uiId: item.id,
            version: 1,
            title: _asString(args['title']),
            definition: args,
            policy: _policyOf(item.meta),
            turn: item.call.turn,
            seq: item.seq,
            originSeq: item.call.originSeq,
          );
        case 'ui_compose':
          if (latest.containsKey(item.id) || !_validComposition(args)) break;
          final blocks = _asList(args['blocks']);
          latest[item.id] = IntelligentUiArtifact(
            kind: IntelligentUiKind.composition,
            hostId: hostId,
            sessionId: sessionId,
            uiId: item.id,
            version: 1,
            title: _asString(args['title']),
            definition: args,
            policy: _policyOf(item.meta),
            turn: item.call.turn,
            seq: item.seq,
            originSeq: item.call.originSeq,
          );
          for (final block in blocks) {
            final map = _asMap(block);
            if (map != null && _asString(map['type']) == 'catalog') {
              final blockId = _asString(map['id']);
              if (blockId != null) blockVersions['${item.id}#$blockId'] = 1;
            }
          }
        case 'ui_patch':
          _applyPatch(
            latest: latest,
            blockVersions: blockVersions,
            args: args,
            meta: item.meta,
            seq: item.seq,
            turn: item.call.turn,
          );
      }
    }

    final result = latest.values.toList(growable: false)..sort((a, b) => a.seq.compareTo(b.seq));
    return result;
  }

  static void _applyPatch({
    required Map<String, IntelligentUiArtifact> latest,
    required Map<String, int> blockVersions,
    required Map<String, Object?> args,
    required Map<String, Object?> meta,
    required int seq,
    required Object? turn,
  }) {
    final targetId = _asString(args['uiId']);
    final baseVersion = _asInt(args['baseVersion']);
    if (targetId == null || baseVersion == null) return;
    // 便携协议要求目标与调用 id 一致。PTC 子调用的 id 是 subCallId，因此
    // 以 targetId 为准，尤其要覆盖 `<composeId>#<blockId>` 形式。
    final hash = targetId.indexOf('#');
    final ownerId = hash < 0 ? targetId : targetId.substring(0, hash);
    final prior = latest[ownerId];
    if (prior == null) return;
    final expected = prior.kind == IntelligentUiKind.composition ? blockVersions[targetId] : prior.version;
    if (expected == null || expected != baseVersion) return;
    final snapshot = _asMap(meta['ui']);
    if (snapshot == null) return;
    if (_asString(snapshot['uiId']) != targetId) return;
    if (_asInt(snapshot['version']) != expected + 1) return;

    if (prior.kind == IntelligentUiKind.composition) {
      final blockId = hash < 0 ? null : targetId.substring(hash + 1);
      if (blockId == null || blockId.isEmpty || !_validTree(snapshot)) return;
      final blocks = _asList(prior.definition['blocks']).map((e) => _asMap(e)).toList(growable: false);
      final index = blocks.indexWhere((block) => _asString(block?['id']) == blockId);
      if (index < 0) return;
      final block = Map<String, Object?>.from(blocks[index]!);
      for (final key in const ['root', 'components']) {
        if (snapshot[key] is List || snapshot[key] is Map || snapshot[key] is String) block[key] = snapshot[key];
      }
      if (snapshot['title'] is String) block['title'] = snapshot['title'];
      if (snapshot['computed'] is List) block['computed'] = snapshot['computed'];
      final nextBlocks = blocks.map((e) => Map<String, Object?>.from(e!)).toList(growable: false);
      nextBlocks[index] = block;
      final definition = Map<String, Object?>.from(prior.definition)..['blocks'] = nextBlocks;
      latest[ownerId] = prior.copyWith(
        version: prior.version + 1,
        definition: definition,
        policy: _asMap(meta['policy']) ?? prior.policy,
        seq: seq,
        updatedTurn: turn,
      );
      blockVersions[targetId] = expected + 1;
      return;
    }

    if (!_validTree(snapshot)) return;
    final nextPolicy = _asMap(meta['policy']);
    latest[ownerId] = prior.copyWith(
      version: _asInt(snapshot['version'])!,
      definition: snapshot,
      title: _asString(snapshot['title']) ?? prior.title,
      policy: nextPolicy ?? prior.policy,
      seq: seq,
      updatedTurn: turn,
    );
  }

  static Map<String, Object?> _policyOf(Map<String, Object?> meta) {
    return _asMap(meta['policy']) ?? const {};
  }

  static Map<String, Object?>? _argumentsOf(Object? value) {
    Object? decoded = value;
    if (decoded is String) {
      if (decoded.length > _maxArgumentChars) return null;
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return null;
      }
    }
    final map = _asMap(decoded);
    if (map == null) return null;
    try {
      if (jsonEncode(map).length > _maxArgumentChars) return null;
    } on JsonUnsupportedObjectError {
      return null;
    }
    return map;
  }

  static bool _validTree(Map<String, Object?> tree) {
    final root = _asString(tree['root']);
    final components = _asList(tree['components']);
    if (root == null || root.isEmpty || components.isEmpty || components.length > _maxComponents) {
      return false;
    }
    if (tree['title'] != null && tree['title'] is! String) return false;
    final ids = <String>{};
    final maps = <Map<String, Object?>>[];
    final byId = <String, Map<String, Object?>>{};
    for (final component in components) {
      final map = _asMap(component);
      if (map == null) return false;
      final id = _asString(map['id']);
      final type = _asString(map['type']);
      if (id == null || id.isEmpty || type == null || type.isEmpty || !ids.add(id)) return false;
      if (map['props'] != null && map['props'] is! Map) return false;
      maps.add(map);
      byId[id] = map;
    }
    if (!ids.contains(root)) return false;
    final parent = <String, String>{};
    for (final map in maps) {
      final id = _asString(map['id'])!;
      final children = map['children'];
      if (children == null) continue;
      if (children is! List) return false;
      for (final child in children) {
        if (child is! String || child.isEmpty || !ids.contains(child) || child == root) return false;
        if (parent.containsKey(child)) return false;
        parent[child] = id;
      }
    }
    final visiting = <String>{};
    final done = <String>{};
    bool visit(String id, int depth) {
      if (depth > _maxTreeDepth) return false;
      if (visiting.contains(id)) return false;
      if (done.contains(id)) return true;
      visiting.add(id);
      final children = _asList(byId[id]!['children']);
      for (final child in children) {
        if (child is String && !visit(child, depth + 1)) return false;
      }
      visiting.remove(id);
      done.add(id);
      return true;
    }

    for (final id in ids) {
      if (!visit(id, 1)) return false;
    }
    final reachable = <String>{};
    void walk(String id) {
      if (!reachable.add(id)) return;
      for (final child in _asList(byId[id]!['children'])) {
        if (child is String) walk(child);
      }
    }

    walk(root);
    if (reachable.length != ids.length) return false;
    return true;
  }

  static bool _validComposition(Map<String, Object?> args) {
    final blocks = _asList(args['blocks']);
    if (blocks.isEmpty || blocks.length > _maxCompositionBlocks) return false;
    for (final key in args.keys) {
      if (key != 'title' && key != 'blocks') return false;
    }
    final title = args['title'];
    if (title != null && (title is! String || title.length > 200)) return false;
    final ids = <String>{};
    final computedIds = <String>{};
    for (final block in blocks) {
      final map = _asMap(block);
      if (map == null) return false;
      final id = _asString(map['id']);
      final type = _asString(map['type']);
      if (id == null || !_blockId.hasMatch(id) || !ids.add(id)) return false;
      final allowed = switch (type) {
        'markdown' => const {'id', 'type', 'text'},
        'catalog' => const {'id', 'type', 'title', 'root', 'components', 'computed'},
        'widget' => const {
          'id',
          'type',
          'title',
          'initialHeight',
          'placeholderMessages',
          'css',
          'html',
          'jsFunctions',
          'jsExpressions',
        },
        _ => null,
      };
      if (allowed == null || map.keys.any((key) => !allowed.contains(key))) return false;
      switch (type) {
        case 'markdown':
          final text = _asString(map['text']);
          if (text == null || text.trim().isEmpty || text.length > _maxMarkdownChars) return false;
        case 'catalog':
          if (!_validTree(map)) return false;
          for (final computed in _asList(map['computed'])) {
            final item = _asMap(computed);
            final id = _asString(item?['id']);
            if (id == null || id.isEmpty || !computedIds.add(id)) return false;
          }
        case 'widget':
          if (!_validWidget(map)) return false;
        default:
          return false;
      }
    }
    try {
      return jsonEncode(args).length <= _maxCompositionChars;
    } on JsonUnsupportedObjectError {
      return false;
    }
  }

  /// widget 块的准入条件与 iui `validateWidget` 对齐。
  static bool _validWidget(Map<String, Object?> args) {
    final html = _asString(args['html']);
    if (html == null || html.trim().isEmpty || RegExp(r'<script[\s>]', caseSensitive: false).hasMatch(html)) {
      return false;
    }
    final title = args['title'];
    if (title != null && title is! String) return false;
    final css = args['css'];
    if (css != null && css is! String) return false;
    final jsFunctions = args['jsFunctions'];
    if (jsFunctions != null && jsFunctions is! String) return false;
    final jsExpressions = args['jsExpressions'];
    if (jsExpressions != null && (jsExpressions is! List || jsExpressions.any((v) => v is! String))) {
      return false;
    }
    final placeholders = args['placeholderMessages'];
    if (placeholders != null && (placeholders is! List || placeholders.any((v) => v is! String))) {
      return false;
    }
    final initialHeight = args['initialHeight'];
    if (initialHeight != null && (initialHeight is! num || !initialHeight.isFinite || initialHeight <= 0)) {
      return false;
    }
    var total = html.length + (css is String ? css.length : 0) + (jsFunctions is String ? jsFunctions.length : 0);
    if (jsExpressions is List) {
      for (final value in jsExpressions) {
        total += (value as String).length;
      }
    }
    return total <= _maxArgumentChars;
  }

  static List<Object?> _asList(Object? value) => value is List ? value : const [];

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return null;
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is double && value.isFinite && value == value.truncateToDouble()) return value.toInt();
    return null;
  }

  /// Validates and sanitizes an artifact that came from an untrusted share
  /// file. Widget JS is never executed outside the authoring conversation.
  static Map<String, Object?>? sanitizeExternalArtifact(Object? json) {
    final artifact = _asMap(json);
    if (artifact == null) return null;
    final kind = _asString(artifact['kind']);
    final definition = _asMap(artifact['definition']);
    if (kind == null || definition == null) return null;
    if (jsonEncode(artifact).length > _maxArgumentChars) return null;
    final sanitized = Map<String, Object?>.from(definition);
    switch (kind) {
      case 'widget':
        sanitized.remove('jsFunctions');
        sanitized.remove('jsExpressions');
        final html = _asString(sanitized['html']);
        if (html == null) return null;
        sanitized['html'] = _sanitizeWidgetHtml(html);
        if (!_validWidget(sanitized)) return null;
      case 'declarative':
        if (!_validTree(sanitized)) return null;
      case 'composition':
        final blocks = _asList(sanitized['blocks']).map((e) => _asMap(e)).toList(growable: false);
        if (blocks.isEmpty || blocks.length > _maxCompositionBlocks) return null;
        final cleanBlocks = <Map<String, Object?>>[];
        for (final block in blocks) {
          if (block == null) return null;
          final copy = Map<String, Object?>.from(block);
          if (_asString(copy['type']) == 'widget') {
            copy.remove('jsFunctions');
            copy.remove('jsExpressions');
            final html = _asString(copy['html']);
            if (html == null) return null;
            copy['html'] = _sanitizeWidgetHtml(html);
          }
          cleanBlocks.add(copy);
        }
        sanitized['blocks'] = cleanBlocks;
        if (!_validComposition(sanitized)) return null;
      default:
        return null;
    }
    return {
      'kind': kind,
      'definition': sanitized,
      if (artifact['title'] is String) 'title': artifact['title'],
      if (artifact['policy'] is Map) 'policy': artifact['policy'],
    };
  }
}

String _sanitizeWidgetHtml(String html) {
  var out = html.replaceAll(RegExp(r'''\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)''', caseSensitive: false), ' ');
  out = out.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
  return out;
}

class _UiCall {
  const _UiCall(this.kind, this.args, this.turn, this.originSeq);

  final String kind;
  final Map<String, Object?> args;
  final Object? turn;
  final int originSeq;
}

class _SettledCall {
  const _SettledCall(this.id, this.call, this.meta, this.seq);

  final String id;
  final _UiCall call;
  final Map<String, Object?> meta;
  final int seq;
}

/// Incremental projector used by the live chat controller. It keeps the same
/// state as [IntelligentUiProjector.project] but only consumes newly arrived
/// events; a snapshot/history rewrite calls [applyAll] once.
class IntelligentUiProjection {
  IntelligentUiProjection({required this.hostId, required this.sessionId});

  final String hostId;
  final String sessionId;
  final Map<String, Object?> _rootTurns = {};
  final Map<String, int> _rootSeqs = {};
  final Map<String, _UiCall> _calls = {};
  final List<_SettledCall> _settled = [];
  final Map<String, IntelligentUiArtifact> _latest = {};
  final Map<String, int> _blockVersions = {};
  int _settledApplied = 0;
  List<IntelligentUiArtifact>? _artifacts;
  bool _dirty = true;

  List<IntelligentUiArtifact> get artifacts {
    if (_dirty) {
      final values = _latest.values.toList(growable: false)..sort((a, b) => a.seq.compareTo(b.seq));
      _artifacts = List.unmodifiable(values);
      _dirty = false;
    }
    return _artifacts ?? const [];
  }

  void reset() {
    _rootTurns.clear();
    _rootSeqs.clear();
    _calls.clear();
    _settled.clear();
    _latest.clear();
    _blockVersions.clear();
    _settledApplied = 0;
    _artifacts = null;
    _dirty = true;
  }

  void applyAll(Iterable<SessionLogEvent> events) {
    reset();
    final ordered = events.toList(growable: false)..sort((a, b) => a.seq.compareTo(b.seq));
    for (final event in ordered) {
      _apply(event);
    }
  }

  /// Applies events appended after the last projection without replaying the
  /// already-projected prefix.
  void applyPending(Iterable<SessionLogEvent> events) {
    for (final event in events) {
      _apply(event);
    }
  }

  void _apply(SessionLogEvent event) {
    switch (event) {
      case AssistantMessageEvent(:final message, :final turn):
        for (final call in message.toolCalls) {
          _rootTurns.putIfAbsent(call.id, () => turn);
          _rootSeqs.putIfAbsent(call.id, () => event.seq);
        }
        return;
      case ToolCallEvent():
        _rootTurns[event.callId] = event.turn;
        _rootSeqs.putIfAbsent(event.callId, () => event.seq);
        if (!IntelligentUiProjector._tools.contains(event.name)) return;
        final args = IntelligentUiProjector._argumentsOf(event.arguments);
        if (args != null) {
          _calls[event.callId] = _UiCall(event.name, args, event.turn, event.seq);
        }
        return;
      case ToolResultEvent():
        final surfaceOp = event.surfaceOp;
        if (surfaceOp != null && surfaceOp != 'append') return;
        final data = event.data;
        final id =
            IntelligentUiProjector._asString(event.message.source.raw['callId']) ??
            IntelligentUiProjector._asString(data['callId']);
        if (id == null || id.isEmpty) return;
        final call = _calls[id];
        if (call == null) return;
        final meta = IntelligentUiProjector._asMap(data['meta']);
        if (meta == null || meta['ok'] != true) return;
        if (event.message.isError || data['isError'] == true || data['error'] != null) return;
        _settled.add(_SettledCall(id, call, meta, event.seq));
      case UnknownEvent() when event.type == 'tool/ptc-dispatch':
        final data = event.data;
        final name = IntelligentUiProjector._asString(data['name']);
        final subCallId = IntelligentUiProjector._asString(data['subCallId']);
        if (name == null || subCallId == null || !IntelligentUiProjector._tools.contains(name)) return;
        if (data['isError'] == true || data['error'] != null) return;
        final meta = IntelligentUiProjector._asMap(data['meta']);
        if (meta == null || meta['ok'] != true) return;
        final args = IntelligentUiProjector._argumentsOf(data['arguments']);
        if (args == null) return;
        final rootId =
            IntelligentUiProjector._asString(data['rootCallId']) ??
            IntelligentUiProjector._asString(data['parentCallId']);
        final turn = data['turn'] ?? (rootId == null ? null : _rootTurns[rootId]);
        final originSeq = rootId == null ? event.seq : (_rootSeqs[rootId] ?? event.seq);
        if (turn != null) _rootTurns[subCallId] = turn;
        _rootSeqs[subCallId] = originSeq;
        _settled.add(_SettledCall(subCallId, _UiCall(name, args, turn, originSeq), meta, event.seq));
      default:
        return;
    }
    _settled.sort((a, b) => a.seq.compareTo(b.seq));
    while (_settledApplied < _settled.length) {
      _applySettled(_settled[_settledApplied++]);
    }
    if (_settledApplied == _settled.length) {
      _settled.clear();
      _settledApplied = 0;
    }
  }

  void _applySettled(_SettledCall item) {
    final args = item.call.args;
    switch (item.call.kind) {
      case 'ui_render':
        if (_latest.containsKey(item.id) || !IntelligentUiProjector._validTree(args)) return;
        _latest[item.id] = IntelligentUiArtifact(
          kind: IntelligentUiKind.declarative,
          hostId: hostId,
          sessionId: sessionId,
          uiId: item.id,
          version: 1,
          title: IntelligentUiProjector._asString(args['title']),
          definition: args,
          policy: IntelligentUiProjector._policyOf(item.meta),
          turn: item.call.turn,
          seq: item.seq,
          originSeq: item.call.originSeq,
        );
        _dirty = true;
      case 'ui_render_widget':
        if (_latest.containsKey(item.id) || !IntelligentUiProjector._validWidget(args)) return;
        _latest[item.id] = IntelligentUiArtifact(
          kind: IntelligentUiKind.widget,
          hostId: hostId,
          sessionId: sessionId,
          uiId: item.id,
          version: 1,
          title: IntelligentUiProjector._asString(args['title']),
          definition: args,
          policy: IntelligentUiProjector._policyOf(item.meta),
          turn: item.call.turn,
          seq: item.seq,
          originSeq: item.call.originSeq,
        );
        _dirty = true;
      case 'ui_compose':
        if (_latest.containsKey(item.id) || !IntelligentUiProjector._validComposition(args)) return;
        final blocks = IntelligentUiProjector._asList(args['blocks']);
        _latest[item.id] = IntelligentUiArtifact(
          kind: IntelligentUiKind.composition,
          hostId: hostId,
          sessionId: sessionId,
          uiId: item.id,
          version: 1,
          title: IntelligentUiProjector._asString(args['title']),
          definition: args,
          policy: IntelligentUiProjector._policyOf(item.meta),
          turn: item.call.turn,
          seq: item.seq,
          originSeq: item.call.originSeq,
        );
        for (final block in blocks) {
          final map = IntelligentUiProjector._asMap(block);
          if (map != null && IntelligentUiProjector._asString(map['type']) == 'catalog') {
            final blockId = IntelligentUiProjector._asString(map['id']);
            if (blockId != null) _blockVersions['${item.id}#$blockId'] = 1;
          }
        }
        _dirty = true;
      case 'ui_patch':
        IntelligentUiProjector._applyPatch(
          latest: _latest,
          blockVersions: _blockVersions,
          args: args,
          meta: item.meta,
          seq: item.seq,
          turn: item.call.turn,
        );
        _dirty = true;
    }
  }
}
