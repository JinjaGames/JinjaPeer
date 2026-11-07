// ignore_for_file: avoid_print
// Two-device test: one side runs on Windows, the other on a different device
// (Android emulator = separate OS behind its own NAT). The connection codes are
// carried between the two test processes by tools/cross_device.ps1, exactly
// like a user would copy-paste them. Real STUN servers are used.
//
//   ROLE=inviter  EXCHANGE=<folder>                      (Windows)
//   ROLE=joiner   INVITE=<invite code> PHOTO_SHA=<hex>   (Android)
//
// Windows → Android: a 24 MB file + a real EXIF photo (must arrive bit-identical,
// get scanned and land in the phone's public Downloads/JinjaPeer folder).
// Android → Windows: a 12 MB file.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jinja_peer/core/codes.dart';
import 'package:jinja_peer/core/crypto.dart';
import 'package:jinja_peer/models/models.dart';
import 'package:jinja_peer/services/android_bridge.dart';
import 'package:jinja_peer/services/peer_session.dart';
import 'package:jinja_peer/services/scanner.dart';
import 'package:jinja_peer/services/transfer_service.dart';
import 'package:path_provider/path_provider.dart';

const role = String.fromEnvironment('ROLE');
const exchange = String.fromEnvironment('EXCHANGE');
const inviteText = String.fromEnvironment('INVITE');
const photoSha = String.fromEnvironment('PHOTO_SHA');
const photoPath = String.fromEnvironment('PHOTO');
const password = 'kopru-2026';

const ice = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun.cloudflare.com:3478'},
];

Uint8List payload(int seed, int size) {
  final r = Random(seed);
  final b = Uint8List(size);
  for (var i = 0; i < size; i++) {
    b[i] = r.nextInt(256);
  }
  return b;
}

const winSize = 24 * 1024 * 1024 + 777; // Windows → Android
const andSize = 12 * 1024 * 1024 + 333; // Android → Windows

void log(String m) => print('[$role] $m');

