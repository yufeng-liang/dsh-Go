// What an intelligent-ui card contributes to a share card.
//
// The live card is a WebView, and platform views are not drawn into Flutter's
// share screenshot. So this file turns the artifact's own definition into
// Markdown: titles, text, lists, tables, code, stats, badges, progress -- the
// content the model asked to show, without the sandboxed widget.

import '../../l10n/l10n.dart';
import '../../state/intelligent_ui.dart';

/// The cards that belong to [turn]'s seq range, latest version per UI id.
///
/// Patches keep the original [IntelligentUiArtifact.originSeq], so a card
/// updated later still belongs to the turn that first showed it.
String? shareIntelligentUiMarkdown(Iterable<IntelligentUiArtifact> artifacts, {required int startSeq, int? endSeq}) {
  final cards = shareIntelligentUiCards(artifacts, startSeq: startSeq, endSeq: endSeq);
  if (cards.isEmpty) return null;
  return cards.map((card) => card.title == null ? card.markdown : '**${card.title}**\n\n${card.markdown}').join('\n\n');
}

/// One UI card as it goes on a share card: an optional title and Markdown.
class ShareIntelligentUiCard {
  const ShareIntelligentUiCard({this.title, required this.markdown, this.widget});

  final String? title;
  final String markdown;
  final Map<String, Object?>? widget;
}

/// The UI cards that belong to [turn]'s seq range, latest version per UI id.
///
/// Patches keep the original [IntelligentUiArtifact.originSeq], so a card
/// updated later still belongs to the turn that first showed it.
List<ShareIntelligentUiCard> shareIntelligentUiCards(
  Iterable<IntelligentUiArtifact> artifacts, {
  required int startSeq,
  int? endSeq,
}) {
  return [
    for (final card in shareIntelligentUiCardSources(artifacts))
      if (card.originSeq >= startSeq && (endSeq == null || card.originSeq <= endSeq))
        ShareIntelligentUiCard(title: card.title, markdown: card.markdown, widget: card.widget),
  ];
}

/// Cards with the seq of the tool call that first showed them, for a share
/// file's reply: the link viewer has no WebView, so it draws a card from this.
List<({int originSeq, String? title, String markdown, Map<String, Object?>? widget})> shareIntelligentUiCardSources(
  Iterable<IntelligentUiArtifact> artifacts,
) {
  final sorted = <IntelligentUiArtifact>[
    for (final ui in artifacts)
      if (ui.originSeq != null) ui,
  ]..sort((a, b) => (a.originSeq ?? 0).compareTo(b.originSeq ?? 0));
  final out = <({int originSeq, String? title, String markdown, Map<String, Object?>? widget})>[];
  for (final card in sorted) {
    final body = _bodyOf(card).trim();
    if (body.isEmpty) continue;
    final title = (card.title ?? '').trim();
    out.add((
      originSeq: card.originSeq!,
      title: title.isEmpty ? null : title,
      markdown: body,
      widget: card.kind == IntelligentUiKind.widget ? _widgetDefinition(card.definition) : null,
    ));
  }
  return out;
}

Map<String, Object?>? _widgetDefinition(Map<String, Object?> definition) {
  final html = _string(definition['html']);
  if (html == null || html.isEmpty) return null;
  final css = _string(definition['css']);
  return {'html': html, if (css != null && css.isNotEmpty) 'css': css};
}

String _bodyOf(IntelligentUiArtifact ui) => switch (ui.kind) {
  IntelligentUiKind.composition => _compositionMarkdown(ui.definition),
  IntelligentUiKind.widget => _widgetMarkdown(ui.definition),
  IntelligentUiKind.declarative => _catalogMarkdown(ui.definition),
};

String _compositionMarkdown(Map<String, Object?> definition) {
  final blocks = definition['blocks'];
  if (blocks is! List) return '';
  final out = <String>[];
  for (final block in blocks) {
    if (block is! Map) continue;
    switch (block['type']) {
      case 'markdown':
        final text = _string(block['text']);
        if (text != null) out.add(text);
      case 'catalog':
        final markdown = _catalogMarkdown({for (final e in block.entries) '${e.key}': e.value});
        if (markdown.isNotEmpty) out.add(markdown);
      case 'widget':
        final markdown = _widgetMarkdown({for (final e in block.entries) '${e.key}': e.value});
        if (markdown.isNotEmpty) out.add(markdown);
    }
  }
  return out.join('\n\n');
}

String _widgetMarkdown(Map<String, Object?> definition) {
  final title = _string(definition['title']);
  final html = _string(definition['html']);
  final text = html == null ? '' : _htmlText(html);
  return [
    if (title != null && title.isNotEmpty) '**$title**',
    if (text.isNotEmpty) text,
    if (text.isEmpty) appL10n.chatIntelligentUiTitle,
  ].join('\n\n');
}

