/// Cryptographic building blocks for JinjaPeer.
///
/// Trust model
/// -----------
/// * Every installation owns a long term **Ed25519 identity** key. It signs
///   each connection code, so a code cannot be altered without detection and
///   a saved contact is recognised (and verified) on every later connection.
/// * Every connection uses fresh **X25519 ephemeral keys** (forward secrecy).
///   The two public halves travel inside the codes the users exchange.
/// * Session keys = HKDF-SHA256(X25519 secret [+ PBKDF2(password)],
///   salt = SHA-256(offer code body ‖ answer code body)). Separate keys per
///   direction; every frame is sealed with ChaCha20-Poly1305 using a strictly
///   increasing counter as nonce (replay / reorder / tamper ⇒ connection drop).
/// * WebRTC's own DTLS encryption sits underneath as a second, independent
///   layer. Data never touches any server.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final _ed25519 = Ed25519();
final _x25519 = X25519();
final _sha256 = Sha256();

Uint8List randomBytes(int length) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(length, (_) => r.nextInt(256)));
}

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List unb64(String s) {
  final pad = (4 - s.length % 4) % 4;
  return Uint8List.fromList(base64Url.decode(s + '=' * pad));
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<Uint8List> sha256(List<int> data) async =>
    Uint8List.fromList((await _sha256.hash(data)).bytes);

/// Crockford base32 (no I, L, O, U) – easy to read aloud.
const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String base32(List<int> bytes, int chars) {
  var bits = 0, value = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5 && out.length < chars) {
      out.write(_crockford[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
    value &= (1 << bits) - 1;
    if (out.length >= chars) break;
  }
  return out.toString();
}

String groupString(String s, int size, [String sep = ' ']) {
  final parts = <String>[];
  for (var i = 0; i < s.length; i += size) {
    parts.add(s.substring(i, min(i + size, s.length)));
  }
  return parts.join(sep);
}

/// Human readable fingerprint of an identity public key, e.g. "7K4Q 9XMP 2DHT R8VA".
Future<String> fingerprintOf(List<int> identityPublicKey) async {
  final h = await sha256(identityPublicKey);
  return groupString(base32(h, 16), 4);
}

/// Long-term identity of this installation.
class Identity {
  Identity._(this._keyPair, this.publicKey, this.fingerprint);

  final SimpleKeyPair _keyPair;
  final Uint8List publicKey;
  final String fingerprint;

  String get publicKeyB64 => b64(publicKey);

  static Future<Identity> fromSeed(List<int> seed) async {
    final kp = await _ed25519.newKeyPairFromSeed(seed);
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    return Identity._(kp, pub, await fingerprintOf(pub));
  }

  static Future<(Identity, Uint8List)> generate() async {
    final seed = randomBytes(32);
    return (await fromSeed(seed), seed);
  }

  Future<Uint8List> sign(List<int> message) async {
    final sig = await _ed25519.sign(message, keyPair: _keyPair);
    return Uint8List.fromList(sig.bytes);
  }
}

Future<bool> verifySignature(
    List<int> message, List<int> signature, List<int> publicKey) async {
  try {
    return await _ed25519.verify(
      message,
      signature: Signature(signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
  } catch (_) {
    return false;
  }
}

/// Fresh X25519 key pair used for exactly one connection.
class EphemeralKey {
  EphemeralKey._(this._kp, this.publicKey);
  final SimpleKeyPair _kp;
  final Uint8List publicKey;

  static Future<EphemeralKey> generate() async {
    final kp = await _x25519.newKeyPair();
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    return EphemeralKey._(kp, pub);
  }

  Future<Uint8List> agree(List<int> remotePublic) async {
    if (remotePublic.length != 32) {
      throw const FormatException('Geçersiz anahtar uzunluğu');
    }
    final secret = await _x25519.sharedSecretKey(
      keyPair: _kp,
      remotePublicKey: SimplePublicKey(remotePublic, type: KeyPairType.x25519),
    );
    final bytes = await secret.extractBytes();
    // Reject the all-zero result produced by low-order points.
    if (bytes.every((b) => b == 0)) {
      throw const FormatException('Güvensiz anahtar reddedildi');
    }
    return Uint8List.fromList(bytes);
  }
}

class SessionKeys {
  SessionKeys({
    required this.sendKey,
    required this.receiveKey,
    required this.verificationCode,
  });

  /// 32 byte ChaCha20-Poly1305 key for frames we send.
  final Uint8List sendKey;

  /// 32 byte key for frames we receive.
  final Uint8List receiveKey;

  /// 40-bit short authentication string, shown as "ABCD-EFGH" on both sides.
  final String verificationCode;
}

const _pbkdfIterations = 120000;

Future<Uint8List> _passwordKey(String password, Uint8List salt) {
  // PBKDF2 is CPU heavy – keep the UI fluid by running it in a worker.
  return Isolate.run(() async {
    final kdf = Pbkdf2(
        macAlgorithm: Hmac.sha256(), iterations: _pbkdfIterations, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: password, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  });
}

/// Derives directional session keys.
///
/// [offerBody] / [answerBody] are the exact signed JSON bodies of both codes,
/// binding the keys to everything both sides agreed on (SDP incl. DTLS
/// fingerprints, identities, ephemeral keys, session id).
Future<SessionKeys> deriveSessionKeys({
  required EphemeralKey mine,
  required Uint8List peerEphemeral,
  required String offerBody,
  required String answerBody,
  required Uint8List sessionId,
  required bool isOfferer,
  String? password,
}) async {
  final dh = await mine.agree(peerEphemeral);
  final transcript = await sha256([
    ...utf8.encode('JinjaPeer/1 transcript'),
    ...utf8.encode(offerBody),
    0,
    ...utf8.encode(answerBody),
  ]);
  final pw = (password != null && password.isNotEmpty)
      ? await _passwordKey(password, sessionId)
      : Uint8List(0);
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  final okm = await (await hkdf.deriveKey(
    secretKey: SecretKey([...dh, ...pw]),
    nonce: transcript,
    info: utf8.encode('JinjaPeer/1 session keys'),
  ))
      .extractBytes();
  final offerToAnswer = Uint8List.fromList(okm.sublist(0, 32));
  final answerToOffer = Uint8List.fromList(okm.sublist(32, 64));

  final sasHkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 8);
  final sasBytes = await (await sasHkdf.deriveKey(
    secretKey: SecretKey(dh),
    nonce: transcript,
    info: utf8.encode('JinjaPeer/1 verification'),
  ))
      .extractBytes();
  final sas = base32(sasBytes, 8);

  return SessionKeys(
    sendKey: isOfferer ? offerToAnswer : answerToOffer,
    receiveKey: isOfferer ? answerToOffer : offerToAnswer,
    verificationCode: '${sas.substring(0, 4)}-${sas.substring(4)}',
  );
}
