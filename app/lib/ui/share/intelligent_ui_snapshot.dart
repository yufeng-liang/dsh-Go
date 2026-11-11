// Renders one intelligent-ui widget in an offscreen Android WebView and
// returns its PNG. The share card is painted by Flutter, so a WebView in the
// tree would not be captured by toImage(); a bitmap can be.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../state/intelligent_ui.dart';
import '../chat/intelligent_ui/intelligent_ui_card.dart' show buildIntelligentUiHtml;
import 'share_intelligent_ui.dart';

/// Builds the same bootstrap the live card uses, with the artifact applied
/// before the page reports that it is ready to be captured.
String buildIntelligentUiSnapshotHtml({
  required String rendererCode,
  required Map<String, Object?> artifact,
  required bool dark,
  required String locale,
}) {
  final base = buildIntelligentUiHtml(rendererCode: rendererCode, token: 'snapshot');
  final data = jsonEncode(artifact).replaceAll('<', r'\u003c');
  final setup =
      '''
<script>
window.__diuiSetTheme(${jsonEncode(dark ? 'dark' : 'light')});
window.__diuiSetLocale(${jsonEncode(locale)});
window.__diuiSetArtifact($data);
(function(){
  var started = Date.now();
  function send() {
    if (window.Dsh && window.Dsh.postMessage) {
      window.Dsh.postMessage(JSON.stringify({type:'captureReady'}));
    }
  }
  function check() {
    var ui = document.getElementById('ui');
    var hasContent = !!ui && (ui.children.length > 0 || (ui.textContent || '').trim().length > 0);
    if (hasContent) {
      setTimeout(send, 250);
      return;
    }
    if (Date.now() - started > 5000) {
      send();
      return;
    }
    setTimeout(check, 100);
  }
  setTimeout(check, 100);
})();
</script>''';
  return base.replaceFirst('</body>', '$setup</body>');
}

/// Paints `ui_render_widget` cards into bitmaps for the share card.
class IntelligentUiSnapshot {
  const IntelligentUiSnapshot._();

  static const _channel = MethodChannel('dsh/intelligent_ui_snapshot');
  static const _maxCache = 16;
  static final _cache = <String, Future<Uint8List?>>{};
  static Future<String>? _rendererCode;

  /// The widget's current pixels at [width] logical pixels, or null when the
  /// platform has no capture channel (tests) or rendering failed.
  static Future<Uint8List?> capture({
    required ShareIntelligentUiCard card,
    required double width,
    required bool dark,
    required String locale,
  }) {
    final payload = card.artifact ?? card.widget;
    if (payload == null || width <= 0) return Future<Uint8List?>.value();
    final key = '${payload.hashCode}|${width.toStringAsFixed(1)}|$dark|$locale';
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
    final future = _capture(card: card, width: width, dark: dark, locale: locale);
    _cache[key] = future;
    return future;
  }

  static Future<Uint8List?> _capture({
    required ShareIntelligentUiCard card,
    required double width,
    required bool dark,
    required String locale,
  }) async {
    try {
      final rendererCode = await (_rendererCode ??= rootBundle.loadString('assets/intelligent_ui/renderer.js'));
      final payload = card.artifact;
      if (payload == null && card.widget == null) return null;
      final kind = payload?['kind'] as String? ?? 'widget';
      final definition = payload?['definition'] as Map? ?? card.widget!;
      final policy = payload?['policy'] as Map? ?? const {'maxHeight': 4000};
      final artifact = IntelligentUiArtifact(
        kind: IntelligentUiKind.values.firstWhere(
          (value) => value.name == kind,
          orElse: () => IntelligentUiKind.widget,
        ),
        hostId: '',
        sessionId: '',
        uiId: 'share-${payload?.hashCode ?? card.widget.hashCode}',
        version: 1,
        definition: Map<String, Object?>.from(definition),
        seq: 0,
        title: card.title,
        policy: Map<String, Object?>.from(policy),
      );
      final html = buildIntelligentUiSnapshotHtml(
        rendererCode: rendererCode,
        artifact: artifact.toRendererJson(),
        dark: dark,
        locale: locale,
      );
      return await _channel.invokeMethod<Uint8List>('capture', {'html': html, 'width': width.round()});
    } on MissingPluginException catch (error) {
      debugPrint('IntelligentUiSnapshot missing plugin: $error');
      return null;
    } on PlatformException catch (error) {
      debugPrint('IntelligentUiSnapshot platform error: ${error.code} ${error.message}');
      return null;
    } on Object catch (error) {
      debugPrint('IntelligentUiSnapshot failed: $error');
      return null;
    }
  }
}
