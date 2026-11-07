/// One direct peer-to-peer connection.
///
/// Signalling is done by hand: the inviter produces an invite code, the joiner
/// pastes it and produces an answer code, the inviter pastes that back.
/// After that the two computers talk directly (WebRTC data channel, NAT
/// traversal via public STUN only – no file data ever touches a server).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/codes.dart';
import '../core/crypto.dart';
import '../core/secure_channel.dart';
import '../core/sanitize.dart';

enum SessionRole { inviter, joiner }

enum SessionState {
  preparing, // gathering network candidates
  waitingForAnswer, // inviter: show invite code, wait for answer code
  waitingForPeer, // joiner: show answer code, wait for inviter to paste it
  connecting, // ICE / DTLS in progress
  securing, // encrypted handshake
  connected,
  failed,
  closed,
}

extension SessionStateX on SessionState {
  bool get isLive => this == SessionState.connected;
  bool get isOver => this == SessionState.failed || this == SessionState.closed;
  String get label => switch (this) {
        SessionState.preparing => 'Hazırlanıyor',
        SessionState.waitingForAnswer => 'Yanıt kodu bekleniyor',
        SessionState.waitingForPeer => 'Karşı taraf bekleniyor',
        SessionState.connecting => 'Bağlanıyor',
        SessionState.securing => 'Şifreleme doğrulanıyor',
        SessionState.connected => 'Bağlı',
        SessionState.failed => 'Başarısız',
        SessionState.closed => 'Kapandı',
      };
}

typedef ControlHandler = Future<void> Function(PeerSession s, Map<String, dynamic> msg);
typedef ChunkHandler = Future<void> Function(
    PeerSession s, String fileIdHex, int offset, Uint8List data);

/// Largest encrypted frame we accept (128 KiB chunk + headers + margin).
const int kMaxFrameBytes = 160 * 1024;

class PeerSession extends ChangeNotifier {
  PeerSession._({
    required this.id,
    required this.role,
    required this.identity,
    required this.myName,
    required this.iceServers,
  });

  static const _channelLabel = 'jinjapeer';
  static const _highWater = 8 * 1024 * 1024;
  static const _lowWater = 2 * 1024 * 1024;

  final String id;
  final SessionRole role;
  final Identity identity;
  final String myName;
  final List<Map<String, dynamic>> iceServers;
  final createdAt = DateTime.now();

  SessionState _state = SessionState.preparing;
  SessionState get state => _state;
  String? error;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  SecureChannel? _channel;
  EphemeralKey? _eph;
  Uint8List? _sessionId;
  String? _password;

  ConnectionCode? myCode;
  ConnectionCode? peerCode;

  String peerName = '';
  String? peerFingerprint;
  Uint8List? get peerIdentityKey => peerCode?.identityKey;
  String get peerKeyB64 => peerCode == null ? '' : b64(peerCode!.identityKey);
  String? verificationCode;
  DateTime? connectedAt;
  int? rttMs;
  String? routeInfo; // "Doğrudan (yerel ağ)" etc.

  ControlHandler? onControl;
  ChunkHandler? onChunk;
  VoidCallback? onConnected;
  VoidCallback? onEnded;

  Future<void> _sendTail = Future.value();
  Future<void> _recvTail = Future.value();
  Timer? _pingTimer;
  Timer? _handshakeTimer;
  DateTime? _lastPong;
  bool _helloSent = false;
  bool _helloReceived = false;
  int _sinceBufferCheck = 0;

  int bytesOut = 0;
  int bytesIn = 0;

  void _set(SessionState s, {String? err}) {
    if (_state.isOver) return;
    _state = s;
    if (err != null) error = err;
    notifyListeners();
    if (s.isOver) {
      _teardown();
      onEnded?.call();
    }
  }

  // ---------------------------------------------------------------------------
  // Creation
  // ---------------------------------------------------------------------------

