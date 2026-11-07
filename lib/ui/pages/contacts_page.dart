import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../connect/connect_flow.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final q = _q.text.trim().toLowerCase();
    final list = app.contacts.where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });

    return PageFrame(
      title: 'Kişilerim',
      subtitle: 'Kaydettiğin kişiler sonraki bağlantılarda kimlik anahtarıyla otomatik doğrulanır.',
      actions: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Kişi ara…',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
              isDense: true,
            ),
          ),
        ),
      ],
      child: app.contacts.isEmpty
          ? const Glass(
              shadow: false,
              child: EmptyState(
                icon: Icons.people_alt_rounded,
                title: 'Henüz kişi yok',
                message: 'Biriyle bağlandıktan sonra bağlantı ekranındaki "Kişilere ekle" düğmesiyle kaydedebilirsin. '
                    'Kayıtlı kişiler bir dahaki sefere tanınır ve başkası onun adını kullanamaz.',
              ),
            )
          : LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 1100 ? 3 : (c.maxWidth > 680 ? 2 : 1);
              final w = (c.maxWidth - S.lg * (cols - 1)) / cols;
              return Wrap(
                spacing: S.lg,
                runSpacing: S.lg,
                children: [
                  for (var i = 0; i < list.length; i++)
                    SizedBox(width: w, child: Reveal(index: i, child: _ContactCard(contact: list[i]))),
                ],
              );
            }),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final c = contact;
    final live = app.liveSessions.where((s) => s.peerKeyB64 == c.identityKey).firstOrNull;

    return Glass(
      shadow: false,
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: c.name, seed: c.colorSeed, size: 46, online: live != null),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleMedium),
                        ),
                        if (c.trusted) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Güvenilir kişi',
                            child: Icon(Icons.verified_user_rounded, size: 16, color: jp.success),
                          ),
                        ],
                      ],
                    ),
                    Text(live != null ? 'Şu an bağlı' : 'Son görülme: ${formatRelative(c.lastSeen)}',
                        style: TextStyle(color: live != null ? jp.success : jp.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              JIconButton(
                icon: c.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                tooltip: c.favorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
                color: c.favorite ? jp.warning : null,
                onPressed: () => app.updateContact(c, (x) => x.favorite = !x.favorite),
              ),
              PopupMenuButton<String>(
                tooltip: 'Diğer',
                icon: Icon(Icons.more_vert_rounded, size: 18, color: jp.textMuted),
                onSelected: (v) async {
                  switch (v) {
                    case 'rename':
                      final name = await promptText(context, title: 'Kişiyi yeniden adlandır', label: 'Ad', initial: c.name);
                      if (name != null) app.updateContact(c, (x) => x.name = name);
                    case 'fp':
                      await Clipboard.setData(ClipboardData(text: c.fingerprint));
                      app.notify('Kopyalandı', 'Kimlik parmak izi panoya kopyalandı.');
                    case 'delete':
                      if (context.mounted &&
                          await confirm(context,
                              title: '${c.name} silinsin mi?',
                              message: 'Kişi listeden kaldırılır. Geçmişteki aktarım kayıtları kalır.',
                              confirmLabel: 'Sil',
                              danger: true,
                              icon: Icons.person_remove_rounded)) {
                        app.removeContact(c);
                      }
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Yeniden adlandır')),
                  PopupMenuItem(value: 'fp', child: Text('Parmak izini kopyala')),
                  PopupMenuItem(value: 'delete', child: Text('Kişiyi sil')),
                ],
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Text(c.fingerprint, style: TextStyle(fontFamily: kMono, fontSize: 11.5, color: jp.textFaint)),
          const SizedBox(height: S.md),
          Row(
            children: [
              _MiniStat(icon: Icons.north_east_rounded, value: formatBytes(c.sentBytes), label: 'gönderilen'),
              _MiniStat(icon: Icons.south_west_rounded, value: formatBytes(c.receivedBytes), label: 'alınan'),
              _MiniStat(icon: Icons.insert_drive_file_outlined, value: '${c.fileCount}', label: 'dosya'),
            ],
          ),
          const SizedBox(height: S.md),
          const Divider(),
          const SizedBox(height: S.sm),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'Açıkken ve Ayarlar\'da otomatik kabul etkinse bu kişinin dosyaları onay beklemeden indirilir.',
                  child: Row(
                    children: [
                      SizedBox(
                        height: 24,
                        child: FittedBox(
                          child: Switch(
                            value: c.trusted,
                            onChanged: (v) => app.updateContact(c, (x) => x.trusted = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Güvenilir', style: TextStyle(color: jp.textMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
              if (live != null)
                JButton(
                  label: 'Dosya gönder',
                  icon: Icons.send_rounded,
                  dense: true,
                  onPressed: () {
                    app.selectedSession.value = live.id;
                    app.page.value = AppPage.connections;
                  },
                )
              else
                JButton(
                  label: 'Bağlan',
                  icon: Icons.link_rounded,
                  kind: BtnKind.secondary,
                  dense: true,
                  tooltip: 'Yeni davet kodu oluştur ve ${c.name} kişisine gönder',
                  onPressed: () => showConnectDialog(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: jp.textFaint),
          const SizedBox(width: 4),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: value, style: TextStyle(color: jp.text, fontSize: 12, fontWeight: FontWeight.w600)),
                TextSpan(text: ' $label', style: TextStyle(color: jp.textFaint, fontSize: 11)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
