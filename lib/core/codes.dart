/// Connection codes – the only thing users exchange to connect.
///
/// An **invite** code (from the inviter) and an **answer** code (from the
/// joiner) each carry a WebRTC session description, a fresh X25519 public
/// key and the sender's identity key. The body is signed with the identity
/// key, gzip-compressed and base64url encoded:
///
/// `JP1I-base64url(gzip(json))` for invites and `JP1A-...` for answers.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crypto.dart';
import 'sanitize.dart';

enum CodeKind { invite, answer }

class CodeException implements Exception {
  const CodeException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _invitePrefix = 'JP1I-';
const _answerPrefix = 'JP1A-';
const _maxEncodedLength = 24 * 1024;
const _maxDecodedLength = 96 * 1024;

class ConnectionCode {
  ConnectionCode({
    required this.kind,
    required this.sessionId,
    required this.sdp,
    required this.ephemeralKey,
    required this.identityKey,
    required this.name,
    required this.expiresAt,
    required this.passwordRequired,
    required this.body,
    required this.encoded,
  });

  final CodeKind kind;
  final Uint8List sessionId;
  final String sdp;
  final Uint8List ephemeralKey;
  final Uint8List identityKey;
  final String name;
  final DateTime expiresAt;
  final bool passwordRequired;

  /// Exact signed JSON body – used for key derivation transcript.
  final String body;

  /// Full shareable text.
  final String encoded;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get remaining => expiresAt.difference(DateTime.now());

  static Future<ConnectionCode> create({
    required CodeKind kind,
    required Identity identity,
    required Uint8List sessionId,
    required String sdp,
    required Uint8List ephemeralKey,
    required String name,
    required Duration validity,
    bool passwordRequired = false,
  }) async {
    final expiresAt = DateTime.now().add(validity);
    final body = jsonEncode({
      'app': 'JinjaPeer',
      'v': 1,
      'k': kind == CodeKind.invite ? 'i' : 'a',
      'sid': b64(sessionId),
      'sdp': sdp,
      'ek': b64(ephemeralKey),
      'ik': identity.publicKeyB64,
      'n': name,
      'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
      'pw': passwordRequired,
    });
    final sig = await identity.sign(utf8.encode(body));
    final wrapped = utf8.encode(jsonEncode({'b': body, 's': b64(sig)}));
    final gz = GZipCodec(level: 9).encode(wrapped);
    final prefix = kind == CodeKind.invite ? _invitePrefix : _answerPrefix;
    return ConnectionCode(
      kind: kind,
      sessionId: sessionId,
      sdp: sdp,
      ephemeralKey: ephemeralKey,
      identityKey: identity.publicKey,
      name: name,
      expiresAt: expiresAt,
      passwordRequired: passwordRequired,
      body: body,
      encoded: '$prefix${b64(gz)}',
    );
  }

  /// Quick check used by the UI while typing/pasting.
  static CodeKind? sniff(String text) {
    final t = _normalize(text);
    if (t.startsWith(_invitePrefix)) return CodeKind.invite;
    if (t.startsWith(_answerPrefix)) return CodeKind.answer;
    return null;
  }

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').replaceAll('"', '').replaceAll('`', '');

  /// Parses and fully verifies a code. Throws [CodeException] with a
  /// user-facing Turkish message on any problem.
  static Future<ConnectionCode> parse(String text, {CodeKind? expect}) async {
    final t = _normalize(text);
    if (t.isEmpty) throw const CodeException('Kod boş.');
    final CodeKind kind;
    if (t.startsWith(_invitePrefix)) {
      kind = CodeKind.invite;
    } else if (t.startsWith(_answerPrefix)) {
      kind = CodeKind.answer;
    } else {
      throw const CodeException(
          'Bu bir JinjaPeer kodu değil. Kod "JP1I-" ya da "JP1A-" ile başlamalı.');
    }
    if (expect != null && kind != expect) {
      throw CodeException(expect == CodeKind.invite
          ? 'Bu bir yanıt kodu. Burada karşı tarafın davet kodunu (JP1I-…) yapıştırmalısın.'
          : 'Bu bir davet kodu. Burada karşı tarafın yanıt kodunu (JP1A-…) yapıştırmalısın.');
    }
    if (t.length > _maxEncodedLength) {
      throw const CodeException('Kod beklenenden çok uzun.');
    }

    final Map<String, dynamic> wrapper;
    final Map<String, dynamic> map;
    final String body;
    try {
      final gz = unb64(t.substring(5));
      final raw = _boundedGunzip(gz);
      wrapper = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      body = wrapper['b'] as String;
      map = jsonDecode(body) as Map<String, dynamic>;
    } on CodeException {
      rethrow;
    } catch (_) {
      throw const CodeException(
          'Kod bozuk ya da eksik kopyalanmış. Kodun tamamını kopyaladığından emin ol.');
    }

    if (map['app'] != 'JinjaPeer' || map['v'] != 1) {
      throw const CodeException('Bu kod uygulamanın farklı bir sürümüne ait.');
    }
    if ((map['k'] == 'i') != (kind == CodeKind.invite)) {
      throw const CodeException('Kod türü tutarsız.');
    }

    try {
      final sid = unb64(map['sid'] as String);
      final ek = unb64(map['ek'] as String);
      final ik = unb64(map['ik'] as String);
      final sig = unb64(wrapper['s'] as String);
      final sdp = map['sdp'] as String;
      if (sid.length != 16 || ek.length != 32 || ik.length != 32 || sig.length != 64) {
        throw const FormatException();
      }
      if (sdp.length > 60000 || !sdp.startsWith('v=0')) {
        throw const FormatException();
      }
      final ok = await verifySignature(utf8.encode(body), sig, ik);
      if (!ok) {
        throw const CodeException(
            'Kodun imzası doğrulanamadı. Kod değiştirilmiş olabilir — güvenliğin için reddedildi.');
      }
      final exp = DateTime.fromMillisecondsSinceEpoch((map['exp'] as int) * 1000);
      if (DateTime.now().isAfter(exp)) {
        throw const CodeException(
            'Bu kodun süresi dolmuş. Karşı taraftan yeni bir kod iste.');
      }
      if (exp.difference(DateTime.now()) > const Duration(hours: 25)) {
        throw const CodeException('Kodun geçerlilik süresi geçersiz.');
      }
      return ConnectionCode(
        kind: kind,
        sessionId: sid,
        sdp: sdp,
        ephemeralKey: ek,
        identityKey: ik,
        name: sanitizeDisplayName(map['n'] as String?),
        expiresAt: exp,
        passwordRequired: map['pw'] == true,
        body: body,
        encoded: t,
      );
    } on CodeException {
      rethrow;
    } catch (_) {
      throw const CodeException('Kodun içeriği geçersiz.');
    }
  }
}

/// gunzip with a hard output limit (protects against "zip bombs").
List<int> _boundedGunzip(List<int> data) {
  final out = BytesBuilder(copy: false);
  final sink = _LimitSink(out, _maxDecodedLength);
  final conv = gzip.decoder.startChunkedConversion(sink);
  conv.add(data);
  conv.close();
  return out.takeBytes();
}

class _LimitSink implements Sink<List<int>> {
  _LimitSink(this.out, this.limit);
  final BytesBuilder out;
  final int limit;
  @override
  void add(List<int> data) {
    if (out.length + data.length > limit) {
      throw const CodeException('Kod çok büyük veriler içeriyor.');
    }
    out.add(data);
  }

  @override
  void close() {}
}
