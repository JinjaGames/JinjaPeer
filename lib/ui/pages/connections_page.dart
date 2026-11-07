import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/peer_session.dart';
import '../../services/transfer_service.dart';
import '../connect/connect_flow.dart';
import '../send_helpers.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/transfer_widgets.dart';

class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return ValueListenableBuilder<String?>(
      valueListenable: app.selectedSession,
      builder: (context, selectedId, _) {
        var selected = app.sessionById(selectedId);
        if (selected == null && wide && app.sessions.isNotEmpty) {
          selected = app.liveSessions.firstOrNull ?? app.sessions.first;
        }
        if (app.sessions.isEmpty) {
          return PageFrame(
            title: 'Bağlantılar',
            subtitle: 'Aktif ve bekleyen eşler arası bağlantıların',
            child: Glass(
              shadow: false,
              child: EmptyState(
                icon: Icons.hub_rounded,
                title: 'Henüz bağlantı yok',
                message: 'Bir davet kodu oluştur ya da sana gönderilen koda katıl. '
                    'Bağlandığında dosyaları buradan gönderebilirsin.',
                action: Wrap(
                  spacing: S.sm,
                  runSpacing: S.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    JButton(label: 'Davet oluştur', icon: Icons.qr_code_2_rounded, onPressed: () => showConnectDialog(context)),
                    JButton(
                      label: 'Koda katıl',
                      icon: Icons.input_rounded,
                      kind: BtnKind.secondary,
                      onPressed: () => showConnectDialog(context, mode: ConnectMode.join),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!wide && selectedId != null && selected != null) {
          return PageFrame(
            title: selected.peerName.isEmpty ? 'Bekleyen bağlantı' : selected.displayName,
            actions: [
              JButton(
                label: 'Geri',
                icon: Icons.arrow_back_rounded,
                kind: BtnKind.secondary,
                dense: true,
                onPressed: () => app.selectedSession.value = null,
              ),
            ],
            child: _Detail(session: selected),
          );
        }
        return PageFrame(
          title: 'Bağlantılar',
          subtitle: '${app.liveSessions.length} aktif · ${app.pendingSessions.length} bekleyen',
          actions: [
            JButton(
              label: 'Yeni bağlantı',
              icon: Icons.add_rounded,
              onPressed: () => showConnectDialog(context),
            ),
          ],
          scroll: false,
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 300, child: _SessionList(selected: selected)),
                    const SizedBox(width: S.lg),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SmoothSwitcher(
                          duration: Duration(milliseconds: 220),
                          child: selected == null
                              ? const SizedBox.shrink()
                              : _Detail(key: ValueKey(selected.id), session: selected),
                        ),
                      ),
                    ),
                  ],
                )
              : _SessionList(selected: null),
        );
      },
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.selected});
  final PeerSession? selected;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final live = app.liveSessions;
    final pending = app.pendingSessions;
    final over = app.sessions.where((s) => s.state.isOver).toList();
    Widget group(String title, List<PeerSession> list, {Widget? trailing}) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, S.md, 4, S.sm),
            child: Row(
              children: [
                Text(title.toUpperCase(),
                    style: TextStyle(color: jp.textFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(bottom: S.sm),
              child: _SessionTile(session: s, selected: identical(s, selected)),
            ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        group('Bağlı', live),
        group('Bekleyen', pending),
        group('Sona erenler', over,
            trailing: JButton(
              label: 'Temizle',
              kind: BtnKind.ghost,
              dense: true,
              onPressed: () {
                for (final s in over) {
                  app.removeSession(s);
                }
              },
            )),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.selected});
  final PeerSession session;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final s = session;
    final c = app.contactFor(s);
    final hasPeer = s.peerName.isNotEmpty;
    final title = c?.name ?? (hasPeer ? s.displayName : (s.role == SessionRole.inviter ? 'Davetin' : 'Katılım'));
    final col = switch (s.state) {
      SessionState.connected => jp.success,
      SessionState.failed => jp.danger,
      SessionState.closed => jp.textFaint,
      _ => jp.warning,
    };
    return GlassTile(
      padding: const EdgeInsets.all(S.md),
      radius: R.md,
      selected: selected,
      onTap: () => app.selectedSession.value = s.id,
      child: Row(
        children: [
          hasPeer
              ? Avatar(name: title, seed: seedOf(s.peerKeyB64), size: 36, online: s.state.isLive)
              : IconOrb(s.role == SessionRole.inviter ? Icons.qr_code_2_rounded : Icons.input_rounded, size: 36),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        s.state.label + (s.state.isLive && s.rttMs != null ? ' · ${s.rttMs} ms' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: jp.textMuted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (c != null) Icon(Icons.verified_rounded, size: 16, color: jp.success),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({super.key, required this.session});
  final PeerSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s.connectedAt == null) {
      return _PendingDetail(session: s);
    }
    return _LiveDetail(session: s);
  }
}

class _PendingDetail extends StatelessWidget {
  const _PendingDetail({required this.session});
  final PeerSession session;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = session;
    return Glass(
      padding: const EdgeInsets.all(S.xl),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.role == SessionRole.inviter ? 'Davet bağlantısı' : 'Katılım bağlantısı',
                  style: context.tt.titleLarge,
                ),
              ),
              JButton(
                label: s.state.isOver ? 'Listeden kaldır' : 'Vazgeç',
                icon: s.state.isOver ? Icons.delete_outline_rounded : Icons.close_rounded,
                kind: BtnKind.ghost,
                dense: true,
                onPressed: () => app.removeSession(s),
              ),
            ],
          ),
          const SizedBox(height: S.lg),
          PendingSessionPanel(session: s),
        ],
      ),
    );
  }
}

