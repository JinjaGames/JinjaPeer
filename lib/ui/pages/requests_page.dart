import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/glass.dart';
import '../widgets/transfer_widgets.dart';

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final incoming = app.transfers.incomingPending;
    final outgoing = app.transfers.outgoingPending;

    return PageFrame(
      title: 'İstekler',
      subtitle: 'Sen onaylamadan hiçbir dosya cihazına yazılmaz.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle('Gelen istekler', subtitle: incoming.isEmpty ? null : '${incoming.length} istek yanıt bekliyor'),
          if (incoming.isEmpty)
            const Glass(
              shadow: false,
              child: EmptyState(
                compact: true,
                icon: Icons.mark_email_read_outlined,
                title: 'Bekleyen istek yok',
                message: 'Biri sana dosya göndermek istediğinde burada onayına sunulur.',
              ),
            )
          else
            for (var i = 0; i < incoming.length; i++)
              Reveal(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: S.md),
                  child: RequestCard(key: ValueKey(incoming[i].reqId), batch: incoming[i]),
                ),
              ),
          const SizedBox(height: S.xl),
          SectionTitle('Gönderdiğin istekler', subtitle: 'Karşı tarafın onayını bekleyenler'),
          if (outgoing.isEmpty)
            Text('Onay bekleyen bir gönderimin yok.', style: TextStyle(color: jp.textFaint, fontSize: 13))
          else
            for (final b in outgoing)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Glass(
                  shadow: false,
                  padding: const EdgeInsets.all(S.md),
                  radius: R.md,
                  child: Row(
                    children: [
                      PulseDot(color: jp.warning),
                      const SizedBox(width: S.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                            Text('→ ${b.peerName} · ${formatBytes(b.totalSize)} · ${formatRelative(b.createdAt)}',
                                style: TextStyle(color: jp.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      JButton(
                        label: 'Geri çek',
                        icon: Icons.undo_rounded,
                        kind: BtnKind.ghost,
                        dense: true,
                        onPressed: () => app.transfers.cancelBatch(b),
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
