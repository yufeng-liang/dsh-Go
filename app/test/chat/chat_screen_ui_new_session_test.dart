import 'package:dsh_app/state/attachments.dart';
import 'package:dsh_app/state/chat_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/state/workspaces_state.dart';
import 'package:dsh_app/ui/chat/chat_list.dart';
import 'package:dsh_app/ui/chat/chat_screen.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

class _UiChatController extends FakeChatController {
  _UiChatController(
    super.sessionId,
    super.initial, {
    this.syncReady = true,
    this.sendFails = false,
    this.sendThrows = false,
  });

  final bool syncReady;
  final bool sendFails;
  final bool sendThrows;

  @override
  Future<bool> waitForSync({bool Function()? isCurrent}) async => syncReady && (isCurrent?.call() ?? true);

  @override
  Future<bool> send(
    String text, {
    List<DraftAttachment> attachments = const [],
    SendMode mode = SendMode.now,
    bool verbatim = false,
    Future<bool> Function(String requestId)? beforeDeliver,
    bool Function()? deliveryAllowed,
  }) async {
    if (sendThrows) throw StateError('send failed');
    if (sendFails) {
      sent.add(text);
      return false;
    }
    return super.send(
      text,
      attachments: attachments,
      mode: mode,
      verbatim: verbatim,
      beforeDeliver: beforeDeliver,
      deliveryAllowed: deliveryAllowed,
    );
  }
}

class _UiWorkspaces extends WorkspacesController {
  @override
  WorkspacesState build() => const WorkspacesState();
}

class _UiSessions extends SessionsController {
  var creates = 0;
  var fail = false;

  @override
  Future<void> refresh() async {}
  String? lastWorkspaceId;
  String? lastCreated;

  @override
  Future<List<SessionSummary>> build() async => [
    SessionSummary(
      sessionId: 'ui-new-session',
      updatedAt: DateTime(2026, 11, 23),
      running: false,
      blank: false,
      agentAvailable: true,
    ),
  ];