class _LiveDetail extends StatefulWidget {
  const _LiveDetail({required this.session});
  final PeerSession session;

  @override
  State<_LiveDetail> createState() => _LiveDetailState();
}

class _LiveDetailState extends State<_LiveDetail> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _saveContact() async {
    final app = context.appRead;
    final name = await promptText(
      context,
      title: 'Kişilere ekle',
      label: 'Kişi adı',
      initial: widget.session.displayName,
      confirmLabel: 'Ekle',
      icon: Icons.person_add_alt_1_rounded,
    );
    if (name == null) return;
    await app.addContact(widget.session, name: name);
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final s = widget.session;
    final c = app.contactFor(s);
    final impostor = app.impostorWarning(s);
    final live = s.state.isLive;
    final batches = app.transfers.batchesFor(s);
    final name = c?.name ?? s.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: Glass(
            padding: const EdgeInsets.all(S.xl),
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Avatar(name: name, seed: seedOf(s.peerKeyB64), size: 56, online: live),
                    const SizedBox(width: S.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: context.tt.headlineSmall),
                          if (c != null && c.name != s.displayName)
                            Text('kendini "${s.displayName}" olarak tanıtıyor',
                                style: TextStyle(color: jp.textFaint, fontSize: 12)),
                          const SizedBox(height: S.sm),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (live)
                                Pill('Bağlı', icon: Icons.circle, color: jp.success, filled: true)
                              else
                                Pill(s.state.label, icon: Icons.link_off_rounded, color: jp.danger, filled: true),
                              if (c != null)
                                Pill('Kayıtlı kişi · kimlik doğrulandı', icon: Icons.verified_rounded, color: jp.success)
                              else
                                Pill('Yeni kişi', icon: Icons.person_outline_rounded, color: jp.warning),
                              Pill('Uçtan uca şifreli', icon: Icons.lock_rounded, color: jp.accent),
                              if (s.routeInfo != null) Pill(s.routeInfo!, icon: Icons.route_rounded),
                              if (live && s.rttMs != null) Pill('${s.rttMs} ms', icon: Icons.network_ping_rounded),
                              if (live && s.connectedAt != null)
                                Pill(formatDuration(DateTime.now().difference(s.connectedAt!)), icon: Icons.timer_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: S.md),
                    Wrap(
                      spacing: S.sm,
                      runSpacing: S.sm,
                      alignment: WrapAlignment.end,
                      children: [
                        if (c == null)
                          JButton(
                            label: 'Kişilere ekle',
                            icon: Icons.person_add_alt_1_rounded,
                            kind: BtnKind.secondary,
                            dense: true,
                            onPressed: _saveContact,
                          ),
                        if (live)
                          JButton(
                            label: 'Bağlantıyı kes',
                            icon: Icons.link_off_rounded,
                            kind: BtnKind.ghost,
                            dense: true,
                            onPressed: () async {
                              final busy = app.transfers.batchesFor(s).any((b) => !b.isFinished);
                              if (busy &&
                                  !await confirm(context,
                                      title: 'Bağlantı kesilsin mi?',
                                      message: 'Devam eden aktarımlar iptal olacak.',
                                      confirmLabel: 'Bağlantıyı kes',
                                      danger: true,
                                      icon: Icons.link_off_rounded)) {
                                return;
                              }
                              await app.closeSession(s);
                            },
                          )
                        else
                          JButton(
                            label: 'Listeden kaldır',
                            icon: Icons.delete_outline_rounded,
                            kind: BtnKind.ghost,
                            dense: true,
                            onPressed: () => app.removeSession(s),
                          ),
                      ],
                    ),
                  ],
                ),
                if (impostor != null) ...[
                  const SizedBox(height: S.lg),
                  _Warning(
                    text: 'Dikkat: "${impostor.name}" adında kayıtlı bir kişin var ama bu cihazın kimlik anahtarı '
                        'FARKLI. Bu kişi o olmayabilir. Emin değilsen doğrulama kodunu sesli olarak karşılaştır.',
                  ),
                ],
                const SizedBox(height: S.lg),
                _VerifyRow(code: s.verificationCode ?? '—', fingerprint: s.peerFingerprint ?? '', known: c != null),
              ],
            ),
          ),
        ),
        const SizedBox(height: S.lg),
        if (live)
          Reveal(
            index: 1,
            child: _SendZone(session: s),
          ),
        if (!live && s.error != null)
          Reveal(
            index: 1,
            child: Glass(
              shadow: false,
              tint: jp.danger,
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: jp.danger),
                  const SizedBox(width: S.md),
                  Expanded(child: Text(s.error!, style: TextStyle(color: jp.textMuted))),
                  const SizedBox(width: S.md),
                  JButton(
                    label: 'Yeniden bağlan',
                    icon: Icons.refresh_rounded,
                    dense: true,
                    onPressed: () => showConnectDialog(context),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: S.xl),
        SectionTitle(
          'Bu bağlantıdaki aktarımlar',
          subtitle: batches.isEmpty ? null : '${batches.length} istek',
        ),
        if (batches.isEmpty)
          Text('Henüz bir şey gönderilmedi ya da alınmadı.', style: TextStyle(color: jp.textFaint, fontSize: 13))
        else
          for (var i = 0; i < batches.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: batches[i].status == BatchStatus.pending && batches[i].direction == TransferDirection.receive
                  ? RequestCard(batch: batches[i])
                  : BatchCard(batch: batches[i], showPeer: false),
            ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Container(
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: jp.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: jp.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gpp_maybe_rounded, color: jp.danger, size: 20),
          const SizedBox(width: S.md),
          Expanded(child: Text(text, style: TextStyle(color: jp.text, fontSize: 12.5, height: 1.45))),
        ],
      ),
    );
  }
}

