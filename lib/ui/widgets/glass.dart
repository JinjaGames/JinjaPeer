import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'liquid_background.dart';

/// Frosted glass surface: blur + translucent fill + light-catching border.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.lg),
    this.radius = R.lg,
    this.blur = 22,
    this.strong = false,
    this.tint,
    this.borderColor,
    this.shadow = true,
    this.margin,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final bool strong;
  final Color? tint;
  final Color? borderColor;
  final bool shadow;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final br = BorderRadius.circular(radius);
    final fill = strong ? jp.glassStrong : jp.glass;
    Widget box = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend((tint ?? Colors.transparent).withValues(alpha: 0.10), fill),
            Color.alphaBlend(
                (tint ?? Colors.transparent).withValues(alpha: 0.04),
                fill.withValues(alpha: fill.a * (jp.isDark ? 0.45 : 0.75))),
          ],
        ),
        border: Border.all(color: borderColor ?? jp.glassBorder, width: 1),
      ),
      child: child,
    );
    box = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Stack(
          children: [
            box,
            // top edge highlight – the "liquid" sheen
            Positioned(
              left: radius * 0.6,
              right: radius * 0.6,
              top: 0,
              height: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      jp.glassHighlight.withValues(alpha: 0),
                      jp.glassHighlight,
                      jp.glassHighlight.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (shadow) {
      box = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          boxShadow: [
            BoxShadow(color: jp.shadow, blurRadius: 30, spreadRadius: -8, offset: const Offset(0, 14)),
          ],
        ),
        child: box,
      );
    }
    if (margin != null) box = Padding(padding: margin!, child: box);
    return box;
  }
}

/// Glass card that reacts to hover and press with a subtle lift.
class GlassTile extends StatefulWidget {
  const GlassTile({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(S.lg),
    this.radius = R.lg,
    this.selected = false,
    this.tint,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool selected;
  final Color? tint;
  final String? tooltip;

  @override
  State<GlassTile> createState() => _GlassTileState();
}

class _GlassTileState extends State<GlassTile> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final interactive = widget.onTap != null;
    Widget w = AnimatedScale(
      scale: _down ? 0.985 : (_hover && interactive ? 1.008 : 1),
      duration: Motion.d(160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Motion.d(180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _hover && interactive
              ? [BoxShadow(color: jp.accent.withValues(alpha: 0.18), blurRadius: 28, spreadRadius: -6)]
              : const [],
        ),
        child: Glass(
          padding: widget.padding,
          radius: widget.radius,
          strong: _hover || widget.selected,
          tint: widget.selected ? jp.accent : widget.tint,
          borderColor: widget.selected ? jp.accent.withValues(alpha: 0.65) : null,
          shadow: false,
          child: widget.child,
        ),
      ),
    );
    if (interactive) {
      w = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: w,
        ),
      );
    }
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}

enum BtnKind { primary, secondary, ghost, danger }

/// Button with gradient fill (primary), glass (secondary) or text (ghost).
class JButton extends StatefulWidget {
  const JButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = BtnKind.primary,
    this.loading = false,
    this.dense = false,
    this.expand = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final bool loading;
  final bool dense;
  final bool expand;
  final String? tooltip;

  @override
  State<JButton> createState() => _JButtonState();
}

class _JButtonState extends State<JButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final enabled = widget.onPressed != null && !widget.loading;
    final h = widget.dense ? 34.0 : 42.0;
    final fg = switch (widget.kind) {
      BtnKind.primary => Colors.white,
      BtnKind.danger => Colors.white,
      BtnKind.secondary => jp.text,
      BtnKind.ghost => jp.textMuted,
    };
    BoxDecoration deco;
    switch (widget.kind) {
      case BtnKind.primary:
        deco = BoxDecoration(
          gradient: LinearGradient(colors: [
            Color.lerp(jp.accent, Colors.white, _hover ? 0.08 : 0)!,
            Color.lerp(jp.accent2, Colors.white, _hover ? 0.08 : 0)!,
          ]),
          borderRadius: BorderRadius.circular(R.md),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: jp.accent.withValues(alpha: _hover ? 0.45 : 0.28),
                    blurRadius: _hover ? 22 : 14,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        );
      case BtnKind.danger:
        deco = BoxDecoration(
          color: Color.lerp(jp.danger, Colors.white, _hover ? 0.08 : 0),
          borderRadius: BorderRadius.circular(R.md),
        );
      case BtnKind.secondary:
        deco = BoxDecoration(
          color: _hover ? jp.glassStrong : jp.glass,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: jp.glassBorder),
        );
      case BtnKind.ghost:
        deco = BoxDecoration(
          color: _hover ? jp.glass : Colors.transparent,
          borderRadius: BorderRadius.circular(R.md),
        );
    }
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: widget.dense ? 16 : 18, color: fg),
        if ((widget.loading || widget.icon != null) && widget.label.isNotEmpty)
          const SizedBox(width: S.sm),
        if (widget.label.isNotEmpty)
          Flexible(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: widget.dense ? 12.5 : 13.5,
              ),
            ),
          ),
      ],
    );
    Widget w = AnimatedOpacity(
      opacity: enabled ? 1 : 0.45,
      duration: Motion.d(150),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: Motion.d(120),
        child: AnimatedContainer(
          duration: Motion.d(160),
          height: h,
          padding: EdgeInsets.symmetric(horizontal: widget.label.isEmpty ? 0 : (widget.dense ? 12 : 18)),
          width: widget.label.isEmpty ? h : null,
          decoration: deco,
          child: content,
        ),
      ),
    );
    w = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled ? widget.onPressed : null,
        child: Semantics(button: true, label: widget.label, enabled: enabled, child: w),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}

