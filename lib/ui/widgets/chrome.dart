import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/app_controller.dart';
import '../theme.dart';
import 'glass.dart';
import 'liquid_background.dart';

/// Gives the widget tree access to the [AppController] and rebuilds
/// dependents when it changes.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppX on BuildContext {
  AppController get app => AppScope.of(this);
  AppController get appRead => AppScope.read(this);
}

bool get hasCustomTitleBar => Platform.isWindows || Platform.isLinux;

/// Frameless window title bar with drag area and window buttons.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, this.leading});
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    if (!hasCustomTitleBar) return const SizedBox(height: 0);
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.only(left: S.lg),
                alignment: Alignment.centerLeft,
                child: leading,
              ),
            ),
          ),
          const _WinButton(icon: Icons.remove_rounded, kind: _WinKind.minimize),
          const _WinButton(icon: Icons.crop_square_rounded, kind: _WinKind.maximize),
          const _WinButton(icon: Icons.close_rounded, kind: _WinKind.close),
        ],
      ),
    );
  }
}

enum _WinKind { minimize, maximize, close }

class _WinButton extends StatefulWidget {
  const _WinButton({required this.icon, required this.kind});
  final IconData icon;
  final _WinKind kind;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  Future<void> _act() async {
    switch (widget.kind) {
      case _WinKind.minimize:
        await windowManager.minimize();
      case _WinKind.maximize:
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      case _WinKind.close:
        await windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final isClose = widget.kind == _WinKind.close;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _act,
        child: AnimatedContainer(
          duration: Motion.d(120),
          width: 46,
          height: 38,
          color: _hover ? (isClose ? const Color(0xFFE81123) : jp.glassStrong) : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.kind == _WinKind.maximize ? 14 : 17,
            color: _hover && isClose ? Colors.white : jp.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Listens to app notices and shows stacked glass toasts (top-right).
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});
  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  final _items = <AppNotice>[];
  StreamSubscription<AppNotice>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= context.appRead.notices.listen(_add);
  }

  void _add(AppNotice n) {
    setState(() {
      _items.add(n);
      if (_items.length > 4) _items.removeAt(0);
    });
    Future<void>.delayed(Duration(milliseconds: n.error ? 7000 : 4500), () => _remove(n));
  }

  void _remove(AppNotice n) {
    if (!mounted) return;
    setState(() => _items.remove(n));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: hasCustomTitleBar ? 46 : 16,
          right: 16,
          width: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final n in _items)
                Padding(
                  key: ValueKey(n.id),
                  padding: const EdgeInsets.only(bottom: S.sm),
                  child: Reveal(
                    child: Glass(
                      strong: true,
                      blur: 30,
                      radius: R.md,
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      tint: n.error ? jp.danger : jp.accent,
                      borderColor: (n.error ? jp.danger : jp.accent).withValues(alpha: 0.4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            n.error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 20,
                            color: n.error ? jp.danger : jp.accent,
                          ),
                          const SizedBox(width: S.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title, style: context.tt.titleSmall),
                                const SizedBox(height: 2),
                                Text(n.body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: jp.textMuted, fontSize: 12.5, height: 1.4)),
                                if (n.action != null) ...[
                                  const SizedBox(height: S.sm),
                                  JButton(
                                    label: n.actionLabel ?? 'Aç',
                                    dense: true,
                                    kind: BtnKind.secondary,
                                    onPressed: () {
                                      n.action!();
                                      _remove(n);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                          JIconButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Kapat',
                            size: 26,
                            onPressed: () => _remove(n),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
