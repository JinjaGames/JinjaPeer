import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../models/models.dart';
import '../services/app_controller.dart';
import '../services/peer_session.dart';
import 'connect/connect_flow.dart';
import 'pages/connections_page.dart';
import 'pages/contacts_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/requests_page.dart';
import 'pages/settings_page.dart';
import 'pages/transfers_page.dart';
import 'send_helpers.dart';
import 'theme.dart';
import 'widgets/chrome.dart';
import 'widgets/glass.dart';
import 'widgets/liquid_background.dart';

class _NavItem {
  const _NavItem(this.page, this.label, this.icon, this.activeIcon, this.shortcut);
  final AppPage page;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String shortcut;
}

const _nav = [
  _NavItem(AppPage.home, 'Ana sayfa', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Ctrl+1'),
  _NavItem(AppPage.connections, 'Bağlantılar', Icons.hub_outlined, Icons.hub_rounded, 'Ctrl+2'),
  _NavItem(AppPage.transfers, 'Aktarımlar', Icons.swap_vert_rounded, Icons.swap_vert_circle_rounded, 'Ctrl+3'),
  _NavItem(AppPage.requests, 'İstekler', Icons.inbox_outlined, Icons.inbox_rounded, 'Ctrl+4'),
  _NavItem(AppPage.history, 'Geçmiş', Icons.history_rounded, Icons.manage_history_rounded, 'Ctrl+5'),
  _NavItem(AppPage.contacts, 'Kişilerim', Icons.people_outline_rounded, Icons.people_rounded, 'Ctrl+6'),
  _NavItem(AppPage.settings, 'Ayarlar', Icons.tune_rounded, Icons.tune_rounded, 'Ctrl+7'),
];

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  bool _dragging = false;

  void _go(AppPage p) => context.appRead.page.value = p;

  Future<void> _onDrop(DropDoneDetails d) async {
    setState(() => _dragging = false);
    final app = context.appRead;
    final paths = d.files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
    if (paths.isEmpty) return;
    final sources = await sourcesFromPaths(paths);
    if (!mounted) return;
    final selected = app.sessionById(app.selectedSession.value);
    final target = app.page.value == AppPage.connections && selected != null && selected.state.isLive ? selected : null;
    await sendTo(context, target, sources);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => showConnectDialog(context),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
            showConnectDialog(context, mode: ConnectMode.join),
        for (var i = 0; i < _nav.length; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () =>
              _go(_nav[i].page),
      },
      child: Focus(
        autofocus: true,
        child: LiquidBackground(
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: _onDrop,
            child: Stack(
              children: [
                Column(
                  children: [
                    TitleBar(
                      leading: wide
                          ? null
                          : Text('JinjaPeer', style: TextStyle(color: context.jp.textMuted, fontSize: 12)),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (wide) const _Sidebar(),
                          Expanded(
                            child: ValueListenableBuilder<AppPage>(
                              valueListenable: app.page,
                              builder: (context, page, _) => SmoothSwitcher(
                                duration: Duration(milliseconds: 280),
                                switchInCurve: Curves.easeOutCubic,
                                transitionBuilder: (child, anim) => FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(anim),
                                    child: child,
                                  ),
                                ),
                                child: KeyedSubtree(key: ValueKey(page), child: _pageFor(page)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!wide) const _BottomNav(),
                  ],
                ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _dragging ? 1 : 0,
                    duration: Duration(milliseconds: 180),
                    child: const _DropOverlay(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageFor(AppPage p) => switch (p) {
        AppPage.home => const HomePage(),
        AppPage.connections => const ConnectionsPage(),
        AppPage.transfers => const TransfersPage(),
        AppPage.requests => const RequestsPage(),
        AppPage.history => const HistoryPage(),
        AppPage.contacts => const ContactsPage(),
        AppPage.settings => const SettingsPage(),
      };
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final live = app.liveSessions;
    return Container(
      color: (jp.isDark ? Colors.black : Colors.white).withValues(alpha: 0.35),
      padding: const EdgeInsets.all(S.xxl),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.xl),
          border: Border.all(color: jp.accent, width: 2),
          color: jp.accent.withValues(alpha: 0.08),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconOrb(Icons.file_upload_rounded, size: 84),
              const SizedBox(height: S.lg),
              Text('Göndermek için bırak', style: context.tt.headlineSmall),
              const SizedBox(height: S.xs),
              Text(
                live.isEmpty
                    ? 'Önce bir bağlantı kurmalısın.'
                    : live.length == 1
                        ? '${live.first.displayName} kişisine gönderilecek'
                        : 'Bıraktıktan sonra kime gönderileceğini seçeceksin',
                style: TextStyle(color: jp.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _badgeFor(AppController app, AppPage p) => switch (p) {
      AppPage.requests => app.transfers.incomingPending.length,
      AppPage.connections => app.liveSessions.length,
      AppPage.transfers => app.transfers.active.length,
      _ => 0,
    };

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.md, hasCustomTitleBar ? 0 : S.md, 0, S.md),
      child: Glass(
        width: 236,
        padding: const EdgeInsets.fromLTRB(S.md, S.lg, S.md, S.md),
        radius: R.xl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Logo(),
            const SizedBox(height: S.xl),
            JButton(
              label: 'Yeni bağlantı',
              icon: Icons.add_rounded,
              expand: true,
              tooltip: 'Davet oluştur ya da koda katıl (Ctrl+N)',
              onPressed: () => showConnectDialog(context),
            ),
            const SizedBox(height: S.lg),
            Expanded(
              child: ValueListenableBuilder<AppPage>(
                valueListenable: app.page,
                builder: (context, page, _) => ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final n in _nav)
                      _SideNavTile(
                        item: n,
                        selected: page == n.page,
                        badge: _badgeFor(app, n.page),
                        urgent: n.page == AppPage.requests,
                        onTap: () => app.page.value = n.page,
                      ),
                  ],
                ),
              ),
            ),
            const _SpeedMeter(),
            const SizedBox(height: S.md),
            GlassTile(
              padding: const EdgeInsets.all(10),
              radius: R.md,
              onTap: () => app.page.value = AppPage.settings,
              tooltip: 'Kimlik parmak izin: ${app.identity.fingerprint}',
              child: Row(
                children: [
                  Avatar(name: app.settings.displayName, seed: seedOf(app.identity.publicKeyB64), size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.settings.displayName,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                        Text(app.identity.fingerprint.substring(0, 9),
                            style: TextStyle(color: jp.textFaint, fontSize: 11, fontFamily: kMono)),
                      ],
                    ),
                  ),
                  Icon(Icons.settings_outlined, size: 16, color: jp.textFaint),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: jp.accentGradient,
            boxShadow: [BoxShadow(color: jp.accent.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: -4)],
          ),
          child: const Icon(Icons.join_inner_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: S.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('JinjaPeer', style: context.tt.titleLarge?.copyWith(fontSize: 17)),
            Text('doğrudan · şifreli', style: TextStyle(color: jp.textFaint, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _SideNavTile extends StatefulWidget {
  const _SideNavTile({
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
    this.urgent = false,
  });

  final _NavItem item;
  final bool selected;
  final int badge;
  final bool urgent;
  final VoidCallback onTap;

  @override
  State<_SideNavTile> createState() => _SideNavTileState();
}

class _SideNavTileState extends State<_SideNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final sel = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Tooltip(
        message: widget.item.shortcut,
        waitDuration: const Duration(seconds: 1),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
                color: sel ? jp.accent.withValues(alpha: jp.isDark ? 0.16 : 0.12) : (_hover ? jp.glass : Colors.transparent),
                border: Border.all(color: sel ? jp.accent.withValues(alpha: 0.35) : Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(sel ? widget.item.activeIcon : widget.item.icon,
                      size: 19, color: sel ? jp.accent : (_hover ? jp.text : jp.textMuted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                        color: sel ? jp.text : jp.textMuted,
                      ),
                    ),
                  ),
                  AnimatedScale(
                    scale: widget.badge > 0 ? 1 : 0,
                    duration: Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: widget.urgent ? jp.danger : jp.glassStrong,
                      ),
                      child: Text(
                        '${widget.badge}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: widget.urgent ? Colors.white : jp.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedMeter extends StatelessWidget {
  const _SpeedMeter();

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final active = app.transfers.active;
    final up = active
        .where((b) => b.direction == TransferDirection.send)
        .fold(0.0, (a, b) => a + b.speed);
    final down = active
        .where((b) => b.direction == TransferDirection.receive)
        .fold(0.0, (a, b) => a + b.speed);
    return SmoothSize(
      duration: Duration(milliseconds: 240),
      child: active.isEmpty
          ? const SizedBox(width: double.infinity)
          : GlassTile(
              padding: const EdgeInsets.all(10),
              radius: R.md,
              onTap: () => app.page.value = AppPage.transfers,
              child: Row(
                children: [
                  PulseDot(color: jp.success, size: 7),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${active.length} aktarım sürüyor', style: TextStyle(fontSize: 12, color: jp.text)),
                        const SizedBox(height: 2),
                        Text('↑ ${formatSpeed(up)}   ↓ ${formatSpeed(down)}',
                            style: TextStyle(fontSize: 11, color: jp.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final items = _nav.where((n) => n.page != AppPage.settings && n.page != AppPage.contacts).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.md),
      child: Glass(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        radius: R.xl,
        child: SafeArea(
          top: false,
          child: ValueListenableBuilder<AppPage>(
            valueListenable: app.page,
            builder: (context, page, _) => Row(
              children: [
                for (final n in items)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => app.page.value = n.page,
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: page == n.page ? jp.accent.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Badge(
                              isLabelVisible: _badgeFor(app, n.page) > 0,
                              label: Text('${_badgeFor(app, n.page)}'),
                              child: Icon(page == n.page ? n.activeIcon : n.icon,
                                  size: 21, color: page == n.page ? jp.accent : jp.textMuted),
                            ),
                            const SizedBox(height: 3),
                            Text(n.label,
                                style: TextStyle(
                                    fontSize: 10.5, color: page == n.page ? jp.text : jp.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Common page frame: title row + content.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.scroll = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final pad = wide ? S.xl : S.lg;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad, hasCustomTitleBar ? S.xs : S.xl, pad, S.lg),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        runSpacing: S.md,
        spacing: S.md,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: context.tt.headlineMedium),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle!, style: TextStyle(color: jp.textMuted, fontSize: 13.5)),
                ),
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: S.sm, runSpacing: S.sm, children: actions),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: scroll
              ? SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, S.xl),
                  child: child,
                )
              : Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, S.lg), child: child),
        ),
      ],
    );
  }
}