/// Compact round icon button with hover glass.
class JIconButton extends StatefulWidget {
  const JIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
    this.size = 34,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final bool active;

  @override
  State<JIconButton> createState() => _JIconButtonState();
}

class _JIconButtonState extends State<JIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: Motion.d(140),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.active
                  ? jp.accent.withValues(alpha: 0.18)
                  : (_hover && enabled ? jp.glassStrong : Colors.transparent),
              borderRadius: BorderRadius.circular(widget.size / 3.2),
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.53,
              color: !enabled
                  ? jp.textFaint.withValues(alpha: 0.5)
                  : widget.color ?? (widget.active ? jp.accent : (_hover ? jp.text : jp.textMuted)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon, this.filled = false});
  final String text;
  final Color? color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final c = color ?? jp.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: 0.18) : c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Gradient icon in a soft rounded square.
class IconOrb extends StatelessWidget {
  const IconOrb(this.icon, {super.key, this.size = 40, this.colors, this.iconColor});
  final IconData icon;
  final double size;
  final List<Color>? colors;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final cs = colors ?? [jp.accent, jp.accent2];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          colors: [cs[0].withValues(alpha: 0.28), cs[1].withValues(alpha: 0.16)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: cs[0].withValues(alpha: 0.35)),
      ),
      child: Icon(icon, size: size * 0.5, color: iconColor ?? cs[0]),
    );
  }
}

