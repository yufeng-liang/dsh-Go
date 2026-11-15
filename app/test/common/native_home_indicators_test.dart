import 'dart:async';

import 'package:dsh_app/native_animation/native_animation_channel.dart';
import 'package:dsh_app/ui/chat/widgets/whale_tail.dart';
import 'package:dsh_app/ui/common/native_animation_surface.dart';
import 'package:dsh_app/ui/common/status_dot.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dsh/native_animation');
  final calls = <MethodCall>[];

  setUpAll(WhaleSprites.load);

  setUp(() {
    NativeAnimationChannel.resetForTesting();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isAvailable' ? true : null;
    });
  });

  tearDown(() {
    NativeAnimationChannel.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('capability probing does not mount the Flutter animation fallback', (tester) async {
    final available = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'isAvailable' ? await available.future : null;
    });
    var fallbackBuilds = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NativeAnimationSurface(
          size: const Size(20, 20),
          config: const {'kind': 'dot', 'color': 0xff123456},
          fallback: (_) {
            fallbackBuilds++;
            return const Text('Flutter animation');
          },
        ),
      ),
    );
    await settle(tester);
    expect(fallbackBuilds, 0, reason: 'probing must not start duplicate Dart clocks or image decoding');
    available.complete(false);
    await settle(tester);
    expect(find.text('Flutter animation'), findsOneWidget);
    expect(fallbackBuilds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native header dot and whale leave Flutter idle and update their native state', (tester) async {
    var level = 1;
    var color = Colors.blue;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Row(
                children: [
                  const StatusDot(tone: StatusTone.busy, nativeAnimation: true),
                  WhaleTail(level: level, color: color, nativeAnimation: true),
                ],
              );
            },
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(NativeAnimationSurface), findsNWidgets(2));
    expect(tester.binding.transientCallbackCount, 0, reason: 'native surfaces own the repeating clocks');
    expect(tester.binding.hasScheduledFrame, isFalse);
    final before = calls.length;
    await tester.pump(const Duration(seconds: 3));
    expect(calls.length, before, reason: 'no per-frame MethodChannel updates while stationary');

    update(() {
      level = 4;
      color = Colors.red;
    });
    await settle(tester);
    final configs = calls.where((c) => c.method == 'upsert').map((c) => c.arguments as Map);
    expect(configs.any((c) => c['kind'] == 'dot' && c['pulse'] == true), isTrue);
    expect(configs.any((c) => c['kind'] == 'whale' && c['level'] == 4 && c['color'] == Colors.red.toARGB32()), isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(calls.where((c) => c.method == 'remove').length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the header dot and whale in the Flutter still path', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Row(
              children: const [
                StatusDot(tone: StatusTone.busy, nativeAnimation: true),
                WhaleTail(level: 4, color: deepSeekBlue, nativeAnimation: true),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(NativeAnimationSurface), findsNothing);
    expect(calls, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.state<WhaleTailState>(find.byType(WhaleTail)).shownForm, 1);
    expect(tester.takeException(), isNull);
  });
}
