// ignore_for_file: avoid_print
// Two-device test: one side runs on Windows, the other on a different device
// (Android emulator = separate OS behind its own NAT). The connection codes are
// carried between the two test processes by tools/cross_device.ps1, exactly
// like a user would copy-paste them. Real STUN servers are used.
//
//   ROLE=inviter  EXCHANGE=<folder>        (Windows: writes invite.txt, waits for answer.txt)
//   ROLE=joiner   INVITE=<invite code>     (Android: prints ANSWER_CODE:<code>)
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jinja_peer/core/codes.dart';
import 'package:jinja_peer/core/crypto.dart';
import 'package:jinja_peer/models/models.dart';
import 'package:jinja_peer/services/peer_session.dart';
import 'package:jinja_peer/services/transfer_service.dart';
import 'package:path_provider/path_provider.dart';

const role = String.fromEnvironment('ROLE');
const exchange = String.fromEnvironment('EXCHANGE');
const inviteText = String.fromEnvironment('INVITE');
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

Future<void> runTransfers(PeerSession s, Directory inbox, {required bool sendFirst}) async {
  final received = <TransferRecord>[];
  final ts = TransferService(
    onRecord: (r, _) {
      if (r.direction == TransferDirection.receive) received.add(r);
    },
    notice: (t, m, {error = false}) => log('bildirim: $t – $m'),
    autoAcceptDestination: (_) async => inbox.path,
    maxIncomingBytes: () => 0,
  );
  ts.attach(s);

  final outName = role == 'inviter' ? 'windows_gonderdi.bin' : 'android_gonderdi.bin';
  final outBytes = role == 'inviter' ? payload(1, winSize) : payload(2, andSize);
  final expectIn = role == 'inviter' ? payload(2, andSize) : payload(1, winSize);
  final inName = role == 'inviter' ? 'android_gonderdi.bin' : 'windows_gonderdi.bin';
  final src = File('${inbox.parent.path}/$outName')..writeAsBytesSync(outBytes);

  Future<void> send() async {
    final sw = Stopwatch()..start();
    final b = (await ts.offer(s, [SendSource.fromFile(src)]))!;
    await waitFor(() => b.isFinished, const Duration(minutes: 5), 'gönderim');
    sw.stop();
    log('GÖNDERİM ${b.status.name} ${(outBytes.length / 1048576 / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)} MB/s '
        '(${sw.elapsedMilliseconds} ms)');
    expect(b.status, BatchStatus.done, reason: b.reason);
  }

  Future<void> receive() async {
    await waitFor(() => received.isNotEmpty, const Duration(minutes: 5), 'alım');
    final r = received.single;
    expect(r.status, RecordStatus.completed, reason: r.error);
    final got = await File('${inbox.path}/$inName').readAsBytes();
    expect(got.length, expectIn.length);
    expect(hex(await sha256(got)), hex(await sha256(expectIn)));
    log('ALIM tamam, SHA-256 eşleşti: ${r.sha256}');
  }

  if (sendFirst) {
    await send();
    await receive();
  } else {
    await receive();
    await send();
  }
  // Let the last confirmations travel before closing.
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
      log('BAĞLANDI: karşı=${s.peerName} doğrulama=${s.verificationCode} rota=${s.routeInfo} rtt=${s.rttMs}');

      await runTransfers(s, inbox, sendFirst: role == 'inviter');
      log('SONUÇ: BAŞARILI');
      await s.close();
      await tmp.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(minutes: 40)));
}
