import 'package:dsh_app/native_animation/native_animation_channel.dart';
import 'package:dsh_app/pets/pet_pack.dart';
import 'package:dsh_app/ui/pets/pet_sprite.dart';
import 'package:dsh_app/ui/pets/pet_surface_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const animation = PetAnimation(
  name: 'idle',
  sheet: 'idle.png',
  frameWidth: 8,
  frameHeight: 10,
  cols: 2,
  box: Rect.fromLTWH(1, 2, 4, 5),
  frames: [PetFrame(0, 50), PetFrame(3, 80)],
  loop: false,
);
const pack = PetPack(
  id: 'fixture',
  name: 'fixture',
  canvas: Size(10, 12),
  anchorX: 4,
  baseline: 10,
  contentBox: Rect.fromLTWH(1, 2, 4, 8),
  animations: {'idle': animation},
  states: {
    'idle': ['idle'],
  },
);

void main() {
  test('native hop envelope contains every intermediate canvas', () {
    final motion = PetSurfaceMotion(
      serial: 1,
      kind: 'hop',
      duration: const Duration(milliseconds: 380),
      from: const Offset(-40, 24),
      height: 18,
    );
    const canvas = Size(30, 40);
    final envelope = motion.envelope(canvas);
    expect(motion.at(0), const Offset(-40, 24));
    expect(motion.at(1), Offset.zero);
    for (var i = 0; i <= 100; i++) {
      final frame = (Offset.zero & canvas).shift(motion.at(i / 100));
      expect(envelope.left, lessThanOrEqualTo(frame.left));
      expect(envelope.top, lessThanOrEqualTo(frame.top));
      expect(envelope.right, greaterThanOrEqualTo(frame.right));
      expect(envelope.bottom, greaterThanOrEqualTo(frame.bottom));
    }
  });

  test('mirrored art is not clipped at an off-centre canvas anchor', () {
    expect(petSurfaceBounds(pack, animation, 2, flip: true).right, 20);
    const edge = PetAnimation(
      name: 'edge',
      sheet: 'edge.png',
      frameWidth: 10,
      frameHeight: 12,
      cols: 1,
      box: Rect.fromLTWH(0, 0, 10, 12),
      frames: [PetFrame(0, 50)],
    );
    expect(petSurfaceBounds(pack, edge, 2, flip: true).left, -4);
  });

  test('native pause clock keeps interruption position until resumed', () {
    final motion = PetSurfaceMotion(
      serial: 1,
      kind: 'walk',
      duration: const Duration(seconds: 2),
      from: const Offset(-40, 0),
    );
    motion.synchronize(const Duration(milliseconds: 500), active: false);
    expect(motion.progress, 0.25);
    expect(motion.offset, const Offset(-30, 0));
  });

  testWidgets('native playback preserves source cells and does not schedule Flutter frames', (tester) async {
    NativeAnimationChannel.resetForTesting();
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(NativeAnimationChannel.channel, (call) async {
      if (call.method == 'isAvailable') return true;
      if (call.method == 'upsert') calls.add(Map<String, Object?>.from(call.arguments as Map));
      return null;
    });
    addTearDown(() {
      NativeAnimationChannel.resetForTesting();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(NativeAnimationChannel.channel, null);
    });
    var shown = 0;
    var ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PetSprite(
            pack: pack,
            anim: animation,
            scale: 2,
            nativeSurface: true,
            onShown: () => shown++,
            onEnd: () => ended++,
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    final config = calls.lastWhere((c) => c.containsKey('frames'));
    expect(config['asset'], 'assets/pets/fixture/idle.png');
    expect(config['frames'], [
      {'i': 0, 'ms': 50},
      {'i': 3, 'ms': 80},
    ]);
    expect(config['dst'], [4.0, 8.0, 16.0, 20.0]);
    expect(shown, 0, reason: 'onShown waits for native decoding');

    Future<void> emit(String type, {Object? serial}) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      NativeAnimationChannel.channel.name,
      NativeAnimationChannel.channel.codec.encodeMethodCall(
        MethodCall('event', {'id': config['id'], 'type': type, 'playbackSerial': serial ?? config['playbackSerial']}),
      ),
      (_) {},
    );
    await emit('ready');
    expect(shown, 1);
    final before = calls.length;
    await tester.pump(const Duration(seconds: 2));
    expect(ended, 0, reason: 'Dart must not run a second playback timer');
    expect(calls.length, before, reason: 'stable geometry must not send per-frame updates');
    expect(tester.binding.hasScheduledFrame, isFalse);
    await emit('ended', serial: -1);
    expect(ended, 0, reason: 'an old animation cannot finish the new one');
    await emit('ended');
    await emit('ended');
    expect(ended, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('imported sprite uses its private file instead of a Flutter asset key', (tester) async {
    NativeAnimationChannel.resetForTesting();
    final calls = <Map<String, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(NativeAnimationChannel.channel, (call) async {
      if (call.method == 'isAvailable') return true;
      if (call.method == 'upsert') calls.add(Map<String, Object?>.from(call.arguments as Map));
      return null;
    });
    addTearDown(() {
      NativeAnimationChannel.resetForTesting();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(NativeAnimationChannel.channel, null);
    });
    const imported = PetPack(
      id: 'imported',
      name: 'imported',
      dir: '/data/user/0/example/files/pets/imported',
      canvas: Size(10, 12),
      anchorX: 4,
      baseline: 10,
      contentBox: Rect.fromLTWH(1, 2, 4, 8),
      animations: {'idle': animation},
      states: {
        'idle': ['idle'],
      },
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: PetSprite(pack: imported, anim: animation, scale: 2, nativeSurface: true),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    final config = calls.lastWhere((c) => c.containsKey('frames'));
    expect(config['path'], '/data/user/0/example/files/pets/imported/idle.png');
    expect(config.containsKey('asset'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