  @override
  Future<String> createForConnection(
    HostConnection conn, {
    required bool Function() isCurrent,
    bool autoApprove = true,
    String? workspaceId,
    void Function(String sessionId)? onCreated,
  }) async {
    creates++;
    lastWorkspaceId = workspaceId;
    if (fail) throw StateError('create failed');
    if (!isCurrent()) throw StateError('superseded');
    const id = 'ui-new-session';
    lastCreated = id;
    onCreated?.call(id);
    return id;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ChatHarness harness,
  _UiSessions sessions, {
  bool syncReady = true,
  bool sendFails = false,
  bool sendThrows = false,
}) async {
  usePhoneView(tester);
  mockClipboard(tester);
  await tester.pumpWidget(
    testApp(
      const ChatScreen(),
      overrides: [
        for (final override in harness.overrides)
          if (override.origin != sessionsProvider && override.origin != chatProvider) override,
        sessionsProvider.overrideWith(() => sessions),
        workspacesProvider.overrideWith(_UiWorkspaces.new),
        chatProvider.overrideWith2(
          (id) => harness.controllers[id] = _UiChatController(
            id,
            const ChatState(loading: false),
            syncReady: syncReady,
            sendFails: sendFails,
            sendThrows: sendThrows,
          ),
        ),
      ],
    ),
  );
  await pumpFrames(tester, 8);
}

ChatList _list(WidgetTester tester) => tester.widget<ChatList>(find.byType(ChatList));

void main() {
  testWidgets('new session action creates, selects and sends once', (tester) async {
    final harness = ChatHarness(session: 'source');
    final sessions = _UiSessions();
    await _pumpScreen(tester, harness, sessions);

    final result = await _list(tester).onSendNewSession!('继续', uiId: 'ui-1', nodeId: 'choice-1');

    expect(sessions.creates, 1);
    expect(result.sessionId, 'ui-new-session');
    expect(result.sent, isTrue);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(ChatScreen))).read(currentSessionProvider),
      'ui-new-session',
    );
    expect(harness.controllers['ui-new-session']?.sentNow, isEmpty);
    expect(harness.controllers['ui-new-session']?.sent, ['继续']);
  });

  testWidgets('concurrent new session actions create only one session', (tester) async {
    final harness = ChatHarness(session: 'source');
    final sessions = _UiSessions();
    await _pumpScreen(tester, harness, sessions);

    final handler = _list(tester).onSendNewSession!;
    final results = await Future.wait([
      handler('先', uiId: 'ui-1', nodeId: 'choice-1'),
      handler('后', uiId: 'ui-2', nodeId: 'choice-2'),
    ]);

    expect(sessions.creates, 1);
    expect(results.where((result) => result.sent), hasLength(1));
  });

  testWidgets('failed creation keeps the source session', (tester) async {
    final harness = ChatHarness(session: 'source');
    final sessions = _UiSessions()..fail = true;
    await _pumpScreen(tester, harness, sessions);
    final before = ProviderScope.containerOf(tester.element(find.byType(ChatScreen))).read(currentSessionProvider);

    final result = await _list(tester).onSendNewSession!('继续', uiId: 'ui-1', nodeId: 'choice-1');

    expect(result.sent, isFalse);
    expect(result.sessionId, isNull);
    expect(ProviderScope.containerOf(tester.element(find.byType(ChatScreen))).read(currentSessionProvider), before);
  });

  testWidgets('sync failure keeps the text in the new session draft', (tester) async {
    final harness = ChatHarness(session: 'source');
    final sessions = _UiSessions();
    await _pumpScreen(tester, harness, sessions, syncReady: false);

    final result = await _list(tester).onSendNewSession!('继续', uiId: 'ui-1', nodeId: 'choice-1');

    expect(sessions.creates, 1);
    expect(result.sessionId, 'ui-new-session');
    expect(result.sent, isFalse);
    expect(harness.controllers['ui-new-session']?.sent, isEmpty);
  });

  testWidgets('send returning false restores the text as a draft', (tester) async {
    final harness = ChatHarness(session: 'source');
    final sessions = _UiSessions();
    await _pumpScreen(tester, harness, sessions, sendFails: true);

    final result = await _list(tester).onSendNewSession!('继续', uiId: 'ui-1', nodeId: 'choice-1');

    expect(result.sessionId, 'ui-new-session');
    expect(result.sent, isFalse);
    expect(harness.controllers['ui-new-session']?.sent, ['继续']);
  });

  testWidgets('send throwing restores the text and reports not sent', (tester) async {
    final harness = ChatHarness(session: 'source');
    final sessions = _UiSessions();
    await _pumpScreen(tester, harness, sessions, sendThrows: true);

    final result = await _list(tester).onSendNewSession!('继续', uiId: 'ui-1', nodeId: 'choice-1');

    expect(result.sessionId, 'ui-new-session');
    expect(result.sent, isFalse);
    expect(harness.controllers['ui-new-session']?.sent, isEmpty);
  });

  testWidgets('retrying the same button reuses the created session', (tester) async {
    final harness = ChatHarness(session: 'source');
    final sessions = _UiSessions();
    await _pumpScreen(tester, harness, sessions);
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    final handler = _list(tester).onSendNewSession!;

    final first = await handler('继续', uiId: 'ui-1', nodeId: 'choice-1');
    expect(first.sent, isTrue);
    container.read(currentSessionProvider.notifier).select('source');
    await pumpFrames(tester, 4);

    final retried = await handler('再试', uiId: 'ui-1', nodeId: 'choice-1');

    expect(sessions.creates, 1);
    expect(retried.sessionId, 'ui-new-session');
    expect(retried.sent, isTrue);
    expect(harness.controllers['ui-new-session']?.sent, ['继续', '再试']);
  });
}
