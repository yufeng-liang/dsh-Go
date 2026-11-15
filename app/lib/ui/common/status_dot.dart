// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// See THIRD_PARTY_NOTICES.md.

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/semantic_colors.dart';
import 'native_animation_surface.dart';

/// 状态语义。业务层把自己的枚举(引擎状态、远程连接状态)映射到这里。
enum StatusTone {
  /// 运行中 / 已连接。
  ok,

  /// 启动中 / 连接中 / 安装中(会呼吸)。
  busy,

  /// 降级、需要注意。
  warn,

  /// 失败 / 已崩溃。
  error,

  /// 已停止 / 未连接。
  idle,
}

/// 状态圆点。[StatusTone.busy] 时缓慢呼吸(透明度 1 ↔ 0.35)。
///
/// 颜色**不是唯一信号**:旁边总要配文字("运行中"/"已停止"),
/// 色弱用户和读屏都靠文字。
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.tone, this.size = 8, this.nativeAnimation = false});

  final StatusTone tone;
  final double size;

  /// Let the chat header breathe without scheduling Flutter frames on Android.
  final bool nativeAnimation;

  static Color colorFor(BuildContext context, StatusTone tone) {
    final colors = DshColors.of(context);
    return switch (tone) {
      StatusTone.ok => colors.success,
      StatusTone.busy => Theme.of(context).colorScheme.primary,
      StatusTone.warn => colors.warning,
      StatusTone.error => colors.danger,
      StatusTone.idle => Theme.of(context).colorScheme.outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context) => _FlutterStatusDot(tone: tone, size: size);
    if (!nativeAnimation || tone != StatusTone.busy || AppMotion.reduced(context)) return fallback(context);
    return NativeAnimationSurface(
      size: Size.square(size),
      config: {'kind': 'dot', 'color': colorFor(context, tone).toARGB32(), 'pulse': true, 'periodMs': 2400},
      fallback: fallback,
    );
  }
}

class _FlutterStatusDot extends StatefulWidget {
  const _FlutterStatusDot({required this.tone, required this.size});
  final StatusTone tone;
  final double size;

  @override
  State<_FlutterStatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_FlutterStatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final Animation<double> _opacity = _pulse.drive(
    Tween(begin: 1.0, end: 0.35).chain(CurveTween(curve: AppMotion.std)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_FlutterStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.tone == StatusTone.busy && !AppMotion.reduced(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: StatusDot.colorFor(context, widget.tone), shape: BoxShape.circle),
      ),
    );
  }
}
