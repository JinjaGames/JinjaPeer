import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Global motion preference (set from settings).
class Motion {
  static bool reduce = false;
  static Duration d(int ms) => reduce ? Duration.zero : Duration(milliseconds: ms);
}

/// Slowly drifting, blurred color blobs behind all glass surfaces.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key, required this.child});
  final Widget child;

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 48));

  @override
  void initState() {
    super.initState();
    if (!Motion.reduce) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    if (Motion.reduce && _c.isAnimating) _c.stop();
    if (!Motion.reduce && !_c.isAnimating) _c.repeat();
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [jp.bgTop, jp.bgBottom],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.decal),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _BlobPainter(_c.value, jp.blobs, jp.isDark),
              ),
            ),
          ),
        ),
        // Very soft vignette for depth.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 1.3,
                colors: [
                  Colors.transparent,
                  jp.isDark ? const Color(0x55000000) : const Color(0x10FFFFFF),
                ],
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.t, this.colors, this.dark);
  final double t;
  final List<Color> colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * pi;
    final specs = <(double, double, double, double, double)>[
      // cx, cy, radius factor, phase, speed
      (0.15, 0.20, 0.42, 0.0, 1),
      (0.85, 0.25, 0.36, 1.7, -1),
      (0.70, 0.85, 0.40, 3.1, 1),
      (0.25, 0.80, 0.30, 4.4, -2),
    ];
    for (var i = 0; i < specs.length; i++) {
      final (cx, cy, rf, phase, speed) = specs[i];
      final dx = cos(a * speed + phase) * 0.08;
      final dy = sin(a * speed * 0.8 + phase) * 0.07;
      final center = Offset((cx + dx) * size.width, (cy + dy) * size.height);
      final r = rf * max(size.width, size.height) * (0.92 + 0.08 * sin(a * 2 + phase));
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          colors[i].withValues(alpha: dark ? 0.42 : 0.55),
          colors[i].withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t || old.dark != dark;
}

/// AnimatedSize that becomes a plain child when motion is reduced
/// (a zero-duration AnimatedSize re-dirties itself during layout).
class SmoothSize extends StatelessWidget {
  const SmoothSize({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.curve = Curves.easeOutCubic,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduce || duration == Duration.zero) return child;
    return AnimatedSize(duration: duration, curve: curve, alignment: alignment, child: child);
  }
}

/// AnimatedSwitcher that swaps instantly (no lingering old child) when
/// motion is reduced.
class SmoothSwitcher extends StatelessWidget {
  const SmoothSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
    this.switchInCurve = Curves.easeOutCubic,
    this.transitionBuilder = AnimatedSwitcher.defaultTransitionBuilder,
  });

  final Widget child;
  final Duration duration;
  final Curve switchInCurve;
  final AnimatedSwitcherTransitionBuilder transitionBuilder;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduce) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: switchInCurve,
      transitionBuilder: transitionBuilder,
      child: child,
    );
  }
}
