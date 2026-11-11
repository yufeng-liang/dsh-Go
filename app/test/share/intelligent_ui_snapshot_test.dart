import 'package:dsh_app/ui/share/intelligent_ui_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot bootstrap applies the artifact before captureReady', () {
    final html = buildIntelligentUiSnapshotHtml(
      rendererCode: 'window.renderer = true;',
      artifact: const {
        'kind': 'widget',
        'uiId': 'share-1',
        'version': 1,
        'definition': {'html': '<p style="font-size:20px">A & B</p>'},
      },
      dark: true,
      locale: 'zh-CN',
    );
    expect(html, contains('window.renderer = true;'));
    expect(html, contains('window.__diuiSetTheme("dark")'));
    expect(html, contains('window.__diuiSetLocale("zh-CN")'));
    expect(html, contains('window.__diuiSetArtifact('));
    expect(html, contains(r'\u003cp style='));
    expect(html, contains("type:'captureReady'"));
  });
}
