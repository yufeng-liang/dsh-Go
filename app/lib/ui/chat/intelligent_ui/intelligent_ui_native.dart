import 'package:flutter/material.dart';

import '../../../state/intelligent_ui.dart';
import '../render/markdown_body.dart';

/// A lightweight native renderer for the most common, fully static
/// declarative cards. Anything outside this small subset falls back to the
/// WebView renderer, so this is a fast path rather than a second catalog.
class IntelligentUiNativePreview {
  const IntelligentUiNativePreview._();

  static const _supported = {'Text', 'Stat', 'Table', 'Badge', 'Divider', 'List', 'Progress', 'Stack', 'Grid', 'Card'};

  /// A catalog Card may carry its heading in `props.title`, while the tool
  /// call itself has no title. Use it as the card heading so native cards
  /// don't show a generic fallback while their text heading is dropped.
  static String? titleOf(IntelligentUiArtifact artifact) {
    if (artifact.kind != IntelligentUiKind.declarative) return null;
    final nodes = _nodes(artifact.definition);
    final root = artifact.definition['root'];
    if (nodes == null || root is! String) return null;
    final seen = <String>{};
    String? visit(String id, int depth) {
      if (depth > 8 || !seen.add(id)) return null;
      final node = nodes[id];
      if (node == null) return null;
      if (node['type'] == 'Card') {
        final title = _props(node)['title'];
        if (title is String && title.trim().isNotEmpty) return title.trim();
      }
      final children = node['children'];
      if (children is List) {
        for (final child in children) {
          if (child is String) {
            final found = visit(child, depth + 1);
            if (found != null) return found;
          }
        }
      }
      return null;
    }

    return visit(root, 0);
  }

  static bool supports(IntelligentUiArtifact artifact) {
    if (artifact.kind != IntelligentUiKind.declarative) return false;
    final nodes = _nodes(artifact.definition);
    if (nodes == null) return false;
    final root = artifact.definition['root'];
    if (root is! String || !nodes.containsKey(root)) return false;
    final seen = <String>{};
    bool visit(String id, int depth) {
      if (depth > 8 || !seen.add(id)) return false;
      final node = nodes[id];
      if (node == null) return false;
      final type = node['type'];
      if (type is! String || !_supported.contains(type)) return false;
      final children = node['children'];
      if (children is List) {
        for (final child in children) {
          if (child is! String || !visit(child, depth + 1)) return false;
        }
      }
      return true;
    }

    return visit(root, 0);
  }

