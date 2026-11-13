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

  test('snapshot opens the network only for a policy that names remote media', () {
    expect(snapshotAllowsRemoteMedia(const {}), isFalse);
    expect(
      snapshotAllowsRemoteMedia(const {
        'allowMedia': false,
        'mediaOrigins': ['https://img.example'],
      }),
      isFalse,
    );
    expect(snapshotAllowsRemoteMedia(const {'allowMedia': true}), isTrue);
    expect(
      snapshotAllowsRemoteMedia(const {
        'allowMedia': true,
        'mediaOrigins': ['https://img.example'],
      }),
      isTrue,
    );
    expect(
      snapshotAllowsRemoteMedia(const {
        'mapTiles': {'url': 'https://tiles.example/style.json'},
      }),
      isTrue,
    );
  });

  test('widget snapshot CSP drops non-https media origins', () {
    final html = buildIntelligentUiSnapshotHtml(
      rendererCode: '',
      artifact: const {
        'kind': 'widget',
        'uiId': 'share-mixed',
        'version': 1,
        'definition': {'html': '<img src="https://ok.example/a.png">'},
        'policy': {
          'allowMedia': true,
          'mediaOrigins': ['http://img.example', 'https://ok.example'],
        },
      },
      dark: false,
      locale: 'en',
    );
    expect(html, contains('img-src data: blob: https://ok.example'));
    expect(html, isNot(contains('img.example')));
  });

  test('snapshot waits for images before captureReady', () {
    final widget = buildIntelligentUiSnapshotHtml(
      rendererCode: '',
      artifact: const {
        'kind': 'widget',
        'uiId': 'share-wait',
        'version': 1,
        'definition': {'html': '<img src="https://img.example/a.png">'},
      },
      dark: false,
      locale: 'en',
    );
    expect(widget, contains('document.images'));
    final declarative = buildIntelligentUiSnapshotHtml(
      rendererCode: 'window.renderer = true;',
      artifact: const {
        'kind': 'declarative',
        'uiId': 'share-wait',
        'version': 1,
        'definition': {'root': 'root', 'components': []},
      },
      dark: false,
      locale: 'en',
    );
    expect(declarative, contains('document.images'));
  });
}
