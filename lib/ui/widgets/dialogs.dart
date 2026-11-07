import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass.dart';
import 'liquid_background.dart';

/// Shows [child] in a centered glass sheet over a blurred backdrop.
Future<T?> showGlassDialog<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 520,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.d(260),
    pageBuilder: (context, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (context, anim, _, _) {
      final jp = context.jp;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: dismissible ? () => Navigator.of(context).maybePop() : null,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8 * curved.value, sigmaY: 8 * curved.value),
                child: ColoredBox(
                  color: (jp.isDark ? Colors.black : const Color(0xFF1E293B))
                      .withValues(alpha: (jp.isDark ? 0.45 : 0.18) * curved.value),
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(curved),
                child: Padding(
                  padding: const EdgeInsets.all(S.xl),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Glass(
                        strong: true,
                        blur: 40,
                        radius: R.xl,
                        padding: const EdgeInsets.all(S.xl),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Standard dialog header: icon, title, close button.
class DialogHeader extends StatelessWidget {
  const DialogHeader({super.key, required this.icon, required this.title, this.subtitle, this.colors});
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconOrb(icon, size: 44, colors: colors),
        const SizedBox(width: S.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.tt.titleLarge),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(subtitle!, style: TextStyle(color: jp.textMuted, fontSize: 13, height: 1.4)),
                ),
            ],
          ),
        ),
        JIconButton(
          icon: Icons.close_rounded,
          tooltip: 'Kapat (Esc)',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Onayla',
  bool danger = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final jp = context.jp;
  final r = await showGlassDialog<bool>(
    context,
    maxWidth: 440,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DialogHeader(
          icon: icon,
          title: title,
          colors: danger ? [jp.danger, jp.warning] : null,
        ),
        const SizedBox(height: S.lg),
        Text(message, style: TextStyle(color: jp.textMuted, height: 1.5)),
        const SizedBox(height: S.xl),
        Builder(
          builder: (context) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              JButton(
                label: 'Vazgeç',
                kind: BtnKind.ghost,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: S.sm),
              JButton(
                label: confirmLabel,
                kind: danger ? BtnKind.danger : BtnKind.primary,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Kaydet',
  IconData icon = Icons.edit_rounded,
  int maxLength = 40,
}) {
  final ctrl = TextEditingController(text: initial);
  return showGlassDialog<String>(
    context,
    maxWidth: 440,
    child: Builder(builder: (context) {
      void submit() {
        final v = ctrl.text.trim();
        if (v.isNotEmpty) Navigator.of(context).pop(v);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogHeader(icon: icon, title: title),
          const SizedBox(height: S.lg),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: maxLength,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: S.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              JButton(label: 'Vazgeç', kind: BtnKind.ghost, onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: S.sm),
              JButton(label: confirmLabel, onPressed: submit),
            ],
          ),
        ],
      );
    }),
  );
}
