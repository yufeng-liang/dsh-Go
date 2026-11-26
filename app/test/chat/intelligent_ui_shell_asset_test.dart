import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('intelligent UI production assets', () {
    test('live shell exposes a guarded newSession bridge', () {
      final shell = File('assets/intelligent_ui/shell.html').readAsStringSync();

      expect(shell, contains('window.__diuiSetNewSession=function(enabled)'));
      expect(shell, contains('host.sendNewSession=function(text,nodeId)'));
      expect(shell, contains("send('newSession',{id:id,text:String(text),nodeId:String(nodeId||'')})"));
      expect(shell, contains('delete host.sendNewSession'));
      expect(shell, contains("if(error==='cancelled') err.name='AbortError';"));
    });

    test('offline renderer forwards sendNewSession with the node id', () {
      final renderer = File('assets/intelligent_ui/renderer.js').readAsStringSync();

      expect(renderer, contains('sendNewSession:t.sendNewSession?'));
      expect(renderer, contains('sendNewSession(s.admitPrompt(v),S)'));
      expect(renderer, contains('AbortError'));
      expect(renderer, contains('diagramLoading'));
      expect(renderer, contains('正在渲染图表'));
    });

    test('asset version records the local patch', () {
      final version = File('assets/intelligent_ui/VERSION').readAsStringSync();

      expect(version, contains('deepseek-harness-intelligent-ui 0.2.17'));
      expect(version, contains('local patch: sendNewSession'));
      expect(version, contains('cancellation handling'));
      expect(version, contains('Mermaid loading state'));
    });
  });
}
