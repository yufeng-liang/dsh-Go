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
  final rawPolicy = artifact['policy'];
  final policy = rawPolicy is Map ? rawPolicy.map((key, value) => MapEntry('$key', value)) : const <String, Object?>{};
  final base = buildIntelligentUiHtml(rendererCode: rendererCode, token: 'snapshot', policy: policy);
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
  // The renderer bundle contains strings such as `"</body>"` inside its own
  // JavaScript. Insert before the *last* real body end, otherwise the setup
  // script lands in the middle of the renderer and the page renders its
  // source code as text.
  final end = base.lastIndexOf('</body>');
  if (end < 0) return '$base$setup';
  return '${base.substring(0, end)}$setup${base.substring(end)}';
}

/// Lets grid/flex children of a widget shrink to the card width.
const _widgetFitCss = '*{box-sizing:border-box!important;min-width:0!important}';

class IntelligentUiSnapshot {
  const IntelligentUiSnapshot._();

  static const _channel = MethodChannel('dsh/intelligent_ui_snapshot');
  static const _maxCache = 8;
  static final _cache = <String, Future<Uint8List?>>{};
  static Future<void> _queue = Future.value();
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
    final key = '${_cardKey(card)}|${width.toStringAsFixed(1)}|$dark|$locale';
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
    // Serialize captures: each one creates an offscreen WebView, so running
    // a whole share card's cards concurrently spikes memory on low-end phones.
    final future = _queue.then((_) => _capture(card: card, width: width, dark: dark, locale: locale));
    _queue = future.then((_) {}, onError: (_) {});
    _cache[key] = future;
    future.then((value) {
      if (value == null) _cache.remove(key);
    });
    return future;
  }

  /// Stable identity for the snapshot cache: a rebuilt share card keeps the
  /// same artifact/uiId/version even when its Dart wrapper object changes.
  static String _cardKey(ShareIntelligentUiCard card) {
    final artifact = card.artifact;
    if (artifact != null) {
      final kind = artifact['kind'];
      final uiId = artifact['uiId'];
      final version = artifact['version'];
      return 'a:$kind:$uiId:$version:${identityHashCode(artifact['definition'])}';
    }
    final widget = card.widget;
    return 'w:${identityHashCode(widget)}:${card.title.hashCode}';
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
      var definition = payload?['definition'] as Map? ?? card.widget!;
      if (kind == 'widget') {
        // The widget lives in its own document, so outer share-card CSS cannot
        // reach it. Allow its grid/flex children to shrink to the card width.
        definition = <String, Object?>{...definition, 'css': '${definition['css'] ?? ''}\n$_widgetFitCss'};
        definition = <String, Object?>{...definition, 'initialHeight': 48};
      }
      final policy = payload?['policy'] as Map? ?? const {'maxHeight': 4000};
      final artifact = IntelligentUiArtifact(
        kind: IntelligentUiKind.values.firstWhere(
          (value) => value.name == kind,
          orElse: () => IntelligentUiKind.widget,
        ),
        hostId: '',
        sessionId: '',
        uiId: 'share-${_cardKey(card).hashCode}',
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