  /// Inviter side: produce an invite code.
  static Future<PeerSession> createInvite({
    required Identity identity,
    required String myName,
    required List<Map<String, dynamic>> iceServers,
    required Duration validity,
    String? password,
  }) async {
    final s = PeerSession._(
      id: hex(randomBytes(8)),
      role: SessionRole.inviter,
      identity: identity,
      myName: myName,
      iceServers: iceServers,
    );
    s._password = password;
    try {
      s._sessionId = randomBytes(16);
      s._eph = await EphemeralKey.generate();
      await s._createPc();
      final dc = await s._pc!.createDataChannel(
          _channelLabel, RTCDataChannelInit()..ordered = true);
      s._attachChannel(dc);
      final offer = await s._pc!.createOffer({});
      await s._pc!.setLocalDescription(offer);
      final sdp = await s._gatheredSdp();
      s.myCode = await ConnectionCode.create(
        kind: CodeKind.invite,
        identity: identity,
        sessionId: s._sessionId!,
        sdp: sdp,
        ephemeralKey: s._eph!.publicKey,
        name: myName,
        validity: validity,
        passwordRequired: password != null && password.isNotEmpty,
      );
      s._set(SessionState.waitingForAnswer);
    } catch (e) {
      s._set(SessionState.failed, err: 'Davet oluşturulamadı: $e');
    }
    return s;
  }

  /// Joiner side: accept an invite code and produce the answer code.
  static Future<PeerSession> acceptInvite({
    required Identity identity,
    required String myName,
    required List<Map<String, dynamic>> iceServers,
    required ConnectionCode invite,
    String? password,
  }) async {
    final s = PeerSession._(
      id: hex(randomBytes(8)),
      role: SessionRole.joiner,
      identity: identity,
      myName: myName,
      iceServers: iceServers,
    );
    s._password = password;
    s.peerCode = invite;
    s.peerName = invite.name;
    s.peerFingerprint = await fingerprintOf(invite.identityKey);
    try {
      if (b64(invite.identityKey) == identity.publicKeyB64) {
        throw const CodeException('Bu kodu sen oluşturdun. Kodu karşı tarafa göndermelisin.');
      }
      s._sessionId = invite.sessionId;
      s._eph = await EphemeralKey.generate();
      await s._createPc();
      s._pc!.onDataChannel = (dc) {
        if (dc.label == _channelLabel && s._dc == null) {
          s._attachChannel(dc);
        } else {
          dc.close();
        }
      };
      await s._pc!.setRemoteDescription(RTCSessionDescription(invite.sdp, 'offer'));
      final answer = await s._pc!.createAnswer({});
      await s._pc!.setLocalDescription(answer);
      final sdp = await s._gatheredSdp();
      s.myCode = await ConnectionCode.create(
        kind: CodeKind.answer,
        identity: identity,
        sessionId: s._sessionId!,
        sdp: sdp,
        ephemeralKey: s._eph!.publicKey,
        name: myName,
        validity: const Duration(minutes: 10),
      );
      await s._deriveKeys();
      s._set(SessionState.waitingForPeer);
    } on CodeException catch (e) {
      s._set(SessionState.failed, err: e.message);
    } catch (e) {
      s._set(SessionState.failed, err: 'Bağlantı hazırlanamadı: $e');
    }
    return s;
  }

  /// Inviter side: apply the answer code pasted by the user.
  Future<void> applyAnswer(ConnectionCode answer) async {
    if (role != SessionRole.inviter || _state != SessionState.waitingForAnswer) {
      throw const CodeException('Bu bağlantı yanıt kodu beklemiyor.');
    }
    if (myCode!.isExpired) {
      throw const CodeException('Davet kodunun süresi doldu. Yeni bir davet oluştur.');
    }
    if (!listEquals(answer.sessionId, _sessionId)) {
      throw const CodeException(
          'Bu yanıt kodu başka bir davete ait. Karşı tarafın SENİN davetine verdiği yanıtı yapıştır.');
    }
    if (b64(answer.identityKey) == identity.publicKeyB64) {
      throw const CodeException('Kendi kodunu yapıştırdın. Karşı tarafın yanıt kodunu yapıştır.');
    }
    peerCode = answer;
    peerName = answer.name;
    peerFingerprint = await fingerprintOf(answer.identityKey);
    await _deriveKeys();
    _set(SessionState.connecting);
    await _pc!.setRemoteDescription(RTCSessionDescription(answer.sdp, 'answer'));
    _armHandshakeTimeout();
  }

