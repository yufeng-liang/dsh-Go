import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_app/ui/share/share_widget_text.dart';

void main() {
  testWidgets('keeps inline size, weight and family', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareWidgetTextView(
            widget: {
              'html':
                  '<h1 style="font-size:24px;font-weight:700">Typography specimen</h1>'
                  '<p style="font-size:20px;font-family:serif">Serif body</p>'
                  '<p style="font-size:16px;font-family:monospace">Mono body</p>',
            },
            markdown: 'fallback',
            width: 320,
            title: 'Typography specimen',
          ),
        ),
      ),
    );

    final flat = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.text != null) flat.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        collect(child);
      }
    }

    for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
      collect(widget.text);
    }
    expect(flat.where((span) => span.text == 'Typography specimen'), isEmpty);
    expect(flat.any((span) => span.style?.fontSize == 20 && span.style?.fontFamily == 'serif'), isTrue);
    expect(flat.any((span) => span.style?.fontSize == 16 && span.style?.fontFamily == 'monospace'), isTrue);
  });
}
