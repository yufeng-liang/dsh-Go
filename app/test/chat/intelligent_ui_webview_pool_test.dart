import 'package:dsh_app/ui/chat/intelligent_ui/intelligent_ui_webview_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('limits concurrent WebView initialization', () async {
    var active = 0;
    var maximum = 0;
    await Future.wait(
      List.generate(8, (index) async {
        await IntelligentUiWebViewPool.instance.run(() async {
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
        });
      }),
    );
    expect(maximum, lessThanOrEqualTo(IntelligentUiWebViewPool.maxConcurrent));
    expect(active, 0);
  });
}