String _catalogMarkdown(Map<String, Object?> definition) {
  final raw = definition['components'];
  if (raw is! List) return '';
  final nodes = <String, Map>{};
  for (final node in raw) {
    if (node is! Map) continue;
    final id = _string(node['id']);
    if (id != null) nodes[id] = node;
  }
  final root = _string(definition['root']);
  final out = <String>[];
  final seen = <String>{};

  void visit(String id, {int depth = 0}) {
    if (depth > 32 || !seen.add(id)) return;
    final node = nodes[id];
    if (node == null) return;
    final text = _nodeMarkdown(node);
    if (text != null && text.trim().isNotEmpty) out.add(text.trim());
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is String) visit(child, depth: depth + 1);
      }
    }
  }

  if (root != null) {
    visit(root);
  } else {
    for (final id in nodes.keys) {
      visit(id);
    }
  }
  return out.join('\n\n');
}

String? _nodeMarkdown(Map node) {
  final type = (_string(node['type']) ?? '').toLowerCase();
  final rawProps = node['props'];
  final props = rawProps is Map ? rawProps : const {};
  String? textOf(Object? value) => _string(value);

  switch (type) {
    case 'text' || 'heading' || 'title' || 'label' || 'caption' || 'markdown' || 'richtext':
      return [
        textOf(props['title']),
        textOf(props['text']) ?? textOf(props['markdown']) ?? textOf(props['value']),
      ].whereType<String>().where((s) => s.isNotEmpty).join('\n\n');
    case 'code':
      final code = textOf(props['code']) ?? textOf(props['text']);
      if (code == null || code.isEmpty) return null;
      final language = textOf(props['language']) ?? '';
      return '```$language\n$code\n```';
    case 'list':
      final items = props['items'];
      if (items is! List || items.isEmpty) return null;
      final ordered = props['ordered'] == true;
      final lines = <String>[];
      for (var i = 0; i < items.length; i++) {
        final item = _string(items[i]);
        if (item != null && item.isNotEmpty) lines.add('${ordered ? '${i + 1}.' : '-'} $item');
      }
      return lines.isEmpty ? null : lines.join('\n');
    case 'table':
      return _tableMarkdown(props);
    case 'stat':
      final label = textOf(props['label']);
      final value = textOf(props['value']) ?? props['value']?.toString();
      final hint = textOf(props['hint']);
      final delta = textOf(props['delta']);
      if (label == null && value == null) return null;
      return [
        if (label != null && label.isNotEmpty) '**$label**',
        if (value != null && value.isNotEmpty) value,
        if (delta != null && delta.isNotEmpty) delta,
        if (hint != null && hint.isNotEmpty) hint,
      ].join(' · ');
    case 'badge':
      final text = textOf(props['text']);
      return text == null || text.isEmpty ? null : '`$text`';
    case 'progress':
      final label = textOf(props['label']);
      final value = props['value'];
      final max = props['max'] ?? 100;
      final text = [
        if (label != null && label.isNotEmpty) label,
        if (value is num) '${((value / (max is num && max > 0 ? max : 100)) * 100).round()}%',
      ].join(' · ');
      return text.isEmpty ? null : text;
    case 'divider':
      return '---';
    case 'image':
      final alt = textOf(props['alt']) ?? textOf(props['caption']);
      return alt == null || alt.isEmpty ? null : '_[图片：$alt]_';
    case 'chart':
      return textOf(props['title']);
    case 'card' || 'section' || 'stack' || 'grid' || 'tabs' || 'tablist':
      return textOf(props['title']);
    default:
      return textOf(props['title']) ?? textOf(props['text']) ?? textOf(props['label']);
  }
}

String? _tableMarkdown(Map props) {
  final columns = props['columns'];
  final rows = props['rows'];
  if (columns is! List || rows is! List || columns.isEmpty || rows.isEmpty) return null;
  String cell(Object? value) => (value?.toString() ?? '').replaceAll('|', r'\|').replaceAll('\n', ' ');
  final header = columns.map(cell).toList();
  if (header.isEmpty) return null;
  final lines = <String>[
    '| ${header.join(' | ')} |',
    '| ${header.map((_) => '---').join(' | ')} |',
    for (final row in rows)
      if (row is List) '| ${row.map(cell).join(' | ')} |',
  ];
  return lines.length <= 2 ? null : lines.join('\n');
}

String? _string(Object? value) {
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return null;
}

String _htmlText(String html) {
  final withoutScripts = html.replaceAll(
    RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true, caseSensitive: false),
    ' ',
  );
  final text = withoutScripts
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');
  return text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}
