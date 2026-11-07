import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/peer_session.dart';
import '../../services/platform_actions.dart';
import '../../services/transfer_service.dart';
import '../theme.dart';
import 'chrome.dart';
import 'glass.dart';
import 'liquid_background.dart';

Color statusColor(JP jp, TaskStatus s) => switch (s) {
      TaskStatus.done => jp.success,
      TaskStatus.failed => jp.danger,
      TaskStatus.canceled => jp.textFaint,
      TaskStatus.paused => jp.warning,
      TaskStatus.verifying => jp.accent2,
      _ => jp.accent,
    };

Future<void> revealOrWarn(BuildContext context, String? path) async {
  final app = context.appRead;
  if (path == null || !await showInFolder(path)) {
    app.notify('Konum açılamadı', 'Dosya taşınmış ya da silinmiş olabilir.', error: true);
  }
}

Future<void> openOrWarn(BuildContext context, String? path) async {
  final app = context.appRead;
  if (path == null || !await openFile(path)) {
    app.notify('Dosya açılamadı', 'Dosya taşınmış ya da silinmiş olabilir.', error: true);
  }
}

/// Live batch (send or receive) with progress and controls.
class BatchCard extends StatefulWidget {
  const BatchCard({super.key, required this.batch, this.showPeer = true});
  final TransferBatch batch;
  final bool showPeer;

  @override
  State<BatchCard> createState() => _BatchCardState();
}

class _BatchCardState extends State<BatchCard> {
  bool _expanded = false;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final b = widget.batch;
    final sending = b.direction == TransferDirection.send;
    final total = b.totalSize;
    final done = b.transferred;
    final speed = b.speed;
    final running = b.status == BatchStatus.accepted;
    final (statusText, statusCol) = switch (b.status) {
      BatchStatus.pending => (sending ? 'Onay bekleniyor' : 'Yanıtını bekliyor', jp.warning),
      BatchStatus.accepted => (b.paused ? (b.pausedByPeer ? 'Karşı taraf duraklattı' : 'Duraklatıldı') : (sending ? 'Gönderiliyor' : 'Alınıyor'),
          b.paused ? jp.warning : jp.accent),
      BatchStatus.done => (b.reason ?? 'Tamamlandı', b.reason == null ? jp.success : jp.warning),
      BatchStatus.rejected => ('Reddedildi', jp.danger),
      BatchStatus.canceled => ('İptal edildi', jp.textFaint),
      BatchStatus.failed => (b.reason ?? 'Başarısız', jp.danger),
    };
    final tasks = _showAll ? b.tasks : b.tasks.take(8).toList();

