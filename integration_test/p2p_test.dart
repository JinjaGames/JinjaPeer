import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jinja_peer/core/codes.dart';
import 'package:jinja_peer/core/crypto.dart';
import 'package:jinja_peer/models/models.dart';
import 'package:jinja_peer/services/peer_session.dart';
import 'package:jinja_peer/services/transfer_service.dart';

Future<void> waitFor(bool Function() cond, {Duration timeout = const Duration(seconds: 40)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

class TimeoutException implements Exception {
  TimeoutException(this.m);
  final String m;
  @override
  String toString() => m;
}

Future<(PeerSession, PeerSession)> connectPair({String? pwA, String? pwB}) async {
  final (idA, _) = await Identity.generate();
  final (idB, _) = await Identity.generate();
  const ice = <Map<String, dynamic>>[];
  final a = await PeerSession.createInvite(
      identity: idA, myName: 'Ayşe', iceServers: ice, validity: const Duration(minutes: 5), password: pwA);
  expect(a.state, SessionState.waitingForAnswer, reason: a.error);
  final invite = await ConnectionCode.parse(a.myCode!.encoded, expect: CodeKind.invite);
  debugPrint('invite code length: ${a.myCode!.encoded.length}');
  final b = await PeerSession.acceptInvite(
      identity: idB, myName: 'Burak', iceServers: ice, invite: invite, password: pwB);
  expect(b.state, SessionState.waitingForPeer, reason: b.error);
  debugPrint('answer code length: ${b.myCode!.encoded.length}');
  final answer = await ConnectionCode.parse(b.myCode!.encoded, expect: CodeKind.answer);
  await a.applyAnswer(answer);
  return (a, b);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connect + transfer + verify over real WebRTC', (tester) async {
    await tester.runAsync(() async {
      final (a, b) = await connectPair(pwA: 'parola1', pwB: 'parola1');
      await waitFor(() => a.state.isLive && b.state.isLive);
      expect(a.verificationCode, b.verificationCode);
      expect(a.peerName, 'Burak');
      expect(b.peerName, 'Ayşe');
      debugPrint('connected, SAS=${a.verificationCode} route=${a.routeInfo}');

      final tmp = Directory.systemTemp.createTempSync('jp_e2e');
      final inbox = Directory('${tmp.path}/gelen')..createSync();
      final rnd = Random(7);
      final big = File('${tmp.path}/büyük dosya.bin')
        ..writeAsBytesSync(Uint8List.fromList(List.generate(24 * 1024 * 1024 + 123, (_) => rnd.nextInt(256))));
      final empty = File('${tmp.path}/boş.txt')..writeAsBytesSync([]);
      final sub = Directory('${tmp.path}/Klasör/alt')..createSync(recursive: true);
      final nested = File('${sub.path}/not.md')..writeAsStringSync('merhaba dünya');

      final recA = <TransferRecord>[], recB = <TransferRecord>[];
      final ta = TransferService(
        onRecord: (r, _) => recA.add(r),
        notice: (t, m, {error = false}) => debugPrint('A: $t – $m'),
        autoAcceptDestination: (_) async => null,
        maxIncomingBytes: () => 0,
      );
      final tb = TransferService(
        onRecord: (r, _) => recB.add(r),
        notice: (t, m, {error = false}) => debugPrint('B: $t – $m'),
        autoAcceptDestination: (_) async => null,
        maxIncomingBytes: () => 0,
      );
      ta.attach(a);
      tb.attach(b);

      final sw = Stopwatch()..start();
      await ta.offer(a, [
        SendSource.fromFile(big),
        SendSource.fromFile(empty),
        SendSource.fromFile(nested, relDir: 'Klasör/alt'),
        SendSource.fromFile(nested, relDir: '../../kaçış'),
      ]);
      await waitFor(() => tb.incomingPending.isNotEmpty);
      final req = tb.incomingPending.first;
      expect(req.tasks.length, 4);
      expect(req.tasks[3].relDir, 'kaçış');
      await tb.accept(req, inbox.path);
      await waitFor(() => ta.batches.first.isFinished, timeout: const Duration(minutes: 3));
      sw.stop();
      final mbps = (big.lengthSync() / 1048576) / (sw.elapsedMilliseconds / 1000);
      debugPrint('transfer took ${sw.elapsedMilliseconds} ms (${mbps.toStringAsFixed(1)} MB/s)');

      expect(ta.batches.first.status, BatchStatus.done, reason: ta.batches.first.reason);
      expect(recA.every((r) => r.status == RecordStatus.completed), isTrue);
      expect(recB.every((r) => r.status == RecordStatus.completed), isTrue, reason: recB.map((r) => r.error).join(','));
      final got = File('${inbox.path}/büyük dosya.bin');
      expect(await got.length(), await big.length());
      expect(hex(await sha256(await got.readAsBytes())), hex(await sha256(await big.readAsBytes())));
      expect(File('${inbox.path}/boş.txt').lengthSync(), 0);
      expect(File('${inbox.path}/Klasör/alt/not.md').readAsStringSync(), 'merhaba dünya');
      expect(File('${inbox.path}/kaçış/not.md').existsSync(), isTrue);
      expect(inbox.listSync(recursive: true).where((e) => e.path.endsWith('.jppart')), isEmpty);

      // reject flow
      await ta.offer(a, [SendSource.fromFile(empty)]);
      await waitFor(() => tb.incomingPending.isNotEmpty);
      await tb.reject(tb.incomingPending.first);
      await waitFor(() => ta.batches.first.status == BatchStatus.rejected);

      // cancel mid-way by receiver
      await ta.offer(a, [SendSource.fromFile(big)]);
      await waitFor(() => tb.incomingPending.isNotEmpty);
      final r2 = tb.incomingPending.first;
      final inbox2 = Directory('${tmp.path}/gelen2')..createSync();
      await tb.accept(r2, inbox2.path);
      await waitFor(() => r2.tasks.first.transferred > 1024 * 1024);
      await tb.cancelBatch(r2);
      await waitFor(() => ta.batches.first.isFinished);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(inbox2.listSync(recursive: true).whereType<File>(), isEmpty);

      await a.close();
      await waitFor(() => b.state.isOver);
      ta.dispose();
      tb.dispose();
      tmp.deleteSync(recursive: true);
    });
  });

  testWidgets('pause/resume and disconnect mid-transfer leave no partial files', (tester) async {
    await tester.runAsync(() async {
      final (a, b) = await connectPair();
      await waitFor(() => a.state.isLive && b.state.isLive);
      final tmp = Directory.systemTemp.createTempSync('jp_e2e2');
      final inbox = Directory('${tmp.path}/gelen')..createSync();
      final rnd = Random(3);
      final big = File('${tmp.path}/video.mp4')
        ..writeAsBytesSync(Uint8List.fromList(List.generate(64 * 1024 * 1024, (_) => rnd.nextInt(256))));

      final recB = <TransferRecord>[];
      final ta = TransferService(
        onRecord: (_, _) {},
        notice: (_, _, {error = false}) {},
        autoAcceptDestination: (_) async => null,
        maxIncomingBytes: () => 0,
      );
      final tb = TransferService(
        onRecord: (r, _) => recB.add(r),
        notice: (_, _, {error = false}) {},
        autoAcceptDestination: (_) async => inbox.path, // auto-accept path
        maxIncomingBytes: () => 0,
      );
      ta.attach(a);
      tb.attach(b);

      final batch = (await ta.offer(a, [SendSource.fromFile(big)]))!;
      await waitFor(() => batch.status == BatchStatus.accepted);
      await waitFor(() => batch.transferred > 4 * 1024 * 1024);

      // Receiver pauses → sender stops.
      final rb = tb.batches.first;
      await tb.setPaused(rb, true);
      await waitFor(() => batch.paused);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final frozen = batch.transferred;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(batch.transferred, frozen, reason: 'sender must not send while paused');
      expect(batch.tasks.first.status, TaskStatus.paused);

      await tb.setPaused(rb, false);
      await waitFor(() => batch.transferred > frozen);

      // Connection drops in the middle.
      await a.close();
      await waitFor(() => b.state.isOver);
      tb.sessionEnded(b);
      ta.sessionEnded(a);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(rb.tasks.first.status, TaskStatus.failed);
      expect(recB.single.status, RecordStatus.failed);
      expect(inbox.listSync(recursive: true).whereType<File>(), isEmpty,
          reason: 'partial .jppart must be removed');

      ta.dispose();
      tb.dispose();
      tmp.deleteSync(recursive: true);
    });
  });

  testWidgets('wrong password is refused', (tester) async {
    await tester.runAsync(() async {
      final (a, b) = await connectPair(pwA: 'dogru-parola', pwB: 'yanlis');
      await waitFor(() => a.state.isOver || b.state.isOver);
      await waitFor(() => a.state.isOver && b.state.isOver || a.state == SessionState.failed || b.state == SessionState.failed,
          timeout: const Duration(seconds: 10));
      expect(a.state.isLive || b.state.isLive, isFalse);
      debugPrint('refused: A=${a.error} | B=${b.error}');
      await a.close();
      await b.close();
    });
  });
}
