// A still-image fallback for a `ui_render_widget` card.
//
// The live card is a WebView, and platform views are not captured by
// `RepaintBoundary.toImage`. Markdown keeps the content but loses the widget's
// own typography; this widget reads the common inline CSS (font-size,
// font-weight, font-family, color, align) so a shared screenshot looks much
// closer to the card the model drew. Unknown CSS layouts still fall back to
// Markdown.

import 'package:flutter/material.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../chat/render/markdown_body.dart';
import '../theme/theme.dart';

class ShareWidgetTextView extends StatelessWidget {
  const ShareWidgetTextView({super.key, required this.widget, required this.markdown, required this.width, this.title});

  final Map<String, Object?> widget;
  final String markdown;
  final double width;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final base = AppType.chatBody(
      context,
      scale: 13 / 16,
      height: 1.45,
    ).copyWith(color: Theme.of(context).colorScheme.onSurface);
    final blocks = _blocks(widget, base, title);
    if (blocks.isEmpty) return MarkdownBody(text: markdown, selectable: false, scale: 13 / 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, block) in blocks.indexed) ...[
          if (i > 0) SizedBox(height: block.gapBefore),
          Text.rich(
            TextSpan(children: block.spans),
            style: block.style,
          ),
        ],
      ],
    );
  }
}