    return Glass(
      padding: const EdgeInsets.all(S.lg),
      radius: R.lg,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconOrb(
                sending ? Icons.north_east_rounded : Icons.south_west_rounded,
                size: 40,
                colors: sending ? [jp.accent, jp.accent2] : [jp.success, jp.accent],
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (widget.showPeer) (sending ? '→ ${b.peerName}' : '← ${b.peerName}'),
                        '${b.tasks.length} dosya',
                        formatBytes(total),
                        if (b.autoAccepted) 'otomatik kabul',
                      ].join('  ·  '),
                      style: TextStyle(color: jp.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Pill(statusText, color: statusCol, filled: true),
              const SizedBox(width: S.sm),
              if (running)
                JIconButton(
                  icon: b.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  tooltip: b.paused ? 'Devam et' : 'Duraklat',
                  onPressed: () => app.transfers.setPaused(b, !b.paused),
                ),
              if (!b.isFinished)
                JIconButton(
                  icon: Icons.close_rounded,
                  tooltip: b.status == BatchStatus.pending && !sending ? 'Reddet' : 'Tümünü iptal et',
                  onPressed: () => app.transfers.cancelBatch(b),
                ),
              if (!sending && b.destination != null && (b.status == BatchStatus.done || running))
                JIconButton(
                  icon: Icons.folder_open_rounded,
                  tooltip: 'Klasörü aç',
                  onPressed: () => openFolder(b.destination!),
                ),
              JIconButton(
                icon: _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                tooltip: _expanded ? 'Dosyaları gizle' : 'Dosyaları göster',
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
          if (b.status != BatchStatus.pending && b.status != BatchStatus.rejected) ...[
            const SizedBox(height: S.md),
            LiquidProgress(
              value: b.progress,
              paused: b.paused,
              color: b.status == BatchStatus.done ? jp.success : (b.status == BatchStatus.failed ? jp.danger : null),
            ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text('${formatBytes(done)} / ${formatBytes(total)}',
                    style: TextStyle(color: jp.textMuted, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
                const Spacer(),
                if (running && !b.paused) ...[
                  Icon(Icons.speed_rounded, size: 14, color: jp.textFaint),
                  const SizedBox(width: 4),
                  Text(formatSpeed(speed), style: TextStyle(color: jp.text, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: S.md),
                  Icon(Icons.schedule_rounded, size: 14, color: jp.textFaint),
                  const SizedBox(width: 4),
                  Text(formatEta(total - done, speed), style: TextStyle(color: jp.textMuted, fontSize: 12)),
                ] else
                  Text('${b.doneCount}/${b.tasks.length} dosya', style: TextStyle(color: jp.textMuted, fontSize: 12)),
              ],
            ),
          ],
          SmoothSize(
            duration: Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: S.md),
                    child: Column(
                      children: [
                        const Divider(),
                        const SizedBox(height: S.xs),
                        for (final t in tasks) TaskRow(task: t),
                        if (b.tasks.length > tasks.length)
                          JButton(
                            label: '${b.tasks.length - tasks.length} dosya daha göster',
                            kind: BtnKind.ghost,
                            dense: true,
                            onPressed: () => setState(() => _showAll = true),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({super.key, required this.task});
  final FileTask task;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final t = task;
    final col = statusColor(jp, t.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(fileIcon(t.name), size: 18, color: fileColor(t.name)),
          const SizedBox(width: S.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        t.relDir.isEmpty ? t.name : '${t.relDir}/${t.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    if (t.risky) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Çalıştırılabilir dosya: güvendiğin kişiden gelmiyorsa açma.',
                        child: Icon(Icons.warning_amber_rounded, size: 14, color: jp.warning),
                      ),
                    ],
                  ],
                ),
                if (t.status == TaskStatus.active || t.status == TaskStatus.paused) ...[
                  const SizedBox(height: 4),
                  LiquidProgress(value: t.progress, height: 4, paused: t.status == TaskStatus.paused),
                ] else if (t.error != null && t.status != TaskStatus.done)
                  Text(t.error!, style: TextStyle(color: col, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: S.sm),
          SizedBox(
            width: 72,
            child: Text(formatBytes(t.size),
                textAlign: TextAlign.right, style: TextStyle(color: jp.textFaint, fontSize: 11.5)),
          ),
          const SizedBox(width: S.sm),
          SizedBox(
            width: 92,
            child: Text(t.status.label,
                textAlign: TextAlign.right,
                style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (t.status == TaskStatus.done && t.path != null) ...[
                  if (t.direction == TransferDirection.receive)
                    JIconButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: 'Aç',
                      size: 28,
                      onPressed: () => openOrWarn(context, t.path),
                    ),
                  JIconButton(
                    icon: Icons.folder_outlined,
                    tooltip: 'Klasörde göster',
                    size: 28,
                    onPressed: () => revealOrWarn(context, t.path),
                  ),
                ] else if (!t.status.isFinal && t.batch.status == BatchStatus.accepted)
                  JIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Bu dosyayı iptal et',
                    size: 28,
                    onPressed: () => context.appRead.transfers.cancelTask(t),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Incoming request card with accept / reject.
class RequestCard extends StatefulWidget {
  const RequestCard({super.key, required this.batch});
  final TransferBatch batch;

  @override
  State<RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<RequestCard> {
  bool _busy = false;
  bool _all = false;

  Future<void> _accept({bool choose = false}) async {
    final app = context.appRead;
    var dest = app.downloadDir;
    if (choose || app.settings.askWhereToSave) {
      final picked = await FilePicker.getDirectoryPath(dialogTitle: 'Dosyalar nereye kaydedilsin?', initialDirectory: dest);
      if (picked == null) return;
      dest = picked;
    }
    setState(() => _busy = true);
    await app.transfers.accept(widget.batch, dest);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final b = widget.batch;
    final contact = app.contactByKey(b.peerKey);
    final shown = _all ? b.tasks : b.tasks.take(5).toList();
    final risky = b.tasks.where((t) => t.risky).length;
    return Glass(
      radius: R.lg,
      shadow: false,
      tint: jp.accent,
      borderColor: jp.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: contact?.name ?? b.peerName, seed: seedOf(b.peerKey), size: 42, online: b.session.state.isLive),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: contact?.name ?? b.peerName, style: context.tt.titleSmall),
                      TextSpan(
                        text: ' sana ${b.tasks.length} dosya göndermek istiyor',
                        style: TextStyle(color: jp.textMuted, fontSize: 13.5),
                      ),
                    ])),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(formatBytes(b.totalSize), icon: Icons.data_usage_rounded),
                        Pill(formatRelative(b.createdAt), icon: Icons.schedule_rounded),
                        if (contact != null)
                          Pill('Kayıtlı kişi', icon: Icons.verified_user_rounded, color: jp.success)
                        else
                          Pill('Kayıtlı değil', icon: Icons.person_outline_rounded, color: jp.warning),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
            decoration: BoxDecoration(
              color: jp.isDark ? const Color(0x22000000) : const Color(0x0A000000),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Column(
              children: [
                for (final t in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(fileIcon(t.name), size: 17, color: fileColor(t.name)),
                        const SizedBox(width: S.sm),
                        Expanded(
                          child: Text(t.relDir.isEmpty ? t.name : '${t.relDir}/${t.name}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                        ),
                        if (t.risky)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.warning_amber_rounded, size: 15, color: jp.warning),
                          ),
                        Text(formatBytes(t.size), style: TextStyle(color: jp.textFaint, fontSize: 11.5)),
                      ],
                    ),
                  ),
                if (b.tasks.length > shown.length)
                  JButton(
                    label: '+${b.tasks.length - shown.length} dosya daha',
                    kind: BtnKind.ghost,
                    dense: true,
                    onPressed: () => setState(() => _all = true),
                  ),
              ],
            ),
          ),
          if (risky > 0) ...[
            const SizedBox(height: S.md),
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: jp.warning),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text(
                    '$risky çalıştırılabilir/komut dosyası var. JinjaPeer dosyaları asla otomatik açmaz; '
                    'tanımadığın birinden geliyorsa çalıştırma.',
                    style: TextStyle(color: jp.warning, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: S.lg),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: S.sm,
            runSpacing: S.sm,
            children: [
              JButton(
                label: 'Reddet',
                icon: Icons.block_rounded,
                kind: BtnKind.ghost,
                onPressed: _busy ? null : () => app.transfers.reject(b),
              ),
              JButton(
                label: 'Farklı klasöre kaydet',
                icon: Icons.drive_folder_upload_rounded,
                kind: BtnKind.secondary,
                onPressed: _busy ? null : () => _accept(choose: true),
              ),
              JButton(
                label: 'Kabul et',
                icon: Icons.download_rounded,
                loading: _busy,
                onPressed: () => _accept(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row in history / sent / received lists.
class RecordTile extends StatelessWidget {
  const RecordTile({super.key, required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final r = record;
    final sending = r.direction == TransferDirection.send;
    final (label, col) = switch (r.status) {
      RecordStatus.completed => (sending ? 'Gönderildi' : 'Alındı', jp.success),
      RecordStatus.failed => ('Başarısız', jp.danger),
      RecordStatus.canceled => ('İptal', jp.textFaint),
      RecordStatus.rejected => ('Reddedildi', jp.warning),
    };
    final name = r.fileName.split('/').last;
    return GlassTile(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 10),
      radius: R.md,
      onTap: r.status == RecordStatus.completed && r.path != null
          ? () => sending ? revealOrWarn(context, r.path) : openOrWarn(context, r.path)
          : null,
      tooltip: r.error,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconOrb(fileIcon(name), size: 38, colors: [fileColor(name), fileColor(name)]),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sending ? jp.accent : jp.success,
                    border: Border.all(color: jp.bgTop, width: 2),
                  ),
                  child: Icon(sending ? Icons.north_east_rounded : Icons.south_west_rounded, size: 10, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                const SizedBox(height: 2),
                Text(
                  [
                    sending ? '→ ${r.peerName}' : '← ${r.peerName}',
                    formatBytes(r.size),
                    formatRelative(r.finishedAt),
                    if (r.status == RecordStatus.completed && r.averageSpeed > 0) 'ort. ${formatSpeed(r.averageSpeed)}',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: jp.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: S.sm),
          Pill(label, color: col),
          const SizedBox(width: S.xs),
          if (r.status == RecordStatus.completed && r.path != null) ...[
            if (!sending)
              JIconButton(icon: Icons.open_in_new_rounded, tooltip: 'Aç', size: 30, onPressed: () => openOrWarn(context, r.path)),
            JIconButton(
              icon: Icons.folder_outlined,
              tooltip: 'Klasörde göster',
              size: 30,
              onPressed: () => revealOrWarn(context, r.path),
            ),
          ],
          PopupMenuButton<String>(
            tooltip: 'Diğer',
            icon: Icon(Icons.more_horiz_rounded, size: 18, color: jp.textMuted),
            onSelected: (v) {
              final app = context.appRead;
              switch (v) {
                case 'hash':
                  Clipboard.setData(ClipboardData(text: r.sha256 ?? ''));
                  app.notify('Kopyalandı', 'SHA-256 özeti panoya kopyalandı.');
                case 'path':
                  Clipboard.setData(ClipboardData(text: r.path ?? ''));
                  app.notify('Kopyalandı', 'Dosya yolu panoya kopyalandı.');
                case 'remove':
                  app.removeRecord(r);
              }
            },
            itemBuilder: (context) => [
              if (r.sha256 != null)
                const PopupMenuItem(value: 'hash', child: Text('SHA-256 özetini kopyala')),
              if (r.path != null) const PopupMenuItem(value: 'path', child: Text('Dosya yolunu kopyala')),
              const PopupMenuItem(value: 'remove', child: Text('Geçmişten kaldır')),
            ],
          ),
        ],
      ),
    );
  }
}
