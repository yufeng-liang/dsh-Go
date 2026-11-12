import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../l10n/l10n.dart';
import '../../../state/connection_state.dart' show activeConnectionProvider;
import '../../../state/hosts_state.dart' show activeHostProvider;
import '../../../state/intelligent_ui.dart';
import '../../../state/sessions_state.dart' show currentSessionProvider;
import '../../common/app_dialog.dart';
import '../../theme/app_icons.dart';
import '../../web/web_view_guard.dart';
import '../widgets/chat_card.dart';
import 'intelligent_ui_bridge.dart';

const _mobileStyles = '''
html,body{padding:0!important;margin:0!important;overflow-x:hidden;background:transparent!important;-webkit-tap-highlight-color:transparent}
#ui{padding:0!important;margin:0!important;overflow-x:hidden!important}
#ui,#ui *{box-sizing:border-box!important}
#ui{width:100%!important}
#ui *{max-width:100%!important;min-width:0!important;overflow-wrap:anywhere}
.diui-remote-title{display:none!important}
#ui .diui-remote{padding:0!important;font-size:13px}
.diui-compose{display:flex;flex-direction:column;gap:10px;padding:2px 0 8px}
.diui-compose .diui-md{font-size:13px;line-height:1.5}
.diui-table-wrap{-webkit-overflow-scrolling:touch;touch-action:pan-y;overscroll-behavior:contain;border-radius:8px;max-height:none!important;overflow:visible!important}
.diui-md table,.diui-md pre,.diui-code,.diui-problem-detail,.diui-diff-body,.diui-map-list,.diui-tablist{max-height:none!important;overflow-y:visible!important;overflow-x:hidden!important}
.diui-md table,.diui-md pre,.diui-code,.diui-diff-body,.diui-tablist{width:100%!important;max-width:100%!important}
.diui-md table,.diui-table{table-layout:fixed!important}
.diui-table th,.diui-table td{padding:8px 12px;font-size:13px;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word}
.diui-table th{font-weight:600}
.diui-md pre,.diui-code{white-space:pre-wrap!important;word-break:break-word!important}
.diui-tablist{flex-wrap:wrap!important;white-space:normal!important}
.diui-button,.diui-choice-submit,.diui-table-tools button{min-height:36px;padding:6px 14px;border-radius:8px;touch-action:manipulation;font-size:13px}
.diui-table-tools{gap:8px;margin-bottom:8px}
.diui-table-tools input[type=search]{height:36px;padding:0 10px;font-size:13px;border-radius:8px}
.diui-choice-option{padding:12px 14px;border-radius:10px}
.diui-choice-submit{width:100%;justify-content:center;min-height:42px;font-weight:600;font-size:14px}
.diui-choice-hint{font-size:11px;line-height:1.4}
.diui-stat{padding:12px 14px;border-radius:10px}
''';

/// 生成智能 UI 卡片的 bootstrap HTML。renderer 代码来自本地打包资源，
/// 不经过网络；CSP 与 remote 的实现保持一致。
String? _rendererCacheInput;
String? _rendererCacheOutput;

String _escapedRendererCode(String rendererCode) {
  if (_rendererCacheInput == rendererCode) return _rendererCacheOutput!;
  final code = rendererCode.replaceAll(RegExp(r'</script', caseSensitive: false), '<\\/script');
  _rendererCacheInput = rendererCode;
  _rendererCacheOutput = code;
  return code;
}