class _VerifyRow extends StatelessWidget {
  const _VerifyRow({required this.code, required this.fingerprint, required this.known});
  final String code;
  final String fingerprint;
  final bool known;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Container(
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: jp.isDark ? const Color(0x1A000000) : const Color(0x0A000000),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Wrap(
        spacing: S.xl,
        runSpacing: S.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: 'Kopyala',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Clipboard.setData(ClipboardData(text: code)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DOĞRULAMA KODU',
                      style: TextStyle(color: jp.textFaint, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  ShaderMask(
                    shaderCallback: (r) => jp.accentGradient.createShader(r),
                    child: Text(code,
                        style: const TextStyle(
                            fontFamily: kMono, fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)),
                  ),
                ],
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              known
                  ? 'Bu kişinin kimlik anahtarı kayıtlı olanla eşleşiyor. Ek doğrulama gerekmez.'
                  : 'Karşı tarafın ekranında da aynı kod görünmeli. Aynıysa aranıza kimse girmemiştir; '
                      'telefonda ya da yüz yüze karşılaştırmak en güvenlisidir.',
              style: TextStyle(color: jp.textMuted, fontSize: 12.5, height: 1.45),
            ),
          ),
          if (fingerprint.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KİMLİK PARMAK İZİ',
                    style: TextStyle(color: jp.textFaint, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(fingerprint, style: TextStyle(fontFamily: kMono, fontSize: 12.5, color: jp.textMuted)),
              ],
            ),
        ],
      ),
    );
  }
}

class _SendZone extends StatefulWidget {
  const _SendZone({required this.session});
  final PeerSession session;

  @override
  State<_SendZone> createState() => _SendZoneState();
}

class _SendZoneState extends State<_SendZone> {
  bool _busy = false;

  Future<void> _run(Future<List<dynamic>> Function() pick) async {
    setState(() => _busy = true);
    try {
      final sources = await pick();
      if (!mounted) return;
      await sendTo(context, widget.session, sources.cast());
    } catch (e) {
      if (mounted) context.appRead.notify('Seçilemedi', '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return CustomPaint(
      painter: _DashedBorder(color: jp.accent.withValues(alpha: 0.55), radius: R.xl),
      child: Glass(
        shadow: false,
        radius: R.xl,
        borderColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.xxl),
        child: Column(
          children: [
            const IconOrb(Icons.cloud_upload_rounded, size: 60),
            const SizedBox(height: S.md),
            Text('Dosyaları ya da klasörleri buraya sürükle', style: context.tt.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Her türlü dosya, her boyutta. Fotoğraf ve videolar sıkıştırılmadan, orijinal kalitede gider. '
              'Hız iki tarafın internet bağlantısına bağlıdır.',
              style: TextStyle(color: jp.textMuted, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: S.lg),
            Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              alignment: WrapAlignment.center,
              children: [
                JButton(
                  label: 'Dosya seç',
                  icon: Icons.attach_file_rounded,
                  loading: _busy,
                  onPressed: () => _run(pickFilesToSend),
                ),
                JButton(
                  label: 'Klasör seç',
                  icon: Icons.create_new_folder_outlined,
                  kind: BtnKind.secondary,
                  onPressed: _busy ? null : () => _run(pickFolderToSend),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect.deflate(0.75));
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 8), paint);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
