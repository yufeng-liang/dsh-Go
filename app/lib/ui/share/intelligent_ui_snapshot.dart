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
  final definition = artifact['definition'];
  if (artifact['kind'] == 'widget' && definition is Map) {
    final html = definition['html'];
    final css = definition['css'];
    if (html is String && html.isNotEmpty) {
      return _buildWidgetSnapshotHtml(
        html: html,
        css: css is String ? css : '',
        dark: dark,
        policy: artifact['policy'] is Map
            ? (artifact['policy'] as Map).map((key, value) => MapEntry('$key', value))
            : const <String, Object?> {},
      );
    }
  }
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

String _buildWidgetSnapshotHtml({
  required String html,
  required String css,
  required bool dark,
  required Map<String, Object?> policy,
}) {
  final allowMedia = policy['allowMedia'] == true;
  final origins = (policy['mediaOrigins'] is List)
      ? (policy['mediaOrigins'] as List).whereType<String>().where((origin) => Uri.tryParse(origin)?.hasScheme == true).toList()
      : const <String>[];
  final mediaSrc = !allowMedia ? "'none'" : (origins.isEmpty ? 'https:' : origins.join(' '));
  final imgSrc = allowMedia ? 'data: blob: $mediaSrc' : 'data: blob:';
  final bg = dark ? '#151517' : '#ffffff';
  final surface = dark ? '#232324' : '#f5f6f7';
  final text = dark ? '#f9fafb' : '#0f1115';
  final muted = dark ? '#adb2b8' : '#81858c';
  final border = dark ? '#ffffff1f' : '#0000001a';
  final accent = dark ? '#7aaaff' : '#4176e6';
  final accentText = dark ? '#151517' : '#ffffff';
  final safeCss = css.replaceAll(RegExp(r'</style', caseSensitive: false), r'<\/style');
  return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src $imgSrc; media-src $mediaSrc; style-src 'unsafe-inline'; font-src data:;">
<style>
:root{--ui-bg:$bg;--ui-surface:$surface;--ui-text:$text;--ui-muted:$muted;--ui-border:$border;--ui-accent:$accent;--ui-accent-text:$accentText;--ui-radius:8px;--ui-font:system-ui,-apple-system,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;--ui-mono:ui-monospace,SFMono-Regular,Consolas,monospace;color-scheme:${dark ? 'dark' : 'light'}}
*,*::before,*::after{box-sizing:border-box}
html,body{margin:0;padding:0;background:transparent!important;color:var(--ui-text);font:14px/1.5 var(--ui-font);-webkit-font-smoothing:antialiased;overflow:hidden!important}
#ui-root{padding:0!important;background:transparent!important;overflow:hidden!important}
h1,h2,h3,h4{margin:0 0 .5em;line-height:1.25}h3{font-size:16px}p{margin:0 0 .75em}a{color:var(--ui-accent)}
button,input,select,textarea{font:inherit;color:inherit}button{cursor:pointer;border:1px solid var(--ui-border);background:var(--ui-surface);border-radius:var(--ui-radius);padding:6px 12px}
button.primary,button[data-variant=primary]{background:var(--ui-accent);border-color:var(--ui-accent);color:var(--ui-accent-text)}
input,select,textarea{border:1px solid var(--ui-border);background:var(--ui-bg);border-radius:var(--ui-radius);padding:6px 8px;max-width:100%}
code,pre{font-family:var(--ui-mono)}table{border-collapse:collapse;width:100%}th,td{border-bottom:1px solid var(--ui-border);padding:6px 8px;text-align:left}
svg,canvas,img,video{max-width:100%}
.ui-row{display:flex;flex-wrap:wrap;gap:8px 16px;align-items:center}
.ui-card{border:1px solid var(--ui-border);border-radius:var(--ui-radius);background:var(--ui-surface);padding:12px}
.ui-muted{color:var(--ui-muted)}
$safeCss
</style></head><body><div id="ui-root">$html</div>
<script>
(function(){
  function send(){if(window.Dsh&&window.Dsh.postMessage){window.Dsh.postMessage(JSON.stringify({type:'captureReady'}));}}
  requestAnimationFrame(function(){requestAnimationFrame(function(){setTimeout(send,250);});});
})();
</script></body></html>''';
}

/// Lets grid/flex children of a widget shrink to the card width.
const _widgetFitCss =
    'html,body,#ui{overflow:hidden!important} *{box-sizing:border-box!important;min-width:0!important}';

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
        definition = <String, Object?>{...definition, 'initialHeight': 1600};
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
