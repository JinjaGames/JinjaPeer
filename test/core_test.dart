import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jinja_peer/core/codes.dart';
import 'package:jinja_peer/core/crypto.dart';
import 'package:jinja_peer/core/sanitize.dart';
import 'package:jinja_peer/core/secure_channel.dart';

const _sdp = 'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';

void main() {
  group('sanitize', () {
    test('blocks traversal and illegal names', () {
      expect(sanitizeFileName('../../etc/passwd'), isNot(contains('/')));
      expect(sanitizeFileName('..'), 'dosya');
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('a<b>:c?.txt'), 'a_b__c_.txt');
      expect(sanitizeFileName('evil.\u202Egnp.exe'), 'evil.gnp.exe');
      expect(sanitizeFileName('trail. . '), 'trail');
      expect(sanitizeRelativeDir(r'../a/./b/../c:\d'), ['a', 'b', 'd']);
      expect(sanitizeRelativeDir(r'C:\Windows\System32'), ['Windows', 'System32']);
      expect(isInside('/tmp/x', '/tmp/x/a/b.txt'), isTrue);
      expect(isInside('/tmp/x', '/tmp/x/../y.txt'), isFalse);
      expect(isRiskyFile('setup.EXE'), isTrue);
      expect(isRiskyFile('photo.jpg'), isFalse);
    });
  });

  group('codes', () {
    test('round trip, signature and tamper detection', () async {
      final (id, _) = await Identity.generate();
      final eph = await EphemeralKey.generate();
      final code = await ConnectionCode.create(
        kind: CodeKind.invite,
        identity: id,
        sessionId: randomBytes(16),
        sdp: _sdp,
        ephemeralKey: eph.publicKey,
        name: 'Ali',
        validity: const Duration(minutes: 5),
        passwordRequired: true,
      );
      final parsed = await ConnectionCode.parse('  ${code.encoded}\n', expect: CodeKind.invite);
      expect(parsed.name, 'Ali');
      expect(parsed.passwordRequired, isTrue);
      expect(parsed.body, code.body);

      await expectLater(ConnectionCode.parse(code.encoded, expect: CodeKind.answer), throwsA(isA<CodeException>()));
      final broken = '${code.encoded.substring(0, code.encoded.length - 6)}AAAAAA';
      await expectLater(ConnectionCode.parse(broken), throwsA(isA<CodeException>()));
      await expectLater(ConnectionCode.parse('merhaba'), throwsA(isA<CodeException>()));
    });

    test('expired code is rejected', () async {
      final (id, _) = await Identity.generate();
      final eph = await EphemeralKey.generate();
      final code = await ConnectionCode.create(
        kind: CodeKind.answer,
        identity: id,
        sessionId: randomBytes(16),
        sdp: _sdp,
        ephemeralKey: eph.publicKey,
        name: 'B',
        validity: const Duration(seconds: -1),
      );
      await expectLater(ConnectionCode.parse(code.encoded), throwsA(isA<CodeException>()));
    });
  });

  group('session crypto', () {
    Future<(SessionKeys, SessionKeys)> pair({String? pwA, String? pwB}) async {
      final a = await EphemeralKey.generate();
      final b = await EphemeralKey.generate();
      final sid = randomBytes(16);
      final ka = await deriveSessionKeys(
          mine: a, peerEphemeral: b.publicKey, offerBody: 'O', answerBody: 'A', sessionId: sid, isOfferer: true, password: pwA);
      final kb = await deriveSessionKeys(
          mine: b, peerEphemeral: a.publicKey, offerBody: 'O', answerBody: 'A', sessionId: sid, isOfferer: false, password: pwB);
      return (ka, kb);
    }

    test('keys match, SAS equal, frames verify', () async {
      final (ka, kb) = await pair();
      expect(ka.sendKey, kb.receiveKey);
      expect(ka.receiveKey, kb.sendKey);
      expect(ka.verificationCode, kb.verificationCode);
      expect(ka.verificationCode, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')));

      final ca = await SecureChannel.start(ka.sendKey, ka.receiveKey);
      final cb = await SecureChannel.start(kb.sendKey, kb.receiveKey);
      final msg = Uint8List.fromList([kTypeControl, ...utf8.encode('{"t":"hello"}')]);
      final f1 = await ca.seal(msg);
      expect(await cb.open(f1), msg);

      // chunk hashing on both sides
      final fid = randomBytes(16);
      final data = randomBytes(1000);
      final chunk = Uint8List(kChunkHeader + data.length)
        ..[0] = kTypeChunk
        ..setRange(1, 17, fid)
        ..setRange(kChunkHeader, kChunkHeader + data.length, data);
      final f2 = await ca.seal(chunk);
      await cb.open(f2);
      final expected = hex(await sha256(data));
      expect(await ca.takeFileHash(hex(fid)), expected);
      expect(await cb.takeFileHash(hex(fid)), expected);

      // replay is rejected and poisons the channel
      await expectLater(cb.open(f2), throwsA(isA<FrameException>()));
      ca.dispose();
      cb.dispose();
    });

    test('tampered frame is rejected', () async {
      final (ka, kb) = await pair();
      final ca = await SecureChannel.start(ka.sendKey, ka.receiveKey);
      final cb = await SecureChannel.start(kb.sendKey, kb.receiveKey);
      final f = await ca.seal(Uint8List.fromList([kTypeControl, 1, 2, 3]));
      f[10] ^= 0x01;
      await expectLater(cb.open(f), throwsA(isA<FrameException>()));
      ca.dispose();
      cb.dispose();
    });

    test('wrong password gives different keys', () async {
      final (ka, kb) = await pair(pwA: 'gizli123', pwB: 'yanlis');
      expect(ka.sendKey, isNot(kb.receiveKey));
      final (ka2, kb2) = await pair(pwA: 'gizli123', pwB: 'gizli123');
      expect(ka2.sendKey, kb2.receiveKey);
    });
  });
}