  static Widget? tryBuild(BuildContext context, IntelligentUiArtifact artifact, {bool unboundedTables = false}) {
    if (!supports(artifact)) return null;
    final nodes = _nodes(artifact.definition)!;
    final root = artifact.definition['root'] as String;
    final content = _buildNode(context, root, nodes, 0, unboundedTables: unboundedTables);
    if (content == null) return null;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: content);
  }

  static Map<String, Map<String, Object?>>? _nodes(Map<String, Object?> definition) {
    final raw = definition['components'];
    if (raw is! List) return null;
    final nodes = <String, Map<String, Object?>>{};
    for (final value in raw) {
      if (value is! Map) return null;
      final node = value.map((key, value) => MapEntry('$key', value));
      final id = node['id'];
      if (id is! String || id.isEmpty || nodes.containsKey(id)) return null;
      nodes[id] = node;
    }
    return nodes;
  }

  static Widget? _buildNode(BuildContext context, String id, Map<String, Map<String, Object?>> nodes, int depth, {bool unboundedTables = false}) {
    if (depth > 8) return null;
    final node = nodes[id];
    if (node == null) return null;
    final props = _props(node);
    switch (node['type']) {
      case 'Text':
        final text = _string(props['text']);
        if (text == null) return null;
        // The catalog Text component explicitly supports a markdown subset
        // (bold/italic/code/links). Render it with the shared markdown body so
        // links stay clickable instead of showing raw [label](url) syntax.
        return MarkdownBody(text: text, scale: 13 / 16);
      case 'Stat':
        final label = _string(props['label']);
        final value = _string(props['value']);
        if (label == null || value == null) return null;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              if (_string(props['delta']) case final delta?) Text(delta, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        );
      case 'Table':
        final columns = props['columns'];
        final rows = props['rows'];
        if (columns is! List || rows is! List || columns.isEmpty) return null;
        return _NativeTable(columns: columns, rows: rows, unbounded: unboundedTables);
      case 'Badge':
        final text = _string(props['text']);
        if (text == null) return null;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(text, style: Theme.of(context).textTheme.labelSmall),
        );
      case 'Divider':
        return const Divider(height: 1);
      case 'List':
        final items = props['items'];
        if (items is! List) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${item ?? ''}', style: Theme.of(context).textTheme.bodyMedium),
              ),
          ],
        );
      case 'Progress':
        final value = _number(props['value']);
        final max = _number(props['max']) ?? 100;
        if (value == null || max <= 0) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_string(props['label']) case final label?) Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: (value / max).clamp(0, 1).toDouble()),
          ],
        );
      case 'Stack':
      case 'Grid':
      case 'Card':
        final children = node['children'];
        if (children is! List) return null;
        final built = <Widget>[];
        for (final child in children) {
          if (child is! String) return null;
          final widget = _buildNode(context, child, nodes, depth + 1, unboundedTables: unboundedTables);
          if (widget == null) return null;
          built.add(widget);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: built);
      default:
        return null;
    }
  }

  static Map<String, Object?> _props(Map<String, Object?> node) {
    final raw = node['props'];
    return raw is Map ? raw.map((key, value) => MapEntry('$key', value)) : const {};
  }

  static String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;
  static double? _number(Object? value) => value is num ? value.toDouble() : null;
}

/// 原生表格卡片：卡片内限高 420 并显示纵向滚动条，全屏时不限高自然展开。
/// 列宽等分、单元格自动换行，不产生横向溢出。
class _NativeTable extends StatefulWidget {
  const _NativeTable({required this.columns, required this.rows, required this.unbounded});

  final List<Object?> columns;
  final List<Object?> rows;
  final bool unbounded;

  @override
  State<_NativeTable> createState() => _NativeTableState();
}

class _NativeTableState extends State<_NativeTable> {
  // 不记忆上次滚动位置：卡片重新出现时应从表格顶部开始，滚动条也在顶部。
  final ScrollController _controller = ScrollController(keepScrollOffset: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients && _controller.offset != 0) _controller.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = Table(
      border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant),
      defaultColumnWidth: const FlexColumnWidth(),
      children: [
        TableRow(
          children: [
            for (final column in widget.columns)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text('$column', style: Theme.of(context).textTheme.labelMedium),
              ),
          ],
        ),
        for (final row in widget.rows)
          if (row is List)
            TableRow(
              children: [
                for (var i = 0; i < widget.columns.length; i++)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(i < row.length ? '${row[i]}' : '', style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
      ],
    );
    if (widget.unbounded) return table;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          if (mounted) setState(() {});
          return false;
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pos = _controller.hasClients ? _controller.position : null;
            final max = pos?.maxScrollExtent ?? 0;
            final vp = pos?.viewportDimension ?? 0;
            final pixels = pos?.pixels ?? 0;
            final show = max > 0 && vp > 0;
            final content = vp + max;
            final thumbH = show ? (vp * vp / content).clamp(36.0, vp) : 0.0;
            final top = show ? (vp - thumbH) * (pixels / max).clamp(0.0, 1.0) : 0.0;
            return Stack(
              children: [
                SingleChildScrollView(controller: _controller, child: table),
                if (show)
                  Positioned(
                    right: 2,
                    top: top,
                    child: IgnorePointer(
                      child: Container(
                        width: 4,
                        height: thumbH,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

