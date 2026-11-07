import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/app_controller.dart';
import '../../services/peer_session.dart';
import '../connect/connect_flow.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/glass.dart';
import '../widgets/transfer_widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final live = app.liveSessions;
    final pending = app.transfers.incomingPending;
    final recent = app.history.take(5).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return PageFrame(
      title: '${_greeting()}, ${app.settings.displayName}',
      subtitle: 'Dosyalarını sunucusuz, uçtan uca şifreli ve doğrudan gönder.',
      actions: [
        if (MediaQuery.sizeOf(context).width < 820) ...[
          JIconButton(icon: Icons.people_rounded, tooltip: 'Kişilerim', onPressed: () => app.page.value = AppPage.contacts),
          JIconButton(icon: Icons.tune_rounded, tooltip: 'Ayarlar', onPressed: () => app.page.value = AppPage.settings),
        ],
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending.isNotEmpty)
            Reveal(
              child: Padding(
                padding: const EdgeInsets.only(bottom: S.lg),
                child: GlassTile(
                  tint: jp.warning,
                  onTap: () => app.page.value = AppPage.requests,
                  child: Row(
                    children: [
                      IconOrb(Icons.inbox_rounded, colors: [jp.warning, jp.danger]),
                      const SizedBox(width: S.md),
                      Expanded(
                        child: Text(
                          '${pending.length} dosya isteği yanıtını bekliyor',
                          style: context.tt.titleSmall,
                        ),
                      ),
                      JButton(
                        label: 'İncele',
                        icon: Icons.arrow_forward_rounded,
                        dense: true,
                        onPressed: () => app.page.value = AppPage.requests,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          LayoutBuilder(builder: (context, c) {
            final twoCol = c.maxWidth > 640;
            final cards = [
              _ActionCard(
                index: 0,
                icon: Icons.qr_code_2_rounded,
                title: 'Davet oluştur',
                text: 'Bir kod üret, karşı tarafa gönder. Yanıt kodunu yapıştırınca bağlanırsınız.',
                hint: 'Ctrl + N',
                colors: [jp.accent, jp.accent2],
                onTap: () => showConnectDialog(context),
              ),
              _ActionCard(
                index: 1,
                icon: Icons.input_rounded,
                title: 'Koda katıl',
                text: 'Sana gönderilen davet kodunu yapıştır, oluşan yanıt kodunu geri gönder.',
                hint: 'Ctrl + J',
                colors: [jp.success, jp.accent],
                onTap: () => showConnectDialog(context, mode: ConnectMode.join),
              ),
            ];
            return twoCol
                ? Row(children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: S.lg),
                    Expanded(child: cards[1]),
                  ])
                : Column(children: [cards[0], const SizedBox(height: S.md), cards[1]]);
          }),
          const SizedBox(height: S.lg),
          Reveal(
            index: 2,
            child: LayoutBuilder(builder: (context, c) {
              final stats = [
                _Stat(Icons.hub_rounded, '${live.length}', 'Aktif bağlantı', jp.accent),
                _Stat(Icons.north_east_rounded, formatBytes(app.totalSent), 'Gönderilen', jp.accent2),
                _Stat(Icons.south_west_rounded, formatBytes(app.totalReceived), 'Alınan', jp.success),
                _Stat(Icons.people_rounded, '${app.contacts.length}', 'Kişi', jp.warning),
              ];
              final perRow = c.maxWidth > 700 ? 4 : 2;
              final w = (c.maxWidth - S.md * (perRow - 1)) / perRow;
              return Wrap(
                spacing: S.md,
                runSpacing: S.md,
                children: [for (final s in stats) SizedBox(width: w, child: s)],
              );
            }),
          ),
          const SizedBox(height: S.xl),
          Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: wide ? 3 : 0,
                fit: FlexFit.loose,
                child: Reveal(
                  index: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionTitle(
                        'Son aktarımlar',
                        trailing: recent.isEmpty
                            ? null
                            : JButton(
                                label: 'Tüm geçmiş',
                                kind: BtnKind.ghost,
                                dense: true,
                                onPressed: () => app.page.value = AppPage.history,
                              ),
                      ),
                      if (recent.isEmpty)
                        const Glass(
                          shadow: false,
                          child: EmptyState(
                            compact: true,
                            icon: Icons.history_toggle_off_rounded,
                            title: 'Henüz aktarım yok',
                            message: 'Bir bağlantı kurup dosya gönderdiğinde ya da aldığında burada görünecek.',
                          ),
                        )
                      else
                        for (final r in recent)
                          Padding(padding: const EdgeInsets.only(bottom: S.sm), child: RecordTile(record: r)),
                    ],
                  ),
                ),
              ),
              SizedBox(width: wide ? S.xl : 0, height: wide ? 0 : S.xl),
              Flexible(
                flex: wide ? 2 : 0,
                fit: FlexFit.loose,
                child: Reveal(
                  index: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionTitle('Bağlı kişiler'),
                      if (live.isEmpty)
                        Glass(
                          shadow: false,
                          child: Row(
                            children: [
                              Icon(Icons.link_off_rounded, color: jp.textFaint),
                              const SizedBox(width: S.md),
                              Expanded(
                                child: Text('Şu an kimseyle bağlı değilsin.',
                                    style: TextStyle(color: jp.textMuted, fontSize: 13)),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final s in live) _LivePeerTile(session: s),
                      const SizedBox(height: S.xl),
                      const _SecurityCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.text,
    required this.hint,
    required this.colors,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final String title;
  final String text;
  final String hint;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Reveal(
      index: index,
      child: GlassTile(
        padding: const EdgeInsets.all(S.xl),
        radius: R.xl,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.4), blurRadius: 22, spreadRadius: -6)],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: S.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: context.tt.titleLarge),
                      const Spacer(),
                      Text(hint, style: TextStyle(color: jp.textFaint, fontSize: 11, fontFamily: kMono)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(color: jp.textMuted, fontSize: 13, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label, this.color);
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Glass(
      shadow: false,
      padding: const EdgeInsets.all(S.lg),
      child: Row(
        children: [
          IconOrb(icon, size: 38, colors: [color, color]),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: context.tt.titleLarge?.copyWith(fontSize: 19)),
                ),
                Text(label, style: TextStyle(color: jp.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePeerTile extends StatelessWidget {
  const _LivePeerTile({required this.session});
  final PeerSession session;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final c = app.contactFor(session);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: GlassTile(
        padding: const EdgeInsets.all(S.md),
        radius: R.md,
        onTap: () {
          app.selectedSession.value = session.id;
          app.page.value = AppPage.connections;
        },
        child: Row(
          children: [
            Avatar(name: c?.name ?? session.displayName, seed: seedOf(session.peerKeyB64), size: 36, online: true),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c?.name ?? session.displayName, style: context.tt.titleSmall),
                  Text(
                    [session.routeInfo ?? 'Doğrudan', if (session.rttMs != null) '${session.rttMs} ms'].join(' · '),
                    style: TextStyle(color: jp.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.send_rounded, size: 17, color: jp.accent),
          ],
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    Widget row(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, size: 16, color: jp.success),
              const SizedBox(width: S.sm),
              Expanded(child: Text(t, style: TextStyle(color: jp.textMuted, fontSize: 12.5, height: 1.4))),
            ],
          ),
        );
    return Glass(
      shadow: false,
      tint: jp.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: jp.success, size: 20),
              const SizedBox(width: S.sm),
              Text('Nasıl güvende kalıyorsun?', style: context.tt.titleSmall),
            ],
          ),
          const SizedBox(height: S.md),
          row(Icons.dns_outlined, 'Dosyaların hiçbir sunucudan geçmez; iki cihaz doğrudan konuşur.'),
          row(Icons.lock_outline_rounded, 'Çift katman şifreleme: WebRTC DTLS + ChaCha20-Poly1305 (her bağlantıda yeni anahtar).'),
          row(Icons.draw_outlined, 'Kodlar Ed25519 ile imzalanır; değiştirilmiş kod reddedilir.'),
          row(Icons.fact_check_outlined, 'Her dosya SHA-256 ile doğrulanır, sen onaylamadan hiçbir şey yazılmaz.'),
          row(Icons.do_not_touch_outlined, 'Gelen dosyalar asla otomatik açılmaz ya da çalıştırılmaz.'),
        ],
      ),
    );
  }
}
