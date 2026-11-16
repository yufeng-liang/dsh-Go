import 'package:dsh_app/native_animation/native_animation_channel.dart';
import 'package:dsh_app/ui/common/native_animation_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <MethodCall>[];
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NativeAnimationChannel.resetForTesting();
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(NativeAnimationChannel.channel, (call) async {
      calls.add(call);
      return call.method == 'isAvailable' ? true : null;
    });
  });

  tearDown(() {
    NativeAnimationChannel.resetForTesting();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(NativeAnimationChannel.channel, null);
  });

  Widget surface() => NativeAnimationSurface(
    size: const Size(40, 20),
    config: const {'kind': 'dot', 'color': 0xff123456},
    fallback: (_) => const Text('fallback'),
  );

  Map<dynamic, dynamic> latest() => calls.lastWhere((c) => c.method == 'upsert').arguments as Map;

  testWidgets('inherits opacity and clip, without scheduling idle frames', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Opacity(
            opacity: .25,
            child: ClipRect(child: Align(widthFactor: .5, heightFactor: 1, child: surface())),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final config = latest();
    expect(config['alpha'], .25);
    final clip = config['clip'] as List;
    expect((clip[2] as num) - (clip[0] as num), closeTo((config['width'] as num) / 2, .01));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final count = calls.length;
    await tester.pump(const Duration(seconds: 2));
    expect(calls.length, count);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls.last.method, 'remove');
  });

  testWidgets('dialog hides surfaces, popping restores them', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: Center(child: surface())),
      ),
    );
    await tester.pumpAndSettle();
    expect(latest()['visible'], isTrue);
    final dialog = showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: Text('modal')),
    );
    await tester.pumpAndSettle();
    expect(latest()['visible'], isFalse);
    navigator.currentState!.pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(latest()['visible'], isTrue);
  });

  testWidgets('missing platform plugin keeps Flutter implementation', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(NativeAnimationChannel.channel, (_) async {
      throw MissingPluginException();
    });
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: surface()));
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