  /// A session that looks connected but has no network underneath. Control
  /// messages it "sends" are collected in [testSent]. Tests only.
  @visibleForTesting
  static Future<PeerSession> fakeConnected({
    required Identity me,
    required Identity peer,
    required String peerName,
  }) async {
    final s = PeerSession._(
      id: hex(randomBytes(8)),
      role: SessionRole.inviter,
      identity: me,
      myName: 'Ben',
      iceServers: const [],
    );
    s.peerCode = await ConnectionCode.create(
      kind: CodeKind.answer,
      identity: peer,
      sessionId: randomBytes(16),
      sdp: 'v=0',
      ephemeralKey: randomBytes(32),
      name: peerName,
      validity: const Duration(minutes: 5),
    );
    s.peerName = peerName;
    s.peerFingerprint = peer.fingerprint;
    s.verificationCode = 'TEST-K0D1';
    s.routeInfo = 'Doğrudan · yerel ağ';
    s.rttMs = 12;
    s.connectedAt = DateTime.now();
    s.testSent = [];
    s._state = SessionState.connected;
    return s;
  }

  @visibleForTesting
  List<Map<String, dynamic>>? testSent;

  // ---------------------------------------------------------------------------
  // WebRTC plumbing
  // ---------------------------------------------------------------------------