Future<void> waitFor(bool Function() c, Duration timeout, String what) async {
  final end = DateTime.now().add(timeout);
  while (!c()) {
    if (DateTime.now().isAfter(end)) throw StateError('zaman aşımı: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String candidateSummary(String sdp) {
  final types = <String, int>{};
  for (final l in sdp.split('\n')) {
    final m = RegExp(r' typ (\w+)').firstMatch(l);
    if (l.startsWith('a=candidate') && m != null) types[m.group(1)!] = (types[m.group(1)!] ?? 0) + 1;
  }
  return types.toString();
}

Future<String?> _publish(FileTask t, String path) async {
  final r = await AndroidBridge.saveToDownloads(path, t.name, t.relDir);
  return r == null ? null : r['uri'];
}

Future<void> runTransfers(PeerSession s, Directory inbox) async {
  final received = <TransferRecord>[];
  final scanner = MalwareScanner(() => const ScanOptions());
  final ts = TransferService(
    onRecord: (r, _) {
      if (r.direction == TransferDirection.receive) received.add(r);
    },
    notice: (t, m, {error = false}) => log('bildirim: $t – $m'),
    autoAcceptDestination: (_) async => inbox.path,
    maxIncomingBytes: () => 0,
    scan: (path, name, sha) => scanner.scanFile(path, displayName: name, sha256: sha),
    publish: AndroidBridge.available ? _publish : null,
  );
  ts.attach(s);

  Future<void> send(List<File> files) async {
    final sw = Stopwatch()..start();
    final total = files.fold<int>(0, (a, f) => a + f.lengthSync());
    final b = (await ts.offer(s, [for (final f in files) SendSource.fromFile(f)]))!;
    await waitFor(() => b.isFinished, const Duration(minutes: 5), 'gönderim');
    sw.stop();
    log('GÖNDERİM ${b.status.name}: ${files.length} dosya, ${(total / 1048576).toStringAsFixed(1)} MB, '
        '${(total / 1048576 / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)} MB/s');
    expect(b.status, BatchStatus.done, reason: b.reason);
  }

  if (role == 'inviter') {
    final big = File('${inbox.parent.path}/windows_gonderdi.bin')..writeAsBytesSync(payload(1, winSize));
    await send([big, File(photoPath)]);

    await waitFor(() => received.isNotEmpty, const Duration(minutes: 5), 'alım');
    final r = received.single;
    expect(r.status, RecordStatus.completed, reason: r.error);
    final got = await File('${inbox.path}/android_gonderdi.bin').readAsBytes();
    expect(hex(await sha256(got)), hex(await sha256(payload(2, andSize))));
    log('ALIM tamam, SHA-256 eşleşti · tarama: ${r.scan}');
  } else {
    await waitFor(() => received.length >= 2, const Duration(minutes: 5), 'alım');
    final bin = received.firstWhere((r) => r.fileName == 'windows_gonderdi.bin');
    final photo = received.firstWhere((r) => r.fileName.endsWith('.jpg'));
    for (final r in [bin, photo]) {
      expect(r.status, RecordStatus.completed, reason: r.error);
      log('ALINDI ${r.fileName} → ${r.path} · tarama: ${r.scan}');
      expect(r.path, startsWith('content://'), reason: 'must be in public Downloads');
      expect(await AndroidBridge.exists(r.path!), isTrue);
    }
    expect(bin.sha256, hex(await sha256(payload(1, winSize))));
    expect(photo.sha256, photoSha, reason: 'photo must be bit-identical (original quality)');
    log('FOTOĞRAF orijinal kalitede: SHA-256 birebir aynı ($photoSha)');

    final back = File('${inbox.parent.path}/android_gonderdi.bin')..writeAsBytesSync(payload(2, andSize));
    await send([back]);
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  ts.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cross-device P2P ($role)', (tester) async {
    await tester.runAsync(() async {
      final (me, _) = await Identity.generate();
      final tmp = await (await getTemporaryDirectory()).createTemp('jp_cross');
      final inbox = Directory('${tmp.path}/gelen')..createSync();
      log('platform=${Platform.operatingSystem} kimlik=${me.fingerprint}');

      late PeerSession s;
      if (role == 'inviter') {
        s = await PeerSession.createInvite(
          identity: me,
          myName: 'Windows-PC',
          iceServers: ice,
          validity: const Duration(minutes: 30),
          password: password,
        );
        expect(s.state, SessionState.waitingForAnswer, reason: s.error);
        log('davet kodu ${s.myCode!.encoded.length} karakter, adaylar ${candidateSummary(s.myCode!.sdp)}');
        final dir = Directory(exchange)..createSync(recursive: true);
        File('${dir.path}/invite.txt').writeAsStringSync(s.myCode!.encoded);
        final answerFile = File('${dir.path}/answer.txt');
        await waitFor(() => answerFile.existsSync() && answerFile.lengthSync() > 100,
            const Duration(minutes: 25), 'yanıt kodu');
        final answer = await ConnectionCode.parse(answerFile.readAsStringSync(), expect: CodeKind.answer);
        log('yanıt kodu alındı: ${answer.name}, adaylar ${candidateSummary(answer.sdp)}');
        await s.applyAnswer(answer);
      } else {
        expect(inviteText, isNotEmpty);
        final invite = await ConnectionCode.parse(inviteText, expect: CodeKind.invite);
        log('davet: ${invite.name}, şifre gerekli=${invite.passwordRequired}');
        s = await PeerSession.acceptInvite(
          identity: me,
          myName: 'Android-Emulator',
          iceServers: ice,
          invite: invite,
          password: password,
        );
        expect(s.state, SessionState.waitingForPeer, reason: s.error);
        log('adaylar ${candidateSummary(s.myCode!.sdp)}');
        print('ANSWER_CODE:${s.myCode!.encoded}');
      }

      await waitFor(() => s.state.isLive || s.state.isOver, const Duration(minutes: 3), 'bağlantı');
      expect(s.state, SessionState.connected, reason: s.error);
      await Future<void>.delayed(const Duration(seconds: 1));
      log('BAĞLANDI: karşı=${s.peerName} doğrulama=${s.verificationCode} rota=${s.routeInfo}');

      await runTransfers(s, inbox);
      log('SONUÇ: BAŞARILI');
      await s.close();
      await tmp.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(minutes: 40)));
}
