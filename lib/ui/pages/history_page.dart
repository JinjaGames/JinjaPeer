import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';
import '../widgets/transfer_widgets.dart';

enum _Filter { all, sent, received, failed }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _q = TextEditingController();
  _Filter _filter = _Filter.all;
  int _limit = 150;

  bool _match(TransferRecord r) {
    switch (_filter) {
      case _Filter.sent:
        if (r.direction != TransferDirection.send) return false;
      case _Filter.received:
        if (r.direction != TransferDirection.receive) return false;
      case _Filter.failed:
        if (r.status == RecordStatus.completed) return false;
      case _Filter.all:
    }
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.fileName.toLowerCase().contains(q) || r.peerName.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final all = app.history;
    final filtered = all.where(_match).toList();
    final shown = filtered.take(_limit).toList();

    final groups = <String, List<TransferRecord>>{};
    for (final r in shown) {
      groups.putIfAbsent(dayGroupLabel(r.finishedAt), () => []).add(r);
    }

    return PageFrame(
      title: 'Geçmiş',
      subtitle: '${all.length} kayıt · yalnızca bu cihazda saklanır',
      actions: [
        if (all.isNotEmpty)
          JButton(
            label: 'Geçmişi temizle',
            icon: Icons.delete_sweep_outlined,
            kind: BtnKind.ghost,
            onPressed: () async {
              if (await confirm(context,
                  title: 'Geçmiş temizlensin mi?',
                  message: 'Tüm aktarım kayıtları silinir. Diskteki dosyalara dokunulmaz.',
                  confirmLabel: 'Temizle',
                  danger: true,
                  icon: Icons.delete_sweep_rounded)) {
                app.clearHistory();
              }
            },
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: S.md,
            runSpacing: S.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() => _limit = 150),
                  decoration: InputDecoration(
                    hintText: 'Dosya ya da kişi ara…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Temizle',
                            icon: const Icon(Icons.close_rounded, size: 17),
                            onPressed: () => setState(_q.clear),
                          ),
                    isDense: true,
                  ),
                ),
              ),
              Segmented<_Filter>(
                value: _filter,
                items: const [
                  (_Filter.all, 'Tümü', null),
                  (_Filter.sent, 'Gönderilen', Icons.north_east_rounded),
                  (_Filter.received, 'Alınan', Icons.south_west_rounded),
                  (_Filter.failed, 'Sorunlu', Icons.error_outline_rounded),
                ],
                onChanged: (f) => setState(() {
                  _filter = f;
                  _limit = 150;
                }),
              ),
            ],
          ),
          const SizedBox(height: S.lg),
          if (filtered.isEmpty)
            Glass(
              shadow: false,
              child: EmptyState(
                icon: all.isEmpty ? Icons.history_rounded : Icons.search_off_rounded,
                title: all.isEmpty ? 'Geçmiş boş' : 'Sonuç bulunamadı',
                message: all.isEmpty
                    ? 'Tamamlanan, iptal edilen ya da başarısız olan her aktarım burada listelenir.'
                    : 'Aramayı ya da filtreyi değiştirmeyi dene.',
              ),
            )
          else
            for (final e in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, S.sm, 4, S.sm),
                child: Text(e.key.toUpperCase(),
                    style: TextStyle(color: jp.textFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ),
              for (final r in e.value)
                Padding(padding: const EdgeInsets.only(bottom: S.sm), child: RecordTile(key: ValueKey(r.id + r.finishedAt.toString()), record: r)),
            ],
          if (filtered.length > shown.length)
            Center(
              child: JButton(
                label: 'Daha fazla göster (${filtered.length - shown.length})',
                kind: BtnKind.secondary,
                onPressed: () => setState(() => _limit += 150),
              ),
            ),
        ],
      ),
    );
  }
}
