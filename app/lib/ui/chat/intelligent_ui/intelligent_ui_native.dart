import 'package:flutter/material.dart';

import '../../../state/intelligent_ui.dart';
import '../render/markdown_body.dart';

/// A lightweight native renderer for the most common, fully static
/// declarative cards. Anything outside this small subset falls back to the
/// WebView renderer, so this is a fast path rather than a second catalog.
class IntelligentUiNativePreview {
  const IntelligentUiNativePreview._();

  static const _supported = {'Text', 'Stat', 'Table', 'Badge', 'Divider', 'List', 'Progress', 'Stack', 'Grid', 'Card'};

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

  static Widget? tryBuild(BuildContext context, IntelligentUiArtifact artifact) {
    if (!supports(artifact)) return null;
    final nodes = _nodes(artifact.definition)!;
    final root = artifact.definition['root'] as String;
    return _buildNode(context, root, nodes, 0);
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

  static Widget? _buildNode(BuildContext context, String id, Map<String, Map<String, Object?>> nodes, int depth) {
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
        return Table(
          border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant),
          children: [
            TableRow(
              children: [
                for (final column in columns)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text('$column', style: Theme.of(context).textTheme.labelMedium),
                  ),
              ],
            ),
            for (final row in rows)
              if (row is List)
                TableRow(
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(i < row.length ? '${row[i]}' : '', style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
          ],
        );
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
          final widget = _buildNode(context, child, nodes, depth + 1);
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
