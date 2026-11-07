import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/platform_actions.dart';
import '../../services/scanner.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _name = TextEditingController(text: context.appRead.settings.displayName);
  late final _ice = TextEditingController(text: context.appRead.settings.iceServers.join('\n'));
  late final _turnUrl = TextEditingController(text: context.appRead.settings.turnUrl);
  late final _turnUser = TextEditingController(text: context.appRead.settings.turnUser);
  late final _turnPass = TextEditingController(text: context.appRead.settings.turnPass);
  late final _vt = TextEditingController(text: context.appRead.settings.virusTotalKey);
  bool _testing = false;

  /// Scans the harmless EICAR test file to prove the scanner works.
  Future<void> _testScan() async {
    final app = context.appRead;
    setState(() => _testing = true);
    String title, body;
    try {
      final dir = await Directory.systemTemp.createTemp('jp_tarama');
      final f = File('${dir.path}${Platform.pathSeparator}eicar_test.txt');
      await f.writeAsString(eicarTestString());
      final r = await app.scanner.scanFile(f.path, displayName: 'eicar_test.txt', sha256: '');
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      if (r == null) {
        title = 'Tarama kapalı';
        body = 'Önce "Gelen her dosyayı tara" seçeneğini aç.';
      } else if (r.isThreat) {
        title = 'Tarayıcı çalışıyor';
        body = 'Test dosyası doğru şekilde yakalandı: ${r.summary}';
      } else {
        title = 'Beklenmeyen sonuç';
        body = r.summary;
      }
    } catch (e) {
      title = 'Test yapılamadı';
      body = '$e';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    app.notify(title, body, error: title != 'Tarayıcı çalışıyor');
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final app = context.app;
    final s = app.settings;

    return PageFrame(
      title: 'Ayarlar',
      subtitle: 'Tüm ayarlar yalnızca bu cihazda saklanır.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            index: 0,
            icon: Icons.badge_rounded,
            title: 'Profil',
            children: [
              _Field(
                label: 'Görünen adın',
                help: 'Karşı taraf seni bu adla görür. Kimliğini kanıtlayan şey ad değil, aşağıdaki anahtardır.',
                child: TextField(
                  controller: _name,
                  maxLength: 40,
                  decoration: const InputDecoration(counterText: '', isDense: true),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) app.updateSettings((x) => x.displayName = v.trim());
                  },
                ),
              ),
              _Field(
                label: 'Kimlik parmak izin',
                help: 'Bu cihaza özel Ed25519 anahtarının özeti. Kişilerin seni bununla tanır.',
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(app.identity.fingerprint,
                          style: TextStyle(fontFamily: kMono, fontSize: 15, color: jp.text, letterSpacing: 1)),
                    ),
                    JIconButton(
                      icon: Icons.copy_rounded,
                      tooltip: 'Kopyala',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: app.identity.fingerprint));
                        app.notify('Kopyalandı', 'Parmak izin panoya kopyalandı.');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            index: 1,
            icon: Icons.download_rounded,
            title: 'Dosya alma',
            children: [
              _Field(
                label: 'İndirme klasörü',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(Platform.isAndroid ? 'Telefonun İndirilenler klasörü › JinjaPeer' : app.downloadDir,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: jp.textMuted, fontSize: 13)),
                    ),
                    const SizedBox(width: S.sm),
                    JButton(
                      label: 'Aç',
                      icon: Icons.folder_open_rounded,
                      kind: BtnKind.ghost,
                      dense: true,
                      onPressed: () => openFolder(app.downloadDir),
                    ),
                    if (isDesktop)
                    JButton(
                      label: 'Değiştir',
                      icon: Icons.drive_folder_upload_rounded,
                      kind: BtnKind.secondary,
                      dense: true,
                      onPressed: () async {
                        final d = await FilePicker.getDirectoryPath(
                            dialogTitle: 'İndirme klasörünü seç', initialDirectory: app.downloadDir);
                        if (d != null) app.updateSettings((x) => x.downloadDir = d);
                      },
                    ),
                    if (isDesktop && s.downloadDir.isNotEmpty)
                      JIconButton(
                        icon: Icons.restart_alt_rounded,
                        tooltip: 'Varsayılana dön',
                        onPressed: () => app.updateSettings((x) => x.downloadDir = ''),
                      ),
                  ],
                ),
              ),
              if (isDesktop)
              _Toggle(
                title: 'Her seferinde nereye kaydedileceğini sor',
                value: s.askWhereToSave,
                onChanged: (v) => app.updateSettings((x) => x.askWhereToSave = v),
              ),
              _Toggle(
                title: 'Güvenilir kişilerden gelenleri otomatik kabul et',
                subtitle: 'Yalnızca Kişilerim\'de "Güvenilir" işaretlediklerin için geçerlidir. Kapalıyken her istek onayına gelir.',
                value: s.autoAcceptTrusted,
                onChanged: (v) => app.updateSettings((x) => x.autoAcceptTrusted = v),
              ),
              _Field(
                label: 'Gelen istek boyut sınırı',
                help: 'Bu boyutu aşan istekler sorulmadan reddedilir.',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final gb in const [0, 1, 5, 20, 100])
                      ChoiceChip(
                        label: Text(gb == 0 ? 'Sınırsız' : '$gb GB'),
                        selected: s.maxIncomingGb == gb,
                        onSelected: (_) => app.updateSettings((x) => x.maxIncomingGb = gb),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            index: 2,
            icon: Icons.palette_rounded,
            title: 'Görünüm',
            children: [
              _Field(
                label: 'Tema',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Segmented<ThemeMode>(
                    value: s.themeMode,
                    items: const [
                      (ThemeMode.dark, 'Koyu', Icons.dark_mode_rounded),
                      (ThemeMode.light, 'Açık', Icons.light_mode_rounded),
                      (ThemeMode.system, 'Sistem', Icons.contrast_rounded),
                    ],
                    onChanged: (m) => app.updateSettings((x) => x.themeMode = m),
                  ),
                ),
              ),
              _Toggle(
                title: 'Hareketleri azalt',
                subtitle: 'Arka plan ve geçiş animasyonlarını kapatır.',
                value: s.reduceMotion,
                onChanged: (v) {
                  Motion.reduce = v;
                  app.updateSettings((x) => x.reduceMotion = v);
                },
              ),
            ],
          ),
          _Section(
            index: 3,
            icon: Icons.router_rounded,
            title: 'Ağ',
            children: [
              _Field(
                label: 'Davet kodu geçerlilik süresi',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in const [5, 15, 60, 240])
                      ChoiceChip(
                        label: Text(m < 60 ? '$m dk' : '${m ~/ 60} saat'),
                        selected: s.inviteMinutes == m,
                        onSelected: (_) => app.updateSettings((x) => x.inviteMinutes = m),
                      ),
                  ],
                ),
              ),
              _Field(
                label: 'STUN sunucuları',
                help: 'Yalnızca cihazının internetteki genel adresini öğrenmek için kullanılır. '
                    'Dosya ya da kod içeriği bu sunuculardan GEÇMEZ. Her satıra bir adres.',
                child: TextField(
                  controller: _ice,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: kMono, fontSize: 12.5),
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (v) => app.updateSettings((x) => x.iceServers =
                      v.split('\n').map((e) => e.trim()).where((e) => e.startsWith('stun:') || e.startsWith('stuns:')).toList()),
                ),
              ),
              _Field(
                label: 'Kendi TURN sunucun (isteğe bağlı)',
                help: 'Çok kısıtlı ağlarda (simetrik NAT, bazı mobil operatörler) doğrudan bağlantı kurulamazsa '
                    'kendi TURN sunucunu ekleyebilirsin. Veri yine uçtan uca şifreli kalır; TURN içeriği göremez.',
                child: Column(
                  children: [
                    TextField(
                      controller: _turnUrl,
                      decoration: const InputDecoration(hintText: 'turn:sunucu.ornek.com:3478', isDense: true),
                      onChanged: (v) => app.updateSettings((x) => x.turnUrl = v.trim()),
                    ),
                    const SizedBox(height: S.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _turnUser,
                            decoration: const InputDecoration(hintText: 'Kullanıcı adı', isDense: true),
                            onChanged: (v) => app.updateSettings((x) => x.turnUser = v),
                          ),
                        ),
                        const SizedBox(width: S.sm),
                        Expanded(
                          child: TextField(
                            controller: _turnPass,
                            obscureText: true,
                            decoration: const InputDecoration(hintText: 'Parola', isDense: true),
                            onChanged: (v) => app.updateSettings((x) => x.turnPass = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            index: 4,
            icon: Icons.health_and_safety_rounded,
            title: 'Virüs taraması',
            children: [
              _Toggle(
                title: 'Gelen her dosyayı tara',
                subtitle: 'Tehdit bulunursa dosya indirme klasörüne yazılmaz, karantinada bekler; '
                    'silmek ya da yine de kaydetmek sana sorulur.',
                value: s.scanEnabled,
                onChanged: (v) => app.updateSettings((x) => x.scanEnabled = v),
              ),
              _Field(
                label: 'Bu cihazdaki tarayıcılar',
                help: Platform.isAndroid
                    ? 'Android\'de ücretsiz bir yerel antivirüs motoru yok. JinjaPeer kontrolleri gizlenmiş programları, '
                        'çift uzantı hilelerini, makroları ve arşivdeki programları yakalar; tam tarama için aşağıya '
                        'ücretsiz VirusTotal anahtarı ekleyebilirsin.'
                    : null,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in app.scanner.availableEngines())
                      Pill(e, icon: Icons.check_circle_rounded, color: jp.success),
                  ],
                ),
              ),
              _Field(
                label: 'VirusTotal API anahtarı (isteğe bağlı, ücretsiz)',
                help: 'virustotal.com\'da ücretsiz hesap açıp API anahtarını yapıştırırsan, gelen her dosyanın yalnızca '
                    'SHA-256 özeti 70\'ten fazla antivirüs motorunun kayıtlarında sorgulanır. Dosyanın kendisi asla yüklenmez.',
                child: TextField(
                  controller: _vt,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'API anahtarı', isDense: true),
                  onChanged: (v) => app.updateSettings((x) => x.virusTotalKey = v.trim()),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: JButton(
                  label: 'Taramayı test et',
                  icon: Icons.bug_report_outlined,
                  kind: BtnKind.secondary,
                  loading: _testing,
                  tooltip: 'Zararsız EICAR test dosyasıyla tarayıcının çalıştığını doğrular',
                  onPressed: _testScan,
                ),
              ),
            ],
          ),
          _Section(
            index: 5,
            icon: Icons.security_rounded,
            title: 'Güvenlik ve gizlilik',
            children: [
              Text(
                '• Bağlantı kodları Ed25519 ile imzalanır, gzip ile sıkıştırılır ve süreli/tek kullanımlıktır.\n'
                '• Her bağlantıda yeni X25519 anahtarı üretilir (ileriye dönük gizlilik).\n'
                '• Tüm veriler WebRTC DTLS içinde, ayrıca ChaCha20-Poly1305 ile ikinci kez şifrelenir.\n'
                '• Sıra dışı, tekrar edilmiş ya da değiştirilmiş tek bir paket bile bağlantıyı anında keser.\n'
                '• Dosya adları temizlenir, klasör dışına yazma engellenir, mevcut dosyaların üzerine yazılmaz.\n'
                '• Her dosya SHA-256 ile doğrulanır; uyuşmazsa kaydedilmez.',
                style: TextStyle(color: jp.textMuted, fontSize: 12.5, height: 1.7),
              ),
              const SizedBox(height: S.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: JButton(
                  label: 'Kimliği ve tüm verileri sıfırla',
                  icon: Icons.restart_alt_rounded,
                  kind: BtnKind.danger,
                  onPressed: () async {
                    if (await confirm(context,
                        title: 'Her şey sıfırlansın mı?',
                        message: 'Yeni bir kimlik oluşturulur; kişilerin seni artık tanımaz. Kişiler, geçmiş ve '
                            'ayarlar silinir. İndirilen dosyalara dokunulmaz. Uygulama kapanacak.',
                        confirmLabel: 'Sıfırla ve kapat',
                        danger: true,
                        icon: Icons.warning_amber_rounded)) {
                      await app.resetAll();
                      exit(0);
                    }
                  },
                ),
              ),
            ],
          ),
          _Section(
            index: 6,
            icon: Icons.info_outline_rounded,
            title: 'Hakkında',
            children: [
              Text('JinjaPeer 1.0.0 · sunucusuz, uçtan uca şifreli P2P dosya aktarımı',
                  style: TextStyle(color: jp.textMuted, fontSize: 12.5)),
              const SizedBox(height: S.sm),
              Text('Kısayollar: Ctrl+N davet · Ctrl+J katıl · Ctrl+1…7 sayfalar · Esc pencereyi kapat',
                  style: TextStyle(color: jp.textFaint, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.index, required this.icon, required this.title, required this.children});
  final int index;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: S.lg),
        child: Glass(
          shadow: false,
          padding: const EdgeInsets.all(S.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconOrb(icon, size: 34),
                  const SizedBox(width: S.md),
                  Text(title, style: context.tt.titleLarge),
                ],
              ),
              const SizedBox(height: S.lg),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.help});
  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: context.tt.titleSmall),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(help!, style: TextStyle(color: jp.textFaint, fontSize: 12, height: 1.4)),
            ),
          const SizedBox(height: S.sm),
          child,
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(color: jp.textFaint, fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: S.md),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