  Future<void> _createPc() async {
    _pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 2,
    });
    _pc!.onConnectionState = (st) {
      switch (st) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          if (_state == SessionState.waitingForPeer) _set(SessionState.connecting);
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          if (_state.index < SessionState.securing.index) {
            _set(SessionState.securing);
          }
          _detectRoute();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _set(SessionState.failed,
              err: _state == SessionState.connected
                  ? 'Bağlantı koptu.'
                  : 'Doğrudan bağlantı kurulamadı. İki ağ da çok kısıtlı olabilir (simetrik NAT). '
                      'Ayarlar > Ağ bölümünden kendi TURN sunucunu ekleyebilirsin.');
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _set(SessionState.closed);
        default:
      }
    };
  }

  Future<String> _gatheredSdp() async {
    final done = Completer<void>();
    _pc!.onIceGatheringState = (st) {
      if (st == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) {
        done.complete();
      }
    };
    // Some networks never report "complete"; candidates collected so far are fine.
    await done.future.timeout(const Duration(seconds: 6), onTimeout: () {});
    final desc = await _pc!.getLocalDescription();
    if (desc?.sdp == null) throw StateError('Yerel bağlantı bilgisi alınamadı');
    return _compactSdp(desc!.sdp!);
  }

  /// Removes lines that are irrelevant for a data-only session to keep codes short.
  String _compactSdp(String sdp) {
    final lines = sdp.split(RegExp(r'\r?\n')).where((l) {
      if (l.isEmpty) return false;
      if (l.startsWith('a=extmap')) return false;
      if (l.startsWith('a=candidate') && l.contains(' tcp ')) return false;
      return true;
    });
    return '${lines.join('\r\n')}\r\n';
  }

  Future<void> _detectRoute() async {
    try {
      final stats = await _pc!.getStats();
      String? localType, remoteType, selectedPair;
      final candidates = <String, Map<dynamic, dynamic>>{};
      for (final r in stats) {
        if (r.type == 'transport' && r.values['selectedCandidatePairId'] != null) {
          selectedPair = r.values['selectedCandidatePairId'] as String;
        }
        if (r.type == 'local-candidate' || r.type == 'remote-candidate') {
          candidates[r.id] = r.values;
        }
      }
      for (final r in stats) {
        final isSelected = selectedPair != null
            ? r.id == selectedPair
            : (r.type == 'candidate-pair' &&
                (r.values['nominated'] == true) &&
                r.values['state'] == 'succeeded');
        if (r.type == 'candidate-pair' && isSelected) {
          localType = candidates[r.values['localCandidateId']]?['candidateType'] as String?;
          remoteType = candidates[r.values['remoteCandidateId']]?['candidateType'] as String?;
        }
      }
      if (localType == 'relay' || remoteType == 'relay') {
        routeInfo = 'TURN aktarıcısı üzerinden';
      } else if (localType == 'host' && remoteType == 'host') {
        routeInfo = 'Doğrudan · yerel ağ';
      } else if (localType != null) {
        routeInfo = 'Doğrudan · internet (P2P)';
      }
      notifyListeners();
    } catch (_) {}
  }

  void _attachChannel(RTCDataChannel dc) {
    _dc = dc;
    dc.bufferedAmountLowThreshold = _lowWater;
    dc.onDataChannelState = (st) {
      if (st == RTCDataChannelState.RTCDataChannelOpen) {
        if (_state.index < SessionState.securing.index) _set(SessionState.securing);
        _sendHello();
      } else if (st == RTCDataChannelState.RTCDataChannelClosed) {
        if (_state == SessionState.connected) {
          _set(SessionState.closed, err: 'Karşı taraf bağlantıyı kapattı.');
        } else if (!_state.isOver) {
          _set(SessionState.failed, err: 'Veri kanalı kapandı.');
        }
      }
    };
    dc.onMessage = (m) {
      if (!m.isBinary) return; // only encrypted binary frames are accepted
      final data = m.binary;
      bytesIn += data.length;
      if (data.length > kMaxFrameBytes) {
        _set(SessionState.failed, err: 'Güvenlik ihlali: beklenenden büyük paket alındı. Bağlantı kesildi.');
        return;
      }
      final ch = _channel;
      if (ch == null || _state.isOver) return;
      // Decryption starts right away (the worker keeps strict order);
      // results are handled one after another.
      final opened = ch.open(data);
      opened.ignore();
      _recvTail = _recvTail.then((_) => _handleFrame(opened));
    };
  }

  Future<void> _deriveKeys() async {
    final offer = role == SessionRole.inviter ? myCode! : peerCode!;
    final answer = role == SessionRole.inviter ? peerCode! : myCode!;
    final keys = await deriveSessionKeys(
      mine: _eph!,
      peerEphemeral: peerCode!.ephemeralKey,
      offerBody: offer.body,
      answerBody: answer.body,
      sessionId: _sessionId!,
      isOfferer: role == SessionRole.inviter,
      password: _password,
    );
    verificationCode = keys.verificationCode;
    _channel = await SecureChannel.start(keys.sendKey, keys.receiveKey);
    _password = null;
  }

  void _armHandshakeTimeout() {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(const Duration(seconds: 45), () {
      if (_state != SessionState.connected && !_state.isOver) {
        _set(SessionState.failed,
            err: 'Bağlantı zaman aşımına uğradı. İki taraf da uygulamayı açık tutmalı '
                've kodlar 45 saniye içinde girilmeli.');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Secure messaging
  // ---------------------------------------------------------------------------

  void _sendHello() {
    if (_helloSent || _channel == null) return;
    _helloSent = true;
    if (role == SessionRole.joiner) _armHandshakeTimeout();
    sendControl({'t': 'hello', 'v': 1, 'name': myName, 'app': 'JinjaPeer'});
  }

  Future<void> _handleFrame(Future<Uint8List> opened) async {
    if (_state.isOver) return;
    final Uint8List plain;
    try {
      plain = await opened;
    } catch (e) {
      if (_state.isOver) return;
      _set(SessionState.failed,
          err: _helloReceived
              ? 'Güvenlik ihlali: bozuk ya da değiştirilmiş veri alındı ($e). Bağlantı kesildi.'
              : 'Şifreli el sıkışma başarısız. Bağlantı şifresi yanlış olabilir ya da kodlar eşleşmiyor.');
      return;
    }
    if (plain.isEmpty) return;
    if (plain[0] == kTypeControl) {
      if (plain.length > 2 * 1024 * 1024) return;
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(utf8.decode(Uint8List.sublistView(plain, 1))) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      await _onControl(msg);
    } else if (plain[0] == kTypeChunk && plain.length >= kChunkHeader) {
      if (!_helloReceived) return;
      final fid = hex(Uint8List.sublistView(plain, 1, 17));
      final offset = ByteData.sublistView(plain).getUint64(17);
      final data = Uint8List.sublistView(plain, kChunkHeader);
      await onChunk?.call(this, fid, offset, data);
    }
  }

  Future<void> _onControl(Map<String, dynamic> msg) async {
    final t = msg['t'];
    if (t == 'hello') {
      if (_helloReceived) return;
      _helloReceived = true;
      _handshakeTimer?.cancel();
      _sendHello();
      connectedAt = DateTime.now();
      _set(SessionState.connected);
      _startPing();
      onConnected?.call();
      return;
    }
    if (!_helloReceived) return;
    switch (t) {
      case 'ping':
        sendControl({'t': 'pong', 'ts': msg['ts']});
      case 'pong':
        _lastPong = DateTime.now();
        final ts = msg['ts'];
        if (ts is int) {
          rttMs = DateTime.now().millisecondsSinceEpoch - ts;
          notifyListeners();
        }
      case 'bye':
        _set(SessionState.closed, err: 'Karşı taraf bağlantıyı sonlandırdı.');
      default:
        try {
          await onControl?.call(this, msg);
        } catch (e) {
          debugPrint('control handler error: $e');
        }
    }
  }

  void _startPing() {
    _lastPong = DateTime.now();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_state != SessionState.connected) return;
      if (DateTime.now().difference(_lastPong!) > const Duration(seconds: 40)) {
        _set(SessionState.failed, err: 'Karşı taraftan yanıt alınamıyor, bağlantı koptu.');
        return;
      }
      sendControl({'t': 'ping', 'ts': DateTime.now().millisecondsSinceEpoch});
    });
  }

  Future<void> sendControl(Map<String, dynamic> msg) {
    if (testSent != null) {
      if (_state.isOver) return Future.error(StateError('Bağlantı yok'));
      testSent!.add(msg);
      return Future.value();
    }
    final body = utf8.encode(jsonEncode(msg));
    final plain = Uint8List(body.length + 1)
      ..[0] = kTypeControl
      ..setRange(1, body.length + 1, body);
    return _enqueue(plain);
  }

  /// Sends one file chunk. Completes once the frame is queued on the channel;
  /// applies back-pressure so memory stays bounded.
  Future<void> sendChunk(Uint8List fileId, int offset, Uint8List data) {
    final plain = Uint8List(kChunkHeader + data.length);
    plain[0] = kTypeChunk;
    plain.setRange(1, 17, fileId);
    ByteData.sublistView(plain).setUint64(17, offset);
    plain.setRange(kChunkHeader, plain.length, data);
    return _enqueue(plain, isChunk: true);
  }

  Future<String> takeFileHash(String fileIdHex) =>
      _channel?.takeFileHash(fileIdHex) ?? Future.value('');

  void dropFileHash(String fileIdHex) => _channel?.dropFileHash(fileIdHex);

  Future<void> _enqueue(Uint8List plain, {bool isChunk = false}) {
    final c = Completer<void>();
    final ch = _channel;
    if (ch == null || _state.isOver) {
      return Future.error(StateError('Bağlantı yok'));
    }
    // Encryption starts immediately (nonce order == call order inside the
    // worker); frames leave the socket strictly in the same order.
    final sealed = ch.seal(plain);
    sealed.ignore();
    _sendTail = _sendTail.then((_) async {
      try {
        final dc = _dc;
        if (dc == null || _state.isOver) {
          throw StateError('Bağlantı yok');
        }
        final frame = await sealed;
        await dc.send(RTCDataChannelMessage.fromBinary(frame));
        bytesOut += frame.length;
        if (isChunk && ++_sinceBufferCheck >= 8) {
          _sinceBufferCheck = 0;
          var buffered = await dc.getBufferedAmount();
          if (buffered > _highWater) {
            while (buffered > _lowWater && !_state.isOver) {
              await Future<void>.delayed(const Duration(milliseconds: 15));
              buffered = await dc.getBufferedAmount();
            }
          }
        }
        c.complete();
      } catch (e) {
        if (!c.isCompleted) c.completeError(e);
      }
    });
    return c.future;
  }

  // ---------------------------------------------------------------------------
  // Shutdown
  // ---------------------------------------------------------------------------

  Future<void> close({String? reason}) async {
    if (_state.isOver) return;
    if (_state == SessionState.connected) {
      try {
        await sendControl({'t': 'bye'}).timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
    _set(SessionState.closed, err: reason);
  }

  void _teardown() {
    _pingTimer?.cancel();
    _handshakeTimer?.cancel();
    final dc = _dc, pc = _pc, ch = _channel;
    _dc = null;
    _pc = null;
    _channel = null;
    Future(() async {
      try {
        await dc?.close();
      } catch (_) {}
      try {
        await pc?.close();
        await pc?.dispose();
      } catch (_) {}
      ch?.dispose();
    });
  }

  String get displayName => sanitizeDisplayName(peerName.isEmpty ? null : peerName);
}