List<_Block> _blocks(Map<String, Object?> widget, TextStyle base, String? title) {
  final source = _string(widget['html']);
  if (source == null || source.trim().isEmpty) return const [];
  final dom.Document doc;
  try {
    doc = html.parse(source);
  } on Object {
    return const [];
  }
  final css = _Css()
    ..add(_string(widget['css']))
    ..addAll(doc.querySelectorAll('style').map((e) => e.text));
  final body = doc.body;
  if (body == null) return const [];
  final out = <_Block>[];
  final wanted = title == null ? null : _plain(title);
  var skippingTitle = wanted != null;

  void add(_Block block) {
    if (block.spans.isEmpty) return;
    final text = _plain(block.text);
    if (text.isEmpty) return;
    if (skippingTitle && text == wanted) return;
    skippingTitle = false;
    out.add(block);
  }

  void walk(dom.Node node, TextStyle style) {
    if (node is dom.Text) {
      final text = _text(node.text, style);
      if (text.isNotEmpty) {
        add(_Block([TextSpan(text: text)], style, text: text));
      }
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (tag == 'script' || tag == 'style' || tag == 'head' || tag == 'title') return;
    if (tag == 'table' || tag == 'img' || tag == 'iframe') {
      add(_Block(const [], style, text: ''));
      return;
    }
    final next = _styleFor(node, style, css);
    if (_isBlock(tag)) {
      final spans = <InlineSpan>[];
      final text = StringBuffer();
      void collect(dom.Node child, TextStyle childStyle) {
        if (child is dom.Text) {
          final value = _text(child.text, childStyle);
          if (value.isNotEmpty) {
            spans.add(TextSpan(text: value, style: childStyle));
            text.write(value);
          }
          return;
        }
        if (child is! dom.Element) return;
        final childTag = child.localName ?? '';
        if (childTag == 'script' || childTag == 'style' || childTag == 'head' || childTag == 'title') return;
        if (childTag == 'br') {
          spans.add(const TextSpan(text: '\n'));
          text.write('\n');
          return;
        }
        if (_isBlock(childTag)) {
          walk(child, childStyle);
          return;
        }
        final nested = _styleFor(child, childStyle, css);
        for (final grandchild in child.nodes) {
          collect(grandchild, nested);
        }
      }

      for (final child in node.nodes) {
        collect(child, next);
      }
      add(_Block(spans, next, text: text.toString(), gap: _gapFor(tag, next)));
      return;
    }
    for (final child in node.nodes) {
      walk(child, next);
    }
  }

  final baseStyle = _styleFor(body, base, css);
  for (final child in body.nodes) {
    walk(child, baseStyle);
  }
  return out;
}

bool _isBlock(String tag) => const {
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'aside',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'pre',
  'blockquote',
  'tr',
}.contains(tag);

double _gapFor(String tag, TextStyle style) {
  final size = style.fontSize ?? 13;
  if (tag == 'h1') return 12;
  if (tag == 'h2') return 10;
  if (tag == 'h3' || tag == 'h4' || tag == 'h5' || tag == 'h6') return 8;
  return size <= 14 ? 6 : 8;
}

TextStyle _styleFor(dom.Element element, TextStyle inherited, _Css css) {
  final tag = element.localName ?? '';
  var style = inherited;
  final weight = switch (tag) {
    'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' || 'b' || 'strong' || 'th' => FontWeight.w700,
    'small' => FontWeight.w400,
    _ => null,
  };
  final size = switch (tag) {
    'h1' => 24.0,
    'h2' => 20.0,
    'h3' => 17.0,
    'h4' => 15.0,
    'h5' => 14.0,
    'h6' => 13.0,
    'small' => 11.0,
    _ => null,
  };
  final family = switch (tag) {
    'code' || 'pre' || 'kbd' || 'samp' => 'monospace',
    _ => null,
  };
  if (weight != null) style = style.copyWith(fontWeight: weight);
  if (size != null) style = style.copyWith(fontSize: size);
  if (family != null) style = style.copyWith(fontFamily: family);

  final rules = <String>[
    if (element.id.isNotEmpty) '#${element.id}',
    for (final name in element.classes) '.$name',
    tag,
  ];
  for (final selector in rules) {
    final declaration = css[selector];
    if (declaration != null) style = _apply(style, declaration);
  }
  final inline = element.attributes['style'];
  if (inline != null) style = _apply(style, _declarations(inline));
  return style;
}

TextStyle _apply(TextStyle style, Map<String, String> css) {
  var out = style;
  final size = css['font-size'];
  if (size != null) {
    final px = RegExp(r'(\d+(?:\.\d+)?)px').firstMatch(size);
    if (px != null) out = out.copyWith(fontSize: double.tryParse(px.group(1)!));
  }
  final weight = css['font-weight'];
  if (weight != null) {
    final parsed = switch (weight.trim().toLowerCase()) {
      'bold' || 'bolder' => FontWeight.w700,
      '600' => FontWeight.w600,
      '500' => FontWeight.w500,
      '300' => FontWeight.w300,
      '200' => FontWeight.w200,
      '100' => FontWeight.w100,
      _ => null,
    };
    if (parsed != null) out = out.copyWith(fontWeight: parsed);
  }
  final family = css['font-family'];
  if (family != null) {
    final name = family.split(',').first.replaceAll('"', '').replaceAll("'", '').trim().toLowerCase();
    out = out.copyWith(
      fontFamily: switch (name) {
        'monospace' || 'mono' || 'courier' => 'monospace',
        'serif' || 'times' || 'georgia' => 'serif',
        'sans-serif' || 'system-ui' || 'arial' || 'helvetica' => null,
        _ => name.isEmpty ? null : name,
      },
    );
  }
  final color = css['color'];
  if (color != null) {
    final parsed = _color(color);
    if (parsed != null) out = out.copyWith(color: parsed);
  }
  final height = css['line-height'];
  if (height != null) {
    final parsed = double.tryParse(height.trim());
    if (parsed != null) out = out.copyWith(height: parsed);
  }
  return out;
}

Color? _color(String value) {
  final v = value.trim().toLowerCase();
  final hex = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(v)?.group(1);
  if (hex != null) {
    final full = hex.length == 3 ? '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}' : hex;
    return Color(int.parse('ff$full', radix: 16));
  }
  final rgb = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(v);
  if (rgb != null) {
    return Color.fromARGB(255, int.parse(rgb.group(1)!), int.parse(rgb.group(2)!), int.parse(rgb.group(3)!));
  }
  return null;
}

String _text(String value, TextStyle style, {bool pre = false}) =>
    pre ? value.replaceAll('\r\n', '\n') : value.replaceAll(RegExp(r'\s+'), ' ');

String _plain(String text) =>
    text.replaceAll(RegExp(r'[*_`~]'), '').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

String? _string(Object? value) => value is String ? value : null;

class _Block {
  _Block(this.spans, this.style, {required this.text, this.gap = 6});
  final List<InlineSpan> spans;
  final TextStyle style;
  final String text;
  final double gap;
  double get gapBefore => gap;
}

class _Css {
  _Css();
  final Map<String, Map<String, String>> _rules = {};

  void add(String? text) {
    if (text == null || text.isEmpty) return;
    for (final match in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(text)) {
      final decl = _declarations(match.group(2) ?? '');
      if (decl.isEmpty) continue;
      for (final selector in (match.group(1) ?? '').split(',')) {
        final key = selector.trim();
        if (key.isEmpty || key.contains(' ') || key.contains('>') || key.contains(':')) continue;
        _rules.putIfAbsent(key, () => {}).addAll(decl);
      }
    }
  }

  void addAll(Iterable<String> values) {
    for (final value in values) {
      add(value);
    }
  }

  Map<String, String>? operator [](String selector) => _rules[selector];
}

Map<String, String> _declarations(String text) {
  final out = <String, String>{};
  for (final part in text.split(';')) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    final key = part.substring(0, i).trim().toLowerCase();
    final value = part.substring(i + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) out[key] = value;
  }
  return out;
}