/// Avatar: gradient circle with initials.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.seed, this.size = 40, this.online});
  final String name;
  final int seed;
  final double size;
  final bool? online;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final cs = avatarColors(seed);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: cs, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: cs[0].withValues(alpha: 0.35), blurRadius: 12, spreadRadius: -4)],
            ),
            child: Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.36,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online! ? jp.success : jp.textFaint,
                  border: Border.all(color: jp.bgTop, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Animated gradient progress bar with a moving sheen.
class LiquidProgress extends StatefulWidget {
  const LiquidProgress({
    super.key,
    required this.value,
    this.height = 8,
    this.color,
    this.paused = false,
    this.indeterminate = false,
  });

  final double value;
  final double height;
  final Color? color;
  final bool paused;
  final bool indeterminate;

  @override
  State<LiquidProgress> createState() => _LiquidProgressState();
}

class _LiquidProgressState extends State<LiquidProgress> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LiquidProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = !Motion.reduce && !widget.paused && (widget.indeterminate || widget.value < 1);
    if (animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final v = widget.value.clamp(0.0, 1.0);
    final colors = widget.color != null
        ? [widget.color!, Color.lerp(widget.color!, Colors.white, 0.25)!]
        : [jp.accent, jp.accent2];
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: jp.isDark ? const Color(0x14FFFFFF) : const Color(0x14000000)),
            if (widget.indeterminate)
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) => FractionallySizedBox(
                  alignment: Alignment(-1.4 + _c.value * 2.8, 0),
                  widthFactor: 0.35,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      borderRadius: BorderRadius.circular(widget.height),
                    ),
                  ),
                ),
              )
            else
              TweenAnimationBuilder<double>(
                tween: Tween(end: v),
                duration: Motion.d(450),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.height),
                        gradient: LinearGradient(
                          colors: widget.paused
                              ? [jp.textFaint, jp.textMuted]
                              : [colors[0], Color.lerp(colors[0], Colors.white, 0.45)!, colors[1]],
                          stops: widget.paused
                              ? null
                              : [0, (_c.value * 1.4 - 0.2).clamp(0.0, 1.0), 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Section title with optional trailing actions.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(color: jp.textMuted, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Friendly empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? S.lg : S.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconOrb(icon, size: compact ? 48 : 64),
              SizedBox(height: compact ? S.md : S.lg),
              Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: S.xs + 2),
              Text(message,
                  style: TextStyle(color: jp.textMuted, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: S.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Monospace, selectable code block with copy action.
class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.code, this.maxLines = 5, this.onCopied});
  final String code;
  final int maxLines;
  final VoidCallback? onCopied;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    widget.onCopied?.call();
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Container(
      decoration: BoxDecoration(
        color: jp.isDark ? const Color(0x33000000) : const Color(0x0D000000),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: jp.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: SelectableText(
              widget.code,
              maxLines: widget.maxLines,
              minLines: 1,
              style: TextStyle(
                fontFamily: kMono,
                fontSize: 11.5,
                height: 1.45,
                color: jp.textMuted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                Icon(Icons.text_snippet_outlined, size: 14, color: jp.textFaint),
                const SizedBox(width: 6),
                Text('${widget.code.length} karakter',
                    style: TextStyle(fontSize: 11.5, color: jp.textFaint)),
                const Spacer(),
                SmoothSwitcher(
                  duration: Duration(milliseconds: 200),
                  child: JButton(
                    key: ValueKey(_copied),
                    label: _copied ? 'Kopyalandı' : 'Kodu kopyala',
                    icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                    kind: _copied ? BtnKind.secondary : BtnKind.primary,
                    dense: true,
                    onPressed: _copy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsing dot used for "live" states.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

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
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: s + s * 1.4 * _c.value,
              height: s + s * 1.4 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
              ),
            ),
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + slide-up entrance, staggered by [index].
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduce) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + (index.clamp(0, 8) * 45)),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child),
      ),
      child: child,
    );
  }
}

/// Segmented control in glass.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<(T, String, IconData?)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: jp.isDark ? const Color(0x22000000) : const Color(0x0F000000),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: jp.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label, icon) in items)
            GestureDetector(
              onTap: () => onChanged(v),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: Motion.d(200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: v == value ? jp.glassStrong : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.sm),
                    boxShadow: v == value
                        ? [BoxShadow(color: jp.shadow, blurRadius: 8, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 15, color: v == value ? jp.accent : jp.textMuted),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: v == value ? jp.text : jp.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Icon for a file name based on its extension.
IconData fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'heic' || 'svg' || 'tiff' => Icons.image_rounded,
    'mp4' || 'mkv' || 'mov' || 'avi' || 'webm' || 'wmv' || 'flv' => Icons.movie_rounded,
    'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' || 'm4a' || 'opus' => Icons.music_note_rounded,
    'pdf' => Icons.picture_as_pdf_rounded,
    'doc' || 'docx' || 'odt' || 'rtf' || 'txt' || 'md' => Icons.description_rounded,
    'xls' || 'xlsx' || 'csv' || 'ods' => Icons.table_chart_rounded,
    'ppt' || 'pptx' || 'key' || 'odp' => Icons.slideshow_rounded,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'bz2' || 'xz' => Icons.folder_zip_rounded,
    'exe' || 'msi' || 'apk' || 'dmg' || 'deb' || 'appx' => Icons.apps_rounded,
    'dart' || 'js' || 'ts' || 'py' || 'java' || 'c' || 'cpp' || 'cs' || 'go' || 'rs' || 'html' || 'css' || 'json' =>
      Icons.code_rounded,
    'iso' || 'img' => Icons.album_rounded,
    'ttf' || 'otf' || 'woff' => Icons.font_download_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

Color fileColor(String name) {
  final i = fileIcon(name);
  if (i == Icons.image_rounded) return const Color(0xFF34D399);
  if (i == Icons.movie_rounded) return const Color(0xFFF472B6);
  if (i == Icons.music_note_rounded) return const Color(0xFFFBBF24);
  if (i == Icons.picture_as_pdf_rounded) return const Color(0xFFF87171);
  if (i == Icons.folder_zip_rounded) return const Color(0xFFA78BFA);
  if (i == Icons.apps_rounded) return const Color(0xFFFB923C);
  if (i == Icons.code_rounded) return const Color(0xFF60A5FA);
  return const Color(0xFF38BDF8);
}
