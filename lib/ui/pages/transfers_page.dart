import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/transfer_service.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/glass.dart';
import '../widgets/transfer_widgets.dart';

enum _Tab { active, sent, received }

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  _Tab _tab = _Tab.active;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final live = app.transfers.batches.where((b) => b.status != BatchStatus.pending || b.direction == TransferDirection.send).toList();
    final running = live.where((b) => !b.isFinished).toList();
    final finished = live.where((b) => b.isFinished).toList();
    final sent = app.history.where((r) => r.direction == TransferDirection.send).toList();
    final received = app.history.where((r) => r.direction == TransferDirection.receive).toList();

    Widget body;
    switch (_tab) {
      case _Tab.active:
        body = live.isEmpty
            ? const Glass(
                shadow: false,
                child: EmptyState(
                  icon: Icons.swap_vert_circle_rounded,
                  title: 'Şu an aktarım yok',
                  message: 'Bir bağlantı üzerinden dosya gönderdiğinde ya da kabul ettiğinde ilerlemesi burada görünür.',
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (running.isNotEmpty) ...[
                    SectionTitle('Devam edenler', subtitle: 'Toplam hız ${formatSpeed(app.transfers.totalSpeed)}'),
                    for (var i = 0; i < running.length; i++)
                      Reveal(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: S.md),
                          child: BatchCard(batch: running[i]),
                        ),
                      ),
                    const SizedBox(height: S.lg),
                  ],
                  if (finished.isNotEmpty) ...[
                    SectionTitle(
                      'Bu oturumda bitenler',
                      trailing: JButton(
                        label: 'Listeyi temizle',
                        icon: Icons.clear_all_rounded,
                        kind: BtnKind.ghost,
                        dense: true,
                        onPressed: app.transfers.clearFinished,
                      ),
                    ),
                    for (final b in finished)
                      Padding(padding: const EdgeInsets.only(bottom: S.md), child: BatchCard(batch: b)),
                  ],
                ],
              );
      case _Tab.sent:
        body = _RecordList(records: sent, emptyText: 'Henüz kimseye dosya göndermedin.');
      case _Tab.received:
        body = _RecordList(records: received, emptyText: 'Henüz kimseden dosya almadın.');
    }

    return PageFrame(
      title: 'Aktarımlar',
      subtitle: running.isEmpty
          ? 'Gönderdiklerin ve aldıkların'
          : '${running.length} aktarım sürüyor · ${formatSpeed(app.transfers.totalSpeed)}',
      actions: [
        Segmented<_Tab>(
          value: _tab,
          items: [
            (_Tab.active, 'Aktif${running.isEmpty ? '' : ' (${running.length})'}', Icons.bolt_rounded),
            (_Tab.sent, 'Aktardıklarım', Icons.north_east_rounded),
            (_Tab.received, 'Aldıklarım', Icons.south_west_rounded),
          ],
          onChanged: (t) => setState(() => _tab = t),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tab != _Tab.active)
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: Text(
                _tab == _Tab.sent
                    ? '${sent.where((r) => r.status == RecordStatus.completed).length} dosya · ${formatBytes(app.totalSent)} gönderildi'
                    : '${received.where((r) => r.status == RecordStatus.completed).length} dosya · ${formatBytes(app.totalReceived)} alındı',
                style: TextStyle(color: jp.textMuted, fontSize: 12.5),
              ),
            ),
          body,
        ],
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records, required this.emptyText});
  final List<TransferRecord> records;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Glass(
        shadow: false,
        child: EmptyState(icon: Icons.inventory_2_outlined, title: 'Liste boş', message: emptyText),
      );
    }
    final shown = records.take(300).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++)
          Reveal(
            index: i,
            child: Padding(padding: const EdgeInsets.only(bottom: S.sm), child: RecordTile(record: shown[i])),
          ),
      ],
    );
  }
}
