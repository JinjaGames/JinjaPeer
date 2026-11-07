// Widget tests for the JinjaPeer UI. They drive the real app shell against a
// real AppController (temp storage) and fake, network-less peer sessions.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jinja_peer/core/codes.dart';
import 'package:jinja_peer/core/crypto.dart';
import 'package:jinja_peer/main.dart';
import 'package:jinja_peer/models/models.dart';
import 'package:jinja_peer/services/app_controller.dart';
import 'package:jinja_peer/services/peer_session.dart';
import 'package:jinja_peer/services/storage.dart';
import 'package:jinja_peer/services/transfer_service.dart';
import 'package:jinja_peer/ui/widgets/glass.dart';
import 'package:jinja_peer/ui/widgets/liquid_background.dart';

late Directory tmp;
late JsonStore store;
late AppController ctrl;

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final p in paths) {
    final f = File(p);
    if (f.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      any = true;
    }
  }
  if (any) await loader.load();
}

/// Lets real async work (file IO, isolates, crypto) run, then rebuilds.
Future<void> settle(WidgetTester t, [int rounds = 4]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<AppController> makeApp(WidgetTester t) async {
  final c = await t.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('jp_ui');
    store = await JsonStore.at(Directory('${tmp.path}/data'));
    final c = await AppController.load(store: store, downloadDir: '${tmp.path}/indirilen');
    c.settings.displayName = 'Eren';
    return c;
  });
  ctrl = c!;
  addTearDown(() async {
    final c = ctrl;
    await t.runAsync(() async {
      try {
        for (final s in c.sessions) {
          s.testSent = null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
  });
  return c;
}

Future<void> pumpApp(WidgetTester t, AppController c, {Size size = const Size(1440, 920)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  Motion.reduce = true;
  await t.pumpWidget(JinjaPeerApp(controller: c));
  await t.pump(const Duration(milliseconds: 100));
}

/// Flush toast timers so no timer is left pending at the end of a test.
Future<void> finish(WidgetTester t) async {
  await t.pump(const Duration(seconds: 10));
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

Future<PeerSession> addPeer(WidgetTester t, AppController c, String name, {Identity? id}) async {
  final s = await t.runAsync(() async {
    final peer = id ?? (await Identity.generate()).$1;
    return PeerSession.fakeConnected(me: c.identity, peer: peer, peerName: name);
  });
  c.debugAddSession(s!);
  await t.pump();
  return s;
}

String hex32(int n) => n.toRadixString(16).padLeft(32, '0');

Map<String, dynamic> offer(String req, List<Map<String, dynamic>> items) => {
      't': 'offer',
      'req': req.padLeft(16, '0'),
      'total': items.fold<int>(0, (a, i) => a + (i['size'] as int)),
      'items': items,
    };

Future<void> deliver(WidgetTester t, AppController c, PeerSession s, Map<String, dynamic> m) async {
  await t.runAsync(() => c.transfers.debugReceiveControl(s, m));
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> goTo(WidgetTester t, String label) async {
  await t.tap(find.text(label).first);
  await t.pump(const Duration(milliseconds: 400));
}

JButton button(WidgetTester t, String label) =>
    t.widget<JButton>(find.ancestor(of: find.text(label), matching: find.byType(JButton)).first);

void main() {
  setUpAll(() async {
    await _loadFont('Segoe UI Variable Text', [r'C:\Windows\Fonts\SegUIVar.ttf', r'C:\Windows\Fonts\segoeui.ttf']);
    await _loadFont('Segoe UI', [r'C:\Windows\Fonts\segoeui.ttf']);
    await _loadFont('Consolas', [r'C:\Windows\Fonts\consola.ttf']);
    await _loadFont('MaterialIcons', [r'C:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf']);
  });

  testWidgets('shell renders and every page opens without layout errors', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    expect(find.textContaining('Eren'), findsWidgets);
    expect(find.text('Davet oluştur'), findsOneWidget);
    expect(find.text('Koda katıl'), findsOneWidget);
    expect(find.text('Henüz aktarım yok'), findsOneWidget);

    for (final (nav, expectText) in [
      ('Bağlantılar', 'Henüz bağlantı yok'),
      ('Aktarımlar', 'Şu an aktarım yok'),
      ('İstekler', 'Bekleyen istek yok'),
      ('Geçmiş', 'Geçmiş boş'),
      ('Kişilerim', 'Henüz kişi yok'),
      ('Ayarlar', 'İndirme klasörü'),
      ('Ana sayfa', 'Son aktarımlar'),
    ]) {
      await goTo(t, nav);
      expect(find.text(expectText), findsWidgets, reason: 'page $nav');
    }

    // Keyboard shortcuts switch pages.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.digit5);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump(const Duration(milliseconds: 400));
    expect(c.page.value, AppPage.history);
    await finish(t);
  });

  testWidgets('narrow window uses bottom navigation', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c, size: const Size(700, 1000));
    expect(find.text('doğrudan · şifreli'), findsNothing); // no sidebar
    expect(find.text('Aktarımlar'), findsOneWidget);
    await goTo(t, 'İstekler');
    expect(c.page.value, AppPage.requests);
    expect(find.text('Bekleyen istek yok'), findsOneWidget);
    await finish(t);
  });

  testWidgets('connect dialog validates invite codes', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);

    // Invite tab: password must be at least 4 chars.
    await t.tap(find.text('Yeni bağlantı').first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Davet kodu oluştur'), findsOneWidget);
    await t.tap(find.text('Ek bağlantı şifresi'));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField).first, '12');
    await t.pump();
    expect(find.text('En az 4 karakter olmalı'), findsOneWidget);
    expect(button(t, 'Davet kodu oluştur').onPressed, isNull);
    await t.enterText(find.byType(TextField).first, '1234');
    await t.pump();
    expect(button(t, 'Davet kodu oluştur').onPressed, isNotNull);

    // Join tab.
    await t.tap(find.text('Koda katıl').last);
    await t.pump(const Duration(milliseconds: 400));
    final field = find.byType(TextField).first;

    await t.enterText(field, 'merhaba dünya');
    await t.pump(const Duration(milliseconds: 300));
    await settle(t);
    expect(find.textContaining('Bu bir JinjaPeer kodu değil'), findsOneWidget);

    final (peer, _) = (await t.runAsync(Identity.generate))!;
    Future<ConnectionCode> code(CodeKind k, {bool pw = false}) async => (await t.runAsync(() async =>
        ConnectionCode.create(
          kind: k,
          identity: peer,
          sessionId: randomBytes(16),
          sdp: 'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n',
          ephemeralKey: (await EphemeralKey.generate()).publicKey,
          name: 'Zeynep',
          validity: const Duration(minutes: 10),
          passwordRequired: pw,
        )))!;

    final answer = await code(CodeKind.answer);
    await t.enterText(field, answer.encoded);
    await t.pump(const Duration(milliseconds: 300));
    await settle(t);
    expect(find.textContaining('Bu bir yanıt kodu'), findsOneWidget);

    final invite = await code(CodeKind.invite, pw: true);
    // Simulate a messenger app wrapping the code in line breaks.
    final wrapped = '${invite.encoded.substring(0, 300)}\n${invite.encoded.substring(300)}  ';
    await t.enterText(field, wrapped);
    await t.pump(const Duration(milliseconds: 300));
    await settle(t, 6);
    expect(find.text('Zeynep seni davet ediyor'), findsOneWidget);
    expect(find.text('İmza doğrulandı'), findsOneWidget);
    expect(find.text('Şifre gerekli'), findsOneWidget);
    expect(button(t, 'Katıl ve yanıt kodu oluştur').onPressed, isNull);
    await t.enterText(find.widgetWithText(TextField, 'Bağlantı şifresi'), 'gizli');
    await t.pump();
    expect(button(t, 'Katıl ve yanıt kodu oluştur').onPressed, isNotNull);

    // Tampered code is refused.
    final tampered = '${invite.encoded.substring(0, invite.encoded.length - 10)}AAAAAAAAAA';
    await t.enterText(field, tampered);
    await t.pump(const Duration(milliseconds: 300));
    await settle(t, 6);
    expect(find.text('Zeynep seni davet ediyor'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('Kod')), findsWidgets);

    // Esc closes the dialog.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Katıl ve yanıt kodu oluştur'), findsNothing);
    await finish(t);
  });

  testWidgets('incoming request: sanitized names, risk warning, reject', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    final s = await addPeer(t, c, 'Zeynep');

    await deliver(t, c, s, offer('a1', [
      {'id': hex32(1), 'name': '../../setup.exe', 'dir': '../../Windows/System32', 'size': 1000},
      {'id': hex32(2), 'name': 'CON.txt', 'dir': '', 'size': 5},
      {'id': hex32(3), 'name': 'tatil.jpg', 'dir': 'Fotoğraflar', 'size': 2048},
    ]));
    expect(c.transfers.incomingPending.length, 1);
    expect(find.text('Görüntüle'), findsOneWidget); // toast action

    await goTo(t, 'İstekler');
    expect(find.textContaining('sana 3 dosya göndermek istiyor'), findsOneWidget);
    expect(find.text('Windows/System32/.._.._setup.exe'), findsOneWidget);
    expect(find.text('_CON.txt'), findsOneWidget);
    expect(find.text('Fotoğraflar/tatil.jpg'), findsOneWidget);
    expect(find.textContaining('1 çalıştırılabilir'), findsOneWidget);
    expect(find.text('Kayıtlı değil'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('../')), findsNothing);

    await t.tap(find.text('Reddet'));
    await settle(t);
    expect(s.testSent!.last, {'t': 'reject', 'req': '00000000000000a1', 'reason': 'user'});
    expect(c.transfers.incomingPending, isEmpty);
    expect(find.text('Bekleyen istek yok'), findsOneWidget);
    expect(c.history.where((r) => r.status == RecordStatus.rejected).length, 3);
    // Nothing was written to disk.
    expect(Directory('${tmp.path}/indirilen').existsSync(), isFalse);
    await finish(t);
  });

  testWidgets('incoming request: accept creates folder and shows active transfer', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    final s = await addPeer(t, c, 'Zeynep');
    await deliver(t, c, s, offer('b2', [
      {'id': hex32(10), 'name': 'rapor.pdf', 'dir': '', 'size': 4096},
    ]));
    await goTo(t, 'İstekler');
    await t.tap(find.text('Kabul et'));
    await settle(t);
    expect(s.testSent!.last, {'t': 'accept', 'req': '00000000000000b2'});
    expect(Directory('${tmp.path}/indirilen').existsSync(), isTrue);
    expect(c.transfers.active.length, 1);

    await goTo(t, 'Aktarımlar');
    expect(find.text('rapor.pdf'), findsOneWidget);
    expect(find.text('Alınıyor'), findsOneWidget);

    // Sender cancels → receiver shows it as canceled.
    await deliver(t, c, s, {'t': 'cancel', 'req': '00000000000000b2'});
    expect(find.text('İptal edildi'), findsWidgets);
    await finish(t);
  });

  testWidgets('protocol limits: busy, size limit, malformed offers', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    final s = await addPeer(t, c, 'Spamcı');

    for (var i = 0; i < kMaxPendingRequestsPerPeer + 1; i++) {
      await deliver(t, c, s, offer('c$i', [
        {'id': hex32(100 + i), 'name': 'f$i.bin', 'size': 1},
      ]));
    }
    expect(c.transfers.incomingPending.length, kMaxPendingRequestsPerPeer);
    expect(s.testSent!.last['reason'], 'busy');

    // Duplicate file ids, bad ids, negative sizes → invalid.
    final s2 = await addPeer(t, c, 'Bozuk');
    await deliver(t, c, s2, offer('d1', [
      {'id': 'zz', 'name': 'a', 'size': 1},
    ]));
    expect(s2.testSent!.last['reason'], 'invalid');
    await deliver(t, c, s2, offer('d2', [
      {'id': hex32(500), 'name': 'a', 'size': -5},
    ]));
    expect(s2.testSent!.last['reason'], 'invalid');
    await deliver(t, c, s2, offer('d3', [
      {'id': hex32(501), 'name': 'a', 'size': 1},
      {'id': hex32(501), 'name': 'b', 'size': 1},
    ]));
    expect(s2.testSent!.last['reason'], 'invalid');

    // Size limit from settings.
    c.updateSettings((x) => x.maxIncomingGb = 1);
    await deliver(t, c, s2, offer('d4', [
      {'id': hex32(502), 'name': 'film.mkv', 'size': 2 * 1024 * 1024 * 1024},
    ]));
    expect(s2.testSent!.last['reason'], 'size');
    expect(c.transfers.incomingPending.where((b) => identical(b.session, s2)), isEmpty);

    // Chunks for unknown files / before acceptance are ignored (nothing written).
    expect(Directory('${tmp.path}/indirilen').existsSync(), isFalse);
    await finish(t);
  });

  testWidgets('trusted contact + auto-accept skips the prompt', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    final s = await addPeer(t, c, 'Annem');
    await t.runAsync(() => c.addContact(s, name: 'Annem', trusted: true));
    c.updateSettings((x) => x.autoAcceptTrusted = true);
    await deliver(t, c, s, offer('e1', [
      {'id': hex32(600), 'name': 'tarif.txt', 'size': 10},
    ]));
    await settle(t);
    expect(s.testSent!.last, {'t': 'accept', 'req': '00000000000000e1'});
    expect(c.transfers.incomingPending, isEmpty);

    // A stranger with auto-accept on is still asked.
    final stranger = await addPeer(t, c, 'Yabancı');
    await deliver(t, c, stranger, offer('e2', [
      {'id': hex32(601), 'name': 'x.txt', 'size': 10},
    ]));
    expect(c.transfers.incomingPending.length, 1);
    await finish(t);
  });

  testWidgets('connection detail: verification, save contact, impostor warning, disconnect', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    final s = await addPeer(t, c, 'Mert');
    await goTo(t, 'Bağlantılar');
    expect(find.text('TEST-K0D1'), findsOneWidget);
    expect(find.text('Yeni kişi'), findsOneWidget);
    expect(find.text('Dosyaları ya da klasörleri buraya sürükle'), findsOneWidget);

    await t.tap(find.text('Kişilere ekle'));
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.byType(TextField).last, 'Mert (iş)');
    await t.tap(find.text('Ekle'));
    await settle(t);
    expect(c.contacts.single.name, 'Mert (iş)');
    expect(find.text('Kayıtlı kişi · kimlik doğrulandı'), findsOneWidget);

    // Someone else calling themselves "Mert (iş)" with another key.
    final fake = await addPeer(t, c, 'Mert (iş)');
    c.selectedSession.value = fake.id;
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('kimlik anahtarı FARKLI'), findsOneWidget);

    // Disconnect the real one.
    c.selectedSession.value = s.id;
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Bağlantıyı kes'));
    await settle(t);
    expect(s.state, SessionState.closed);
    expect(find.text('Listeden kaldır'), findsOneWidget);
    await finish(t);
  });

  testWidgets('contacts page: trust toggle, rename, delete', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    final s = await addPeer(t, c, 'Ayşe');
    await t.runAsync(() => c.addContact(s, name: 'Ayşe'));
    await goTo(t, 'Kişilerim');
    expect(find.text('Ayşe'), findsOneWidget);
    expect(find.text(c.contacts.single.fingerprint), findsOneWidget);
    expect(find.text('Şu an bağlı'), findsOneWidget);

    await t.tap(find.byType(Switch).first);
    await t.pump();
    expect(c.contacts.single.trusted, isTrue);

    await t.tap(find.byTooltip('Diğer').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    await t.tap(find.text('Yeniden adlandır'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Kişiyi yeniden adlandır'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Ayşe Abla');
    await t.tap(find.text('Kaydet'));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.contacts.single.name, 'Ayşe Abla');

    await t.tap(find.byTooltip('Diğer').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    await t.tap(find.text('Kişiyi sil'));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Sil'));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.contacts, isEmpty);
    expect(find.text('Henüz kişi yok'), findsOneWidget);
    await finish(t);
  });

  testWidgets('history: search, filters, sent/received tabs, clear', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    final now = DateTime.now();
    TransferRecord rec(String name, TransferDirection d, RecordStatus st, {int ago = 0}) => TransferRecord(
          id: name,
          direction: d,
          fileName: name,
          size: 1024 * 1024,
          peerName: 'Zeynep',
          peerKey: 'k',
          status: st,
          startedAt: now.subtract(Duration(days: ago, seconds: 5)),
          finishedAt: now.subtract(Duration(days: ago)),
          path: '${tmp.path}/$name',
        );
    c.debugAddRecord(rec('rapor.pdf', TransferDirection.send, RecordStatus.completed, ago: 3));
    c.debugAddRecord(rec('tatil.mp4', TransferDirection.receive, RecordStatus.completed, ago: 1));
    c.debugAddRecord(rec('bozuk.zip', TransferDirection.receive, RecordStatus.failed));
    await t.pump();

    await goTo(t, 'Geçmiş');
    expect(find.text('3 kayıt · yalnızca bu cihazda saklanır'), findsOneWidget);
    expect(find.text('BUGÜN'), findsOneWidget);
    expect(find.text('DÜN'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'rapor');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('rapor.pdf'), findsOneWidget);
    expect(find.text('tatil.mp4'), findsNothing);
    await t.enterText(find.byType(TextField).first, '');
    await t.pump();

    await t.tap(find.text('Sorunlu'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('bozuk.zip'), findsOneWidget);
    expect(find.text('rapor.pdf'), findsNothing);

    await goTo(t, 'Aktarımlar');
    await t.tap(find.text('Aktardıklarım'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('rapor.pdf'), findsOneWidget);
    expect(find.text('tatil.mp4'), findsNothing);
    await t.tap(find.text('Aldıklarım'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('tatil.mp4'), findsOneWidget);
    expect(find.text('bozuk.zip'), findsOneWidget);

    await goTo(t, 'Geçmiş');
    await t.tap(find.text('Geçmişi temizle'));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Temizle'));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.history, isEmpty);
    expect(find.text('Geçmiş boş'), findsOneWidget);
    await finish(t);
  });

  testWidgets('settings are applied and persisted', (t) async {
    final c = await makeApp(t);
    await pumpApp(t, c);
    await goTo(t, 'Ayarlar');
    await t.ensureVisible(find.text('Açık'));
    await t.pump();
    await t.tap(find.text('Açık'));
    await t.pump(const Duration(milliseconds: 500));
    expect(c.settings.themeMode, ThemeMode.light);
    expect(Theme.of(t.element(find.text('Ayarlar').last)).brightness, Brightness.light);

    await t.ensureVisible(find.text('Her seferinde nereye kaydedileceğini sor'));
    await t.pump();
    await t.tap(find.text('Her seferinde nereye kaydedileceğini sor'));
    await t.pump();
    expect(c.settings.askWhereToSave, isTrue);

    await t.ensureVisible(find.text('5 GB'));
    await t.pump();
    await t.tap(find.text('5 GB'));
    await t.pump();
    expect(c.settings.maxIncomingGb, 5);

    await t.enterText(find.byType(TextField).first, 'Eren K.');
    await t.pump();
    expect(c.settings.displayName, 'Eren K.');

    await t.pump(const Duration(milliseconds: 500)); // debounce fires
    await settle(t, 30); // file IO completes
    final saved = await t.runAsync(() => store.read('settings'));
    final reloaded = AppSettings.fromJson((saved as Map).cast<String, dynamic>());
    expect(reloaded.themeMode, ThemeMode.light);
    expect(reloaded.askWhereToSave, isTrue);
    expect(reloaded.maxIncomingGb, 5);
    expect(reloaded.displayName, 'Eren K.');
    await finish(t);
  });

  testWidgets('identity survives restart, contacts and history reload', (t) async {
    final c = await makeApp(t);
    final s = await addPeer(t, c, 'Kalıcı');
    await t.runAsync(() async {
      await c.addContact(s, name: 'Kalıcı');
      c.debugAddRecord(TransferRecord(
        id: 'x',
        direction: TransferDirection.send,
        fileName: 'a.txt',
        size: 3,
        peerName: 'Kalıcı',
        peerKey: s.peerKeyB64,
        status: RecordStatus.completed,
        startedAt: DateTime.now(),
        finishedAt: DateTime.now(),
      ));
      await store.flushAll();
    });
    final c2 = (await t.runAsync(() => AppController.load(store: store, downloadDir: tmp.path)))!;
    expect(c2.identity.fingerprint, c.identity.fingerprint);
    expect(c2.contacts.single.name, 'Kalıcı');
    expect(c2.contacts.single.sentBytes, 3);
    expect(c2.history.single.fileName, 'a.txt');
  });
}