String buildIntelligentUiHtml({required String rendererCode, required String token}) {
  final code = _escapedRendererCode(rendererCode);
  final tokenJson = jsonEncode(token);
  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob:; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src about: data: blob:; form-action 'none'; base-uri 'none'">
<style>$_mobileStyles</style>
</head>
<body>
<main id="ui"></main>
<script>$code</script>
<script>
(function(){
  var token=$tokenJson;
  var seq=0;
  var pending=new Map();
  function send(type,payload){
    var message=Object.assign({token:token,type:type},payload||{});
    if(window.Dsh&&window.Dsh.postMessage) window.Dsh.postMessage(JSON.stringify(message));
  }
  window.__diuiReply=function(id,ok,error){
    var item=pending.get(id);
    if(!item) return;
    pending.delete(id);
    if(ok) item.resolve(); else item.reject(new Error(error||'failed'));
  };
  var host={
    sendPrompt:function(text){
      return new Promise(function(resolve,reject){
        var id=++seq;
        pending.set(id,{resolve:resolve,reject:reject});
        send('prompt',{id:id,text:String(text)});
      });
    },
    onHeight:function(height){ send('resize',{height:height}); }
  };
  window.open=function(url){ if(url) send('openLink',{url:String(url)}); return null; };
  var renderer=DshIntelligentUiRenderer.mount(document.getElementById('ui'),host);
  document.addEventListener('click',function(event){
    var anchor=event.target&&event.target.closest?event.target.closest('a[href]'):null;
    if(!anchor) return;
    if(anchor.hasAttribute('download')){
      var href=anchor.getAttribute('href')||'';
      if(href.indexOf('blob:')!==0) return;
      event.preventDefault();
      fetch(href).then(function(response){return response.text();}).then(function(text){
        send('download',{name:anchor.getAttribute('download')||'download.txt',text:text});
      }).catch(function(error){send('error',{message:String(error&&error.message||error)});});
      return;
    }
    var link=anchor.getAttribute('href')||'';
    if(link.indexOf('https://')===0){ event.preventDefault(); send('openLink',{url:link}); }
  },true);
  window.__diuiSetArtifact=function(value){
    try { renderer.render(value); } catch(error) { send('error',{message:String(error&&error.message||error)}); }
  };
  window.__diuiSetTheme=function(value){ try { renderer.setTheme(value); } catch(_){} };
  window.__diuiSetLocale=function(value){ try { if(renderer.setLocale) renderer.setLocale(value); } catch(_){} };
  send('ready',{});
})();
</script>
</body>
</html>
''';
}

/// Lets a widget's grid/flex children shrink to the card width.
const _widgetFitCss = '''
*{box-sizing:border-box!important;min-width:0!important}
#ui-root{padding:0!important;background:transparent!important}
''';

/// widget iframe 里的普通 <a href> 会导航 iframe 并被 renderer 移除；捕获点击后
/// 交给渲染器的 Bridge.openLink，由外层 WebView 打开系统浏览器。
const _widgetLinkBridge = r'''
(function(){
  function openLink(href){
    try {
      if (window.Bridge && typeof window.Bridge.openLink === 'function') {
        window.Bridge.openLink(href);
        return;
      }
    } catch (e) {}
    try { window.open(href, '_blank', 'noopener,noreferrer'); } catch (e) {}
  }
  function onClick(event){
    var node = event.target;
    var anchor = node && node.closest ? node.closest('a[href]') : null;
    if (!anchor) return;
    var href = anchor.getAttribute('href') || '';
    if (!/^https:\/\//i.test(href)) return;
    event.preventDefault();
    event.stopPropagation();
    openLink(href);
  }
  document.addEventListener('click', onClick, true);
})();
''';

class IntelligentUiCard extends ConsumerStatefulWidget {
  const IntelligentUiCard({
    super.key,
    required this.artifact,
    this.onSendPrompt,
    this.readOnly = false,
    this.immersive = false,
  });

  final IntelligentUiArtifact artifact;
  final Future<bool> Function(String text)? onSendPrompt;

  /// Replay/share cards are read-only: action buttons may render, but any
  /// prompt is rejected instead of reaching a host.
  final bool readOnly;

  /// Chat-stream widget cards are usually already fully styled by the widget
  /// itself. Skipping the outer [ChatCard] avoids a card-inside-a-card look.
  final bool immersive;

  @override
  ConsumerState<IntelligentUiCard> createState() => _IntelligentUiCardState();
}

class _IntelligentUiCardState extends ConsumerState<IntelligentUiCard> {
  static Future<String>? _rendererCode;

  final _actions = UiActionGuard();
  late String _token;
  WebViewController? _controller;
  WebViewGuard? _guard;
  int _loadGeneration = 0;
  bool _ready = false;
  bool _gone = false;
  bool _dark = false;
  // The renderer reports scrollHeight, which cannot shrink below the current
  // viewport. Start near a single text line so short cards do not keep a
  // permanent blank tail; taller content grows on the next resize report.
  int _height = 96;
  int _textZoom = 100;
  String _locale = 'zh-CN';
  String? _error;

  int get _maxHeight {
    final value = widget.artifact.policy['maxHeight'];
    final raw = value is num ? value.toInt() : 4000;
    return raw.clamp(100, 4000).toInt();
  }

  @override
  void initState() {
    super.initState();
    _token = _newToken();
    _dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    _locale = _localeOf(context);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final textZoom = MediaQuery.textScalerOf(context).scale(100).round().clamp(50, 300).toInt();
    if (textZoom != _textZoom) {
      _textZoom = textZoom;
      unawaited(_guard?.setTextZoom(_textZoom) ?? Future<void>.value());
    }
    final locale = _localeOf(context);
    if (locale != _locale) {
      _locale = locale;
      _setLocale();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark != _dark) {
      _dark = dark;
      unawaited(_guard?.setDark(dark) ?? Future<void>.value());
      if (_ready) _setTheme(dark);
    }
  }

  @override
  void didUpdateWidget(covariant IntelligentUiCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready) return;
    if (oldWidget.artifact.uiId != widget.artifact.uiId || oldWidget.artifact.version != widget.artifact.version) {
      _postArtifact();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    final guard = _guard;
    _guard = null;
    _controller = null;
    if (guard != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        guard.destroy();
        guard.dispose();
      });
    }
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final code = await (_rendererCode ??= rootBundle.loadString('assets/intelligent_ui/renderer.js'));
      if (!mounted || generation != _loadGeneration) return;
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.addJavaScriptChannel('Dsh', onMessageReceived: (message) => unawaited(_onMessage(message)));
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            return url == 'about:blank' || url.startsWith('about:srcdoc') || url.startsWith('data:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            _ready = false;
            _actions.reset();
          },
          onPageFinished: (_) {
            if (!_ready && !_gone) _postArtifact();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _setError(error.description);
            }
          },
        ),
      );
      if (controller.platform case final AndroidWebViewController android) {
        await android.setAllowFileAccess(false);
        await android.setAllowContentAccess(false);
        await android.setMixedContentMode(MixedContentMode.neverAllow);
      }
      final guard = WebViewGuard(
        onGone: (crashed) {
          if (!mounted || generation != _loadGeneration) return;
          final oldGuard = _guard;
          _guard = null;
          _controller = null;
          if (oldGuard != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              oldGuard.destroy();
              oldGuard.dispose();
            });
          }
          setState(() {
            _gone = true;
            _error = null;
          });
        },
      );
      await guard.attach(controller, dark: _dark, textZoom: _textZoom);
      if (!mounted || generation != _loadGeneration) {
        await guard.destroy();
        guard.dispose();
        return;
      }
      _guard = guard;
      _controller = controller;
      if (mounted) setState(() {});
      await controller.loadHtmlString(buildIntelligentUiHtml(rendererCode: code, token: _token));
    } catch (error) {
      _rendererCode = null;
      if (generation == _loadGeneration) _setError('$error');
    }
  }

  String _localeOf(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return language == 'zh' ? 'zh-CN' : language;
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _error = message.length > 240 ? message.substring(0, 240) : message);
  }

  void _postArtifact() {
    final controller = _controller;
    if (controller == null) return;
    // 与 remote 一致：即使插件策略允许，卡片也不给它网络、CDN 或外链权限。
    final artifact = _renderArtifact(widget.artifact);
    final rawPolicy = artifact['policy'];
    final policy = <String, Object?>{
      if (rawPolicy is Map) ...rawPolicy.cast<String, Object?>(),
      'allowNetwork': false,
      'cdn': const <String>[],
      'openLinkOrigins': const <String>[],
    };
    final data = jsonEncode({...artifact, 'policy': policy}).replaceAll('<', r'\u003c');
    unawaited(controller.runJavaScript('window.__diuiSetArtifact && window.__diuiSetArtifact($data); true;'));
  }

  Map<String, Object?> _renderArtifact(IntelligentUiArtifact card) {
    final json = card.toRendererJson();
    if (card.kind != IntelligentUiKind.widget) return json;
    final definition = json['definition'];
    if (definition is! Map) return json;
    final css = definition['css'];
    final jsFunctions = definition['jsFunctions'];
    return {
      ...json,
      'definition': {
        ...definition.cast<String, Object?>(),
        'css': '${css is String ? css : ''}\n$_widgetFitCss',
        'jsFunctions': '${jsFunctions is String ? jsFunctions : ''}\n$_widgetLinkBridge',
        // Start small so a short widget does not keep the model's initialHeight.
        'initialHeight': 48,
      },
    };
  }

  void _setTheme(bool dark) {
    unawaited(
      _controller?.runJavaScript(
        "window.__diuiSetTheme && window.__diuiSetTheme(${jsonEncode(dark ? 'dark' : 'light')}); true;",
      ),
    );
  }

  void _setLocale() {
    unawaited(
      _controller?.runJavaScript('window.__diuiSetLocale && window.__diuiSetLocale(${jsonEncode(_locale)}); true;'),
    );
  }

  Future<void> _onMessage(JavaScriptMessage message) async {
    if (!mounted || _gone) return;
    final parsed = parseIntelligentUiBridgeMessage(message.message, _token);
    if (parsed == null) return;
    switch (parsed.type) {
      case 'ready':
        _ready = true;
        _postArtifact();
        _setTheme(_dark);
        _setLocale();
        break;
      case 'resize':
        final height = parsed.height;
        if (height == null || !height.isFinite) return;
        setState(() => _height = (height.ceil() + 8).clamp(100, _maxHeight).toInt());
        break;
      case 'error':
        _setError(parsed.data['message'] is String ? parsed.data['message'] as String : 'renderer error');
        break;
      case 'download':
        if (widget.readOnly) return;
        final text = parsed.text;
        if (text == null) return;
        await SharePlus.instance.share(ShareParams(text: text, subject: parsed.name ?? widget.artifact.title ?? ''));
        break;
      case 'openLink':
        await _handleOpenLink(parsed);
        break;
      case 'prompt':
        await _handlePrompt(parsed);
        break;
    }
  }

  Future<void> _handleOpenLink(IntelligentUiBridgeMessage message) async {
    final raw = message.url?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.toLowerCase() != 'https' || !uri.hasAuthority) return;
    final allowed = switch (widget.artifact.policy['openLinkOrigins']) {
      final List<Object?> value => value.whereType<String>().toList(growable: false),
      _ => const <String>[],
    };
    if (allowed.isEmpty || !allowed.any((origin) => origin == uri.origin)) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Opening the browser is best-effort; the card itself stays usable.
    }
  }

  Future<void> _handlePrompt(IntelligentUiBridgeMessage message) async {
    final id = message.id;
    final text = message.text?.trim();
    if (id == null || text == null || text.isEmpty || text.length > 4000 || !_ready) return;
    if (widget.readOnly) {
      _reply(id, false, 'read-only');
      return;
    }
    if (!_scopeActive() || _actions.admit(id, DateTime.now()) == null) {
      _reply(id, false, 'unavailable');
      return;
    }
    bool approved;
    try {
      approved = await _confirm(text);
    } catch (_) {
      _actions.invalidate();
      _reply(id, false, 'cancelled');
      return;
    }
    if (!mounted) return;
    if (!_actions.isCurrent(id) || !_scopeActive()) {
      _actions.invalidate();
      _reply(id, false, 'cancelled');
      return;
    }
    if (!approved) {
      _actions.invalidate();
      _reply(id, false, 'cancelled');
      return;
    }
    if (!_actions.submit(id)) {
      _reply(id, false, 'replayed');
      return;
    }
    var ok = false;
    try {
      final sendPrompt = widget.onSendPrompt;
      ok = sendPrompt == null ? false : await sendPrompt(text);
    } catch (_) {
      ok = false;
    } finally {
      _reply(id, ok, ok ? null : 'send failed');
    }
  }

  Future<bool> _confirm(String text) async {
    final l10n = context.l10n;
    final result = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.chatIntelligentUiActionTitle),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.commonSend)),
        ],
      ),
    );
    return result == true;
  }

  bool _scopeActive() {
    try {
      final host = ref.read(activeHostProvider).id == widget.artifact.hostId;
      final session = ref.read(currentSessionProvider) == widget.artifact.sessionId;
      final connected = ref.read(activeConnectionProvider).value?.client != null;
      return host && session && connected;
    } catch (_) {
      return false;
    }
  }

  void _reply(int id, bool ok, String? error) {
    final controller = _controller;
    if (controller == null) return;
    final args = '${jsonEncode(id)}, ${jsonEncode(ok)}, ${jsonEncode(error)}';
    unawaited(controller.runJavaScript('window.__diuiReply && window.__diuiReply($args); true;'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final child = _gone
        ? _Unavailable(
            message: l10n.chatIntelligentUiUnavailable,
            action: TextButton(onPressed: _reload, child: Text(l10n.commonRetry)),
          )
        : _error != null
        ? _Unavailable(
            message: l10n.chatIntelligentUiUnavailable,
            action: TextButton(onPressed: _reload, child: Text(l10n.commonRetry)),
          )
        : _controller == null
        ? const SizedBox(height: 96, child: Center(child: CircularProgressIndicator()))
        : SizedBox(
            height: _height.toDouble(),
            // 只让长按进入 WebView，用于选中文字并弹出系统选择工具条；
            // 纵向拖动不注册，仍由外层 CustomScrollView 接管。
            child: WebViewWidget(
              controller: _controller!,
              gestureRecognizers: {Factory<LongPressGestureRecognizer>(LongPressGestureRecognizer.new)},
            ),
          );
    final title = widget.artifact.title?.trim();
    final cardBody = Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, widget.immersive ? 0 : 8),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
    if (widget.immersive && widget.artifact.kind == IntelligentUiKind.widget) {
      return _ImmersiveCard(title: title, child: cardBody);
    }
    return ChatCard(
      icon: AppIcons.generating,
      title: title == null || title.isEmpty ? l10n.chatIntelligentUiTitle : title,
      children: [cardBody],
    );
  }

  void _reload() {
    _loadGeneration++;
    final old = _guard;
    _guard = null;
    _controller = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.destroy();
        old.dispose();
      });
    }
    _gone = false;
    _error = null;
    _ready = false;
    _height = 96;
    _token = _newToken();
    _actions.reset();
    _load();
  }

  static String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _ImmersiveCard extends StatelessWidget {
  const _ImmersiveCard({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showTitle = title != null && title!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
            child: Row(
              children: [
                Icon(AppIcons.generating, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        child,
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
  }
}
