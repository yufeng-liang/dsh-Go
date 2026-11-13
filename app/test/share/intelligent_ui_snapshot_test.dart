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
    expect(html, contains('<div id="ui-root">'));
    expect(html, contains('A & B'));
    expect(html, isNot(contains('window.renderer = true;')));
    expect(html, contains("type:'captureReady'"));
  });

  test('snapshot policy controls remote media origins', () {
    final html = buildIntelligentUiSnapshotHtml(
      rendererCode: '',
      artifact: const {
        'kind': 'widget',
        'uiId': 'share-media',
        'version': 1,
        'definition': {'html': '<img src="https://img.example/a.png">'},
        'policy': {
          'allowMedia': true,
          'mediaOrigins': ['https://img.example'],
        },
      },
      dark: false,
      locale: 'en',
    );
    expect(html, contains('img-src data: blob: https://img.example'));
    expect(html, contains('media-src https://img.example'));
  });

  test('snapshot bootstrap stays outside a renderer string containing </body>', () {
    final html = buildIntelligentUiSnapshotHtml(
      rendererCode: 'var fake = "</body>"; window.renderer = true;',
      artifact: const {
        'kind': 'declarative',
        'uiId': 'share-1',
        'version': 1,
        'definition': {'root': 'root', 'components': []},
      },
      dark: false,
      locale: 'en',
    );
    final setup = html.indexOf("type:'captureReady'");
    final lastBody = html.lastIndexOf('</body>');
    final rendererEnd = html.indexOf('</script>');
    expect(setup, greaterThan(rendererEnd));
    expect(setup, lessThan(lastBody));
  });
}
