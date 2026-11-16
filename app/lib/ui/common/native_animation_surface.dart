import 'dart:async';
import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../native_animation/native_animation_channel.dart';

/// Suppresses surfaces underneath Flutter overlays such as the side drawers.
class NativeAnimationVisibility extends InheritedWidget {
  const NativeAnimationVisibility({super.key, required this.visible, required super.child});

  final bool visible;

  @override
  bool updateShouldNotify(NativeAnimationVisibility oldWidget) => visible != oldWidget.visible;
}

/// Keeps layout and semantics in Flutter, without a Flutter ticker for playback.
/// Geometry is sampled after existing frames; this widget never requests frames
/// merely to keep an Android surface aligned.
class NativeAnimationSurface extends StatefulWidget {
  const NativeAnimationSurface({
    super.key,
    required this.size,
    required this.config,
    required this.fallback,
    this.visible = true,
    this.opacity = 1,
    this.onEvent,
  });

  final Size size;
  final Map<String, Object?> config;
  final WidgetBuilder fallback;
  final bool visible;
  final double opacity;
  final ValueChanged<Map<String, Object?>>? onEvent;

  @override
  State<NativeAnimationSurface> createState() => _NativeAnimationSurfaceState();
}

class _NativeAnimationSurfaceState extends State<NativeAnimationSurface> with WidgetsBindingObserver {
  final _box = GlobalKey();
  late final int _id;
  bool _native = NativeAnimationChannel.supported && NativeAnimationChannel.available.value;
  bool _initializing = NativeAnimationChannel.supported && !NativeAnimationChannel.availabilityChecked;
  bool _active = true;
  bool _scopeVisible = true;
  bool _routeVisible = true;
  ModalRoute<dynamic>? _route;
  bool _ticking = true;
  bool _attached = true;
  String? _last;
  Future<void> _operations = Future.value();

  @override
  void initState() {
    super.initState();
    _id = NativeAnimationChannel.register(_event);
    WidgetsBinding.instance.addObserver(this);
    _active = _isVisible(WidgetsBinding.instance.lifecycleState);
    unawaited(_initialize());
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  static bool _isVisible(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

  Future<void> _initialize() async {
    try {
      final available = await NativeAnimationChannel.ensureAvailable();
      if (mounted) {
        setState(() {
          _initializing = false;
          _native = available;
        });
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _event(Map<String, Object?> event) {
    if (!mounted) return;
    if (event['type'] == 'reset') {
      _last = null;
      WidgetsBinding.instance.scheduleFrame();
    }
    if (event['type'] == 'error') {
      _fail(StateError('${event['code']}: ${event['message']}'), StackTrace.current);
    }
    widget.onEvent?.call(event);
  }

  void _fail(Object error, StackTrace stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'native animation'));
    if (mounted && (_native || _initializing)) {
      final hadSurface = _native;
      setState(() {
        _initializing = false;
        _native = false;
      });
      if (hadSurface) _enqueue(() => NativeAnimationChannel.remove(_id));
    }
  }

  void _enqueue(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation()).catchError((Object error, StackTrace stack) {
      // Removal can also fail after an engine detaches; report it rather than
      // leaving an unhandled asynchronous error.
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'native animation'));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scopeVisible = context.dependOnInheritedWidgetOfExactType<NativeAnimationVisibility>()?.visible ?? true;
    _routeVisible = ModalRoute.isCurrentOf(context) ?? true;
    _route = ModalRoute.of(context);
    _ticking = TickerMode.valuesOf(context).enabled;
    _syncVisibility();
  }

  @override
  void didUpdateWidget(NativeAnimationSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = _isVisible(state);
    _syncVisibility();
    if (_active) {
      _last = null;
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  bool get _visible =>
      _native &&
      _active &&
      _attached &&
      _scopeVisible &&
      _routeVisible &&
      (_route?.animation?.isCompleted ?? true) &&
      (_route?.secondaryAnimation?.isDismissed ?? true) &&
      _ticking &&
      widget.visible;

  void _syncVisibility() {
    if (!_native || _visible || _last == null) return;
    _last = null;
    _enqueue(() => NativeAnimationChannel.upsert({'id': _id, 'visible': false}));
  }

  void _afterFrame(Duration _) {
    if (!mounted) return;
    if (_native && _attached) _syncGeometry();
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  void _syncGeometry() {
    if (!_visible) {
      _syncVisibility();
      return;
    }
    final box = _box.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final dpr = View.of(context).devicePixelRatio;
    final transform = box.getTransformTo(null);
    final rect = MatrixUtils.transformRect(transform, Offset.zero & box.size);
    var clip = Offset.zero & (View.of(context).physicalSize / dpr);
    var alpha = widget.opacity;
    RenderObject? ancestor = box.parent;
    while (ancestor != null) {
      if (ancestor is RenderOffstage && ancestor.offstage) alpha = 0;
      if (ancestor is RenderFollowerLayer && !ancestor.showWhenUnlinked && ancestor.link.leader == null) alpha = 0;
      if (ancestor is RenderOpacity) alpha *= ancestor.opacity;
      if (ancestor is RenderAnimatedOpacity) alpha *= ancestor.opacity.value;
      if (ancestor is RenderClipRect && ancestor.clipBehavior != Clip.none) {
        final local = ancestor.clipper?.getClip(ancestor.size) ?? Offset.zero & ancestor.size;
        clip = clip.intersect(MatrixUtils.transformRect(ancestor.getTransformTo(null), local));
      }
      ancestor = ancestor.parent;
    }
    final clipped = rect.intersect(clip);
    final config = <String, Object?>{
      ...widget.config,
      'id': _id,
      'x': (rect.left * dpr).round(),
      'y': (rect.top * dpr).round(),
      'width': (rect.width * dpr).round(),
      'height': (rect.height * dpr).round(),
      'visible': alpha > 0 && !clipped.isEmpty,
      'alpha': alpha,
      'clip': [
        (clipped.left - rect.left) * dpr,
        (clipped.top - rect.top) * dpr,
        (clipped.right - rect.left) * dpr,
        (clipped.bottom - rect.top) * dpr,
      ],
    };
    final encoded = jsonEncode(config);
    if (encoded == _last) return;
    _last = encoded;
    _enqueue(() async {
      try {
        await NativeAnimationChannel.upsert(config);
      } catch (error, stack) {
        _fail(error, stack);
      }
    });
  }

  @override
  void deactivate() {
    _attached = false;
    _syncVisibility();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _last = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NativeAnimationChannel.unregister(_id);
    if (_native) _enqueue(() => NativeAnimationChannel.remove(_id));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _native || _initializing ? SizedBox.fromSize(key: _box, size: widget.size) : widget.fallback(context);
}
