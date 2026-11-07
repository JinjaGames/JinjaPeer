/// Authenticated encryption of every frame, done in a background isolate so
/// the UI stays fluid at full transfer speed.
///
/// Wire frame:  [8 byte big-endian counter][ChaCha20 ciphertext][16 byte Poly1305 tag]
/// Nonce:       4 zero bytes ‖ counter   (unique per key, keys differ per direction)
///
/// The receiver only accepts the *exact next* counter value, so replayed,
/// dropped, reordered or modified frames are detected immediately.
///
/// Plaintext frames start with a type byte:
///   0x01 control message (UTF-8 JSON)
///   0x02 file chunk: [16 byte file id][8 byte offset][data]
/// File chunks are SHA-256 hashed inside the worker on both sides so the
/// receiver can verify every file end-to-end without a second pass.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const int kTypeControl = 0x01;
const int kTypeChunk = 0x02;
const int kChunkHeader = 1 + 16 + 8;

class FrameException implements Exception {
  FrameException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SecureChannel {
  SecureChannel._(this._isolate, this._send, this._receive);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _receive;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  var _closed = false;

  static Future<SecureChannel> start(Uint8List sendKey, Uint8List receiveKey) async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    final isolate = await Isolate.spawn(
      _workerMain,
      [receive.sendPort, sendKey, receiveKey],
      debugName: 'jp-crypto',
      errorsAreFatal: false,
    );
    late SecureChannel channel;
    receive.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      if (msg is List && msg.isNotEmpty) {
        final c = channel._pending.remove(msg[0] as int);
        if (c == null) return;
        if (msg.length > 2 && msg[2] != null) {
          c.completeError(FrameException(msg[2] as String));
        } else {
          c.complete(msg[1]);
        }
      }
    });
    final port = await ready.future;
    channel = SecureChannel._(isolate, port, receive);
    return channel;
  }

  Future<Object?> _call(String op, Object? arg) {
    if (_closed) return Future.error(FrameException('Kanal kapalı'));
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send.send([op, id, arg]);
    return c.future;
  }

  Future<Uint8List> seal(Uint8List plaintext) async =>
      (await _call('seal', plaintext)) as Uint8List;

  Future<Uint8List> open(Uint8List frame) async =>
      (await _call('open', frame)) as Uint8List;

  /// Returns the hex SHA-256 of all chunk payloads seen for [fileIdHex]
  /// (sent or received) and forgets the running hash.
  Future<String> takeFileHash(String fileIdHex) async =>
      (await _call('hash', fileIdHex)) as String;

  void dropFileHash(String fileIdHex) {
    if (!_closed) _send.send(['drop', -1, fileIdHex]);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(FrameException('Kanal kapatıldı'));
    }
    _pending.clear();
    _receive.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

String _hexOf(List<int> bytes, int start, int end) {
  final sb = StringBuffer();
  for (var i = start; i < end; i++) {
    sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Future<void> _workerMain(List<Object?> args) async {
  final reply = args[0] as SendPort;
  final aead = DartChacha20.poly1305Aead();
  final sendKey = SecretKey(args[1] as Uint8List);
  final recvKey = SecretKey(args[2] as Uint8List);
  var sendCounter = 0;
  var recvCounter = 0;
  final hashes = <String, HashSink>{};
  var poisoned = false;

  Uint8List nonceFor(int counter) {
    final n = Uint8List(12);
    ByteData.sublistView(n).setUint64(4, counter);
    return n;
  }

  void hashChunk(Uint8List plain) {
    if (plain.length < kChunkHeader || plain[0] != kTypeChunk) return;
    final fid = _hexOf(plain, 1, 17);
    final sink = hashes.putIfAbsent(fid, () => const DartSha256().newHashSink());
    sink.add(Uint8List.sublistView(plain, kChunkHeader));
  }

  final port = ReceivePort();
  reply.send(port.sendPort);

  Future<void> tail = Future.value();
  port.listen((msg) {
    final m = msg as List;
    final op = m[0] as String;
    final id = m[1] as int;
    tail = tail.then((_) async {
      try {
        switch (op) {
          case 'seal':
            final plain = m[2] as Uint8List;
            hashChunk(plain);
            final counter = sendCounter++;
            final box = await aead.encrypt(plain,
                secretKey: sendKey, nonce: nonceFor(counter));
            final out = Uint8List(8 + box.cipherText.length + 16);
            ByteData.sublistView(out).setUint64(0, counter);
            out.setRange(8, 8 + box.cipherText.length, box.cipherText);
            out.setRange(8 + box.cipherText.length, out.length, box.mac.bytes);
            reply.send([id, out]);
          case 'open':
            if (poisoned) throw FrameException('Kanal güvenliği bozuldu');
            final frame = m[2] as Uint8List;
            if (frame.length < 8 + 1 + 16) {
              poisoned = true;
              throw FrameException('Geçersiz çerçeve');
            }
            final counter = ByteData.sublistView(frame).getUint64(0);
            if (counter != recvCounter) {
              poisoned = true;
              throw FrameException('Sıra dışı / tekrar edilmiş çerçeve');
            }
            final box = SecretBox(
              Uint8List.sublistView(frame, 8, frame.length - 16),
              nonce: nonceFor(counter),
              mac: Mac(Uint8List.sublistView(frame, frame.length - 16)),
            );
            final List<int> plainList;
            try {
              plainList = await aead.decrypt(box, secretKey: recvKey);
            } on SecretBoxAuthenticationError {
              poisoned = true;
              throw FrameException('Kimlik doğrulama başarısız');
            }
            recvCounter++;
            final plain = plainList is Uint8List
                ? plainList
                : Uint8List.fromList(plainList);
            hashChunk(plain);
            reply.send([id, plain]);
          case 'hash':
            final fid = m[2] as String;
            final sink = hashes.remove(fid) ?? const DartSha256().newHashSink();
            sink.close();
            final h = await sink.hash();
            reply.send([id, _hexOf(h.bytes, 0, h.bytes.length)]);
          case 'drop':
            hashes.remove(m[2] as String);
        }
      } catch (e) {
        if (id >= 0) reply.send([id, null, e.toString()]);
      }
    });
  });
}
