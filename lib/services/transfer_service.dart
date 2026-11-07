/// File transfer protocol on top of an encrypted [PeerSession].
///
/// Control messages (all encrypted):
///   offer   {req, items:[{id,name,dir,size}], total}   sender → receiver
///   accept  {req}                                       receiver → sender
///   reject  {req, reason}                               receiver → sender
///   fend    {id, sha}                                   sender → receiver (after last chunk)
///   fdone   {id, ok, reason?}                           receiver → sender (after hash check)
///   cancel  {req, id?}                                  either side
///   pause / resume {req}                                either side
///
/// Receiver safety rules:
///   * nothing is written before the user (or a trusted-contact rule) accepts
///   * names / folders are sanitized, the final path must stay inside the
///     chosen download folder, existing files are never overwritten
///   * chunks must arrive exactly in order and never exceed the declared size
///   * data is written to "*.jppart" and only renamed after the SHA-256 of all
///     received bytes matches the sender's hash
///   * received files are never opened or executed automatically
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/crypto.dart';
import '../core/sanitize.dart';
import '../models/models.dart';
import 'peer_session.dart';

const int kChunkSize = 128 * 1024;
const int kChunksInFlight = 12;
const int kMaxItemsPerRequest = 10000;
const int kMaxPendingRequestsPerPeer = 5;

enum BatchStatus { pending, accepted, rejected, canceled, done, failed }

enum TaskStatus { queued, active, paused, verifying, done, failed, canceled }

extension TaskStatusX on TaskStatus {
  bool get isFinal =>
      this == TaskStatus.done || this == TaskStatus.failed || this == TaskStatus.canceled;
  String get label => switch (this) {
        TaskStatus.queued => 'Sırada',
        TaskStatus.active => 'Aktarılıyor',
        TaskStatus.paused => 'Duraklatıldı',
        TaskStatus.verifying => 'Doğrulanıyor',
        TaskStatus.done => 'Tamamlandı',
        TaskStatus.failed => 'Başarısız',
        TaskStatus.canceled => 'İptal edildi',
      };
}

/// Something the user wants to send.
class SendSource {
  SendSource({
    required this.name,
    required this.size,
    required this.open,
    this.relDir = '',
    this.path,
  });

  final String name;
  final int size;
  final String relDir;
  final String? path;
  final Stream<List<int>> Function() open;

  static SendSource fromFile(File f, {String relDir = ''}) {
    return SendSource(
      name: p.basename(f.path),
      size: f.lengthSync(),
      relDir: relDir,
      path: f.path,
      open: () => f.openRead(),
    );
  }
}

class FileTask {
  FileTask({
    required this.fileId,
    required this.batch,
    required this.name,
    required this.relDir,
    required this.size,
    this.source,
  });

  final Uint8List fileId;
  String get idHex => hex(fileId);
  final TransferBatch batch;
  final String name;
  final String relDir;
  final int size;
  final SendSource? source;

  TaskStatus status = TaskStatus.queued;
  int transferred = 0;
  double speed = 0;
  int _lastSampleBytes = 0;
  DateTime? startedAt;
  DateTime? finishedAt;
  String? path;
  String? sha256;
  String? error;

  // receiver internals
  RandomAccessFile? _raf;
  String? _partPath;

  TransferDirection get direction => batch.direction;
  double get progress => size == 0 ? (status == TaskStatus.done ? 1 : 0) : transferred / size;
  bool get risky => isRiskyFile(name);
}

class TransferBatch {
  TransferBatch({
    required this.reqId,
    required this.session,
    required this.direction,
    required this.peerName,
    required this.peerKey,
  });

  final String reqId;
  final PeerSession session;
  final TransferDirection direction;
  final String peerName;
  final String peerKey;
  final createdAt = DateTime.now();
  final List<FileTask> tasks = [];
  BatchStatus status = BatchStatus.pending;
  bool paused = false;
  bool pausedByPeer = false;
  String? reason;
  String? destination;
  bool autoAccepted = false;

  int get totalSize => tasks.fold(0, (a, t) => a + t.size);
  int get transferred => tasks.fold(0, (a, t) => a + t.transferred);
  double get speed => tasks.fold(0.0, (a, t) => a + (t.status == TaskStatus.active ? t.speed : 0));
  double get progress => totalSize == 0 ? 0 : transferred / totalSize;
  int get doneCount => tasks.where((t) => t.status == TaskStatus.done).length;
  bool get isFinished =>
      status == BatchStatus.rejected ||
      status == BatchStatus.canceled ||
      status == BatchStatus.failed ||
      status == BatchStatus.done;
  bool get hasRisky => tasks.any((t) => t.risky);
  String get title {
    if (tasks.isEmpty) return 'Boş istek';
    if (tasks.length == 1) return tasks.first.name;
    final folders = tasks.map((t) => t.relDir.split('/').first).toSet();
    if (folders.length == 1 && folders.first.isNotEmpty) {
      return '${folders.first} klasörü · ${tasks.length} dosya';
    }
    return '${tasks.first.name} ve ${tasks.length - 1} dosya daha';
  }
}

typedef RecordSink = void Function(TransferRecord r, FileTask? t);
typedef IncomingPolicy = Future<String?> Function(TransferBatch b);
typedef NoticeSink = void Function(String title, String body, {bool error});

class TransferService extends ChangeNotifier {
  TransferService({
    required this.onRecord,
    required this.notice,
    required this.autoAcceptDestination,
    required this.maxIncomingBytes,
  }) {
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  final RecordSink onRecord;
  final NoticeSink notice;

  /// Returns a destination folder if the batch may be accepted without asking.
  final IncomingPolicy autoAcceptDestination;
  final int Function() maxIncomingBytes;

  final List<TransferBatch> batches = [];
  final Map<String, FileTask> _tasksById = {};
  final Map<String, Future<void>> _sendQueues = {};
  late final Timer _ticker;
  bool _dirty = false;

  List<TransferBatch> get incomingPending => batches
      .where((b) => b.direction == TransferDirection.receive && b.status == BatchStatus.pending)
      .toList();
  List<TransferBatch> get outgoingPending => batches
      .where((b) => b.direction == TransferDirection.send && b.status == BatchStatus.pending)
      .toList();
  List<TransferBatch> get active =>
      batches.where((b) => b.status == BatchStatus.accepted).toList();
  Iterable<FileTask> get allTasks => batches.expand((b) => b.tasks);

  double get totalSpeed => active.fold(0.0, (a, b) => a + b.speed);

  List<TransferBatch> batchesFor(PeerSession s) =>
      batches.where((b) => identical(b.session, s)).toList();

  void attach(PeerSession s) {
    s.onControl = _onControl;
    s.onChunk = _onChunk;
  }

  void _markDirty() => _dirty = true;

  void _tick() {
    var any = false;
    for (final t in allTasks) {
      if (t.status == TaskStatus.active) {
        final delta = t.transferred - t._lastSampleBytes;
        final inst = delta / 0.5;
        t.speed = t.speed == 0 ? inst : t.speed * 0.6 + inst * 0.4;
        any = true;
      }
      t._lastSampleBytes = t.transferred;
    }
    if (any || _dirty) {
      _dirty = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  Future<TransferBatch?> offer(PeerSession s, List<SendSource> sources) async {
    if (!s.state.isLive) {
      notice('Gönderilemedi', 'Bağlantı aktif değil.', error: true);
      return null;
    }
    if (sources.isEmpty) return null;
    if (sources.length > kMaxItemsPerRequest) {
      notice('Çok fazla dosya', 'Tek seferde en fazla $kMaxItemsPerRequest dosya gönderilebilir.',
          error: true);
      return null;
    }
    final b = TransferBatch(
      reqId: hex(randomBytes(8)),
      session: s,
      direction: TransferDirection.send,
      peerName: s.displayName,
      peerKey: s.peerKeyB64,
    );
    for (final src in sources) {
      b.tasks.add(FileTask(
        fileId: randomBytes(16),
        batch: b,
        name: src.name,
        relDir: src.relDir,
        size: src.size,
        source: src,
      ));
    }
    for (final t in b.tasks) {
      _tasksById[t.idHex] = t;
    }
    batches.insert(0, b);
    _markDirty();
    try {
      await s.sendControl({
        't': 'offer',
        'req': b.reqId,
        'total': b.totalSize,
        'items': [
          for (final t in b.tasks) {'id': t.idHex, 'name': t.name, 'dir': t.relDir, 'size': t.size}
        ],
      });
    } catch (e) {
      _failBatch(b, 'İstek gönderilemedi: $e');
    }
    notifyListeners();
    return b;
  }

  void _startSending(TransferBatch b) {
    final key = b.session.id;
    final prev = _sendQueues[key] ?? Future.value();
    _sendQueues[key] = prev.then((_) => _sendBatch(b)).catchError((_) {});
  }

  Future<void> _sendBatch(TransferBatch b) async {
    final s = b.session;
    for (final t in b.tasks) {
      if (b.status != BatchStatus.accepted) break;
      if (t.status.isFinal) continue;
      t.status = TaskStatus.active;
      t.startedAt = DateTime.now();
      t.path = t.source?.path;
      _markDirty();
      final inFlight = <Future<void>>[];
      try {
        var offset = 0;
        await for (final piece in t.source!.open()) {
          var pos = 0;
          final data = piece is Uint8List ? piece : Uint8List.fromList(piece);
          while (pos < data.length) {
            while (b.paused && !t.status.isFinal && b.status == BatchStatus.accepted) {
              t.status = TaskStatus.paused;
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
            if (t.status == TaskStatus.paused) t.status = TaskStatus.active;
            if (t.status.isFinal || b.status != BatchStatus.accepted || !s.state.isLive) {
              throw _Abort();
            }
            final end = min(pos + kChunkSize, data.length);
            final slice = Uint8List.sublistView(data, pos, end);
            if (offset + slice.length > t.size) {
              throw StateError('Dosya gönderim sırasında büyüdü');
            }
            final sentTo = offset + slice.length;
            final sending = s.sendChunk(t.fileId, offset, slice).then((_) => t.transferred = sentTo);
            // Errors surface when awaited below; never as "unhandled".
            sending.ignore();
            inFlight.add(sending);
            if (inFlight.length >= kChunksInFlight) await inFlight.removeAt(0);
            offset = sentTo;
            pos = end;
          }
        }
        for (final f in inFlight) {
          await f;
        }
        inFlight.clear();
        if (offset != t.size) {
          throw StateError('Dosya gönderim sırasında değişti');
        }
        t.status = TaskStatus.verifying;
        t.sha256 = await s.takeFileHash(t.idHex);
        _markDirty();
        await s.sendControl({'t': 'fend', 'id': t.idHex, 'sha': t.sha256});
        // Completion is confirmed by the receiver's "fdone".
        await _waitFor(() => t.status != TaskStatus.verifying || !s.state.isLive,
            timeout: const Duration(minutes: 10));
        if (t.status == TaskStatus.verifying) {
          _finishTask(t, TaskStatus.failed, error: 'Alıcıdan onay gelmedi');
        }
      } on _Abort {
        for (final f in inFlight) {
          f.ignore();
        }
        s.dropFileHash(t.idHex);
        if (!t.status.isFinal) {
          _finishTask(t, TaskStatus.canceled, error: 'İptal edildi');
        }
        if (s.state.isLive && b.status == BatchStatus.accepted) {
          s.sendControl({'t': 'cancel', 'req': b.reqId, 'id': t.idHex}).catchError((_) {});
        }
      } catch (e) {
        for (final f in inFlight) {
          f.ignore();
        }
        s.dropFileHash(t.idHex);
        if (!t.status.isFinal) {
          _finishTask(t, TaskStatus.failed, error: e is FileSystemException ? 'Dosya okunamadı' : '$e');
        }
        if (s.state.isLive) {
          s.sendControl({'t': 'cancel', 'req': b.reqId, 'id': t.idHex}).catchError((_) {});
        }
      }
    }
    _settleBatch(b);
  }

  Future<void> _waitFor(bool Function() cond, {required Duration timeout}) async {
    final end = DateTime.now().add(timeout);
    while (!cond() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  /// Feeds a decrypted control message as if it came from [s] (tests).
  @visibleForTesting
  Future<void> debugReceiveControl(PeerSession s, Map<String, dynamic> m) => _onControl(s, m);

  Future<void> _onControl(PeerSession s, Map<String, dynamic> m) async {
    switch (m['t']) {
      case 'offer':
        await _onOffer(s, m);
      case 'accept':
        final b = _batch(s, m['req'], TransferDirection.send);
        if (b != null && b.status == BatchStatus.pending) {
          b.status = BatchStatus.accepted;
          notice('İstek kabul edildi', '${s.displayName} aktarımı onayladı: ${b.title}');
          _startSending(b);
          _markDirty();
        }
      case 'reject':
        final b = _batch(s, m['req'], TransferDirection.send);
        if (b != null && b.status == BatchStatus.pending) {
          b.status = BatchStatus.rejected;
          b.reason = _reasonText(m['reason']);
          for (final t in b.tasks) {
            _finishTask(t, TaskStatus.canceled, error: 'Reddedildi', record: RecordStatus.rejected);
          }
          notice('İstek reddedildi', '${s.displayName}: ${b.reason}', error: true);
          _markDirty();
        }
      case 'fend':
        await _onFileEnd(s, m);
      case 'fdone':
        final t = _task(s, m['id'], TransferDirection.send);
        if (t != null && t.status == TaskStatus.verifying) {
          if (m['ok'] == true) {
            _finishTask(t, TaskStatus.done);
          } else {
            _finishTask(t, TaskStatus.failed, error: _reasonText(m['reason']));
          }
        }
      case 'cancel':
        _onPeerCancel(s, m);
      case 'pause':
      case 'resume':
        final b = batches.where((x) => identical(x.session, s) && x.reqId == m['req']).firstOrNull;
        if (b != null) {
          b.paused = m['t'] == 'pause';
          b.pausedByPeer = b.paused;
          for (final t in b.tasks) {
            if (b.direction == TransferDirection.receive && !t.status.isFinal && t.transferred > 0) {
              t.status = b.paused ? TaskStatus.paused : TaskStatus.active;
            }
          }
          _markDirty();
        }
    }
  }

  String _reasonText(Object? r) => switch (r) {
        'user' => 'Karşı taraf reddetti',
        'busy' => 'Karşı tarafta çok fazla bekleyen istek var',
        'size' => 'Boyut, karşı tarafın izin verdiği sınırı aşıyor',
        'invalid' => 'İstek geçersiz bulundu',
        'hash' => 'Bütünlük doğrulaması başarısız (dosya bozuk geldi)',
        'write' => 'Alıcı dosyayı diske yazamadı',
        'closed' => 'Bağlantı kapandı',
        _ => r is String && r.length < 120 ? r : 'Bilinmeyen neden',
      };

  Future<void> _onOffer(PeerSession s, Map<String, dynamic> m) async {
    final req = m['req'];
    final items = m['items'];
    if (req is! String || req.length != 16 || items is! List) return;
    Future<void> reject(String reason) =>
        s.sendControl({'t': 'reject', 'req': req, 'reason': reason}).catchError((_) {});

    if (batches.any((b) => b.reqId == req && identical(b.session, s))) return;
    final pending = batches
        .where((b) => identical(b.session, s) && b.direction == TransferDirection.receive && b.status == BatchStatus.pending)
        .length;
    if (pending >= kMaxPendingRequestsPerPeer) return reject('busy');
    if (items.isEmpty || items.length > kMaxItemsPerRequest) return reject('invalid');

    final b = TransferBatch(
      reqId: req,
      session: s,
      direction: TransferDirection.receive,
      peerName: s.displayName,
      peerKey: s.peerKeyB64,
    );
    final seen = <String>{};
    for (final raw in items) {
      if (raw is! Map) return reject('invalid');
      final id = raw['id'], name = raw['name'], size = raw['size'];
      if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) || !seen.add(id)) {
        return reject('invalid');
      }
      if (name is! String || size is! int || size < 0 || size > (1 << 50)) {
        return reject('invalid');
      }
      if (_tasksById.containsKey(id)) return reject('invalid');
      final dir = sanitizeRelativeDir(raw['dir'] is String ? raw['dir'] as String : null);
      b.tasks.add(FileTask(
        fileId: Uint8List.fromList(List.generate(16, (i) => int.parse(id.substring(i * 2, i * 2 + 2), radix: 16))),
        batch: b,
        name: sanitizeFileName(name),
        relDir: dir.join('/'),
        size: size,
      ));
    }
    final limit = maxIncomingBytes();
    if (limit > 0 && b.totalSize > limit) {
      await reject('size');
      notice('İstek otomatik reddedildi',
          '${s.displayName} ayarladığın boyut sınırını aşan bir aktarım göndermek istedi.',
          error: true);
      return;
    }
    for (final t in b.tasks) {
      _tasksById[t.idHex] = t;
    }
    batches.insert(0, b);
    _markDirty();

    final autoDir = await autoAcceptDestination(b);
    if (autoDir != null) {
      b.autoAccepted = true;
      await accept(b, autoDir);
    } else {
      notice('Yeni dosya isteği', '${s.displayName} sana ${b.title} göndermek istiyor.');
    }
  }

  Future<void> accept(TransferBatch b, String destination) async {
    if (b.status != BatchStatus.pending || b.direction != TransferDirection.receive) return;
    if (!b.session.state.isLive) {
      b.status = BatchStatus.failed;
      b.reason = 'Bağlantı kapalı';
      _markDirty();
      return;
    }
    try {
      await Directory(destination).create(recursive: true);
    } catch (_) {
      notice('Klasör kullanılamıyor', destination, error: true);
      return;
    }
    b.destination = destination;
    b.status = BatchStatus.accepted;
    _markDirty();
    await b.session.sendControl({'t': 'accept', 'req': b.reqId});
  }

  Future<void> reject(TransferBatch b) async {
    if (b.status != BatchStatus.pending) return;
    b.status = BatchStatus.rejected;
    for (final t in b.tasks) {
      _finishTask(t, TaskStatus.canceled, error: 'Reddettin', record: RecordStatus.rejected);
    }
    _markDirty();
    if (b.session.state.isLive) {
      await b.session.sendControl({'t': 'reject', 'req': b.reqId, 'reason': 'user'}).catchError((_) {});
    }
  }

  Future<void> _onChunk(PeerSession s, String fid, int offset, Uint8List data) async {
    final t = _tasksById[fid];
    if (t == null || !identical(t.batch.session, s) || t.direction != TransferDirection.receive) {
      return; // unknown/foreign id – ignore (and never write anything)
    }
    final b = t.batch;
    if (b.status != BatchStatus.accepted || t.status.isFinal) return;
    if (offset != t.transferred || t.transferred + data.length > t.size) {
      await _failReceive(t, 'invalid', 'Beklenmeyen veri sırası');
      return;
    }
    try {
      if (t._raf == null) {
        final dir = _targetDir(b.destination!, t.relDir);
        await Directory(dir).create(recursive: true);
        final part = uniquePath(dir, '${t.name}.jppart', (x) => File(x).existsSync());
        if (!isInside(b.destination!, part)) throw const FileSystemException('Güvensiz yol');
        t._partPath = part;
        t._raf = await File(part).open(mode: FileMode.writeOnly);
        t.status = TaskStatus.active;
        t.startedAt = DateTime.now();
        _markDirty();
      }
      if (t.status == TaskStatus.queued) t.status = TaskStatus.active;
      await t._raf!.writeFrom(data);
      t.transferred += data.length;
    } catch (e) {
      await _failReceive(t, 'write', 'Diske yazılamadı: ${e is FileSystemException ? e.message : e}');
    }
  }

  String _targetDir(String root, String relDir) {
    if (relDir.isEmpty) return root;
    final segs = sanitizeRelativeDir(relDir);
    final dir = p.joinAll([root, ...segs]);
    return isInside(root, dir) ? dir : root;
  }

  Future<void> _onFileEnd(PeerSession s, Map<String, dynamic> m) async {
    final t = _task(s, m['id'], TransferDirection.receive);
    if (t == null || t.status.isFinal) return;
    final b = t.batch;
    if (b.status != BatchStatus.accepted) return;
    if (t.transferred != t.size) {
      await _failReceive(t, 'invalid', 'Dosya eksik geldi');
      return;
    }
    t.status = TaskStatus.verifying;
    _markDirty();
    try {
      // Zero byte files never produced a chunk – create them now.
      if (t._raf == null) {
        final dir = _targetDir(b.destination!, t.relDir);
        await Directory(dir).create(recursive: true);
        t._partPath = uniquePath(dir, '${t.name}.jppart', (x) => File(x).existsSync());
        t._raf = await File(t._partPath!).open(mode: FileMode.writeOnly);
        t.startedAt ??= DateTime.now();
      }
      await t._raf!.flush();
      await t._raf!.close();
      t._raf = null;
      final actual = await s.takeFileHash(t.idHex);
      final expected = m['sha'];
      if (expected is! String || actual != expected) {
        await _failReceive(t, 'hash', 'Bütünlük doğrulaması başarısız — dosya silindi');
        return;
      }
      final dir = p.dirname(t._partPath!);
      final finalPath = uniquePath(dir, t.name, (x) => File(x).existsSync() || Directory(x).existsSync());
      if (!isInside(b.destination!, finalPath)) {
        await _failReceive(t, 'write', 'Güvensiz hedef yol');
        return;
      }
      await File(t._partPath!).rename(finalPath);
      t.path = finalPath;
      t.sha256 = actual;
      _finishTask(t, TaskStatus.done);
      await s.sendControl({'t': 'fdone', 'id': t.idHex, 'ok': true});
    } catch (e) {
      await _failReceive(t, 'write', 'Dosya kaydedilemedi: $e');
    }
    _settleBatch(b);
  }

  Future<void> _failReceive(FileTask t, String code, String message) async {
    await _discardPart(t);
    t.batch.session.dropFileHash(t.idHex);
    _finishTask(t, TaskStatus.failed, error: message);
    if (t.batch.session.state.isLive) {
      await t.batch.session
          .sendControl({'t': 'fdone', 'id': t.idHex, 'ok': false, 'reason': code})
          .catchError((_) {});
    }
    _settleBatch(t.batch);
  }

  Future<void> _discardPart(FileTask t) async {
    try {
      await t._raf?.close();
    } catch (_) {}
    t._raf = null;
    if (t._partPath != null) {
      try {
        final f = File(t._partPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  void _onPeerCancel(PeerSession s, Map<String, dynamic> m) {
    final b = batches.where((x) => identical(x.session, s) && x.reqId == m['req']).firstOrNull;
    if (b == null) return;
    final id = m['id'];
    final targets = id is String ? b.tasks.where((t) => t.idHex == id) : b.tasks;
    for (final t in targets.toList()) {
      if (t.status.isFinal) continue;
      if (b.direction == TransferDirection.receive) {
        _discardPart(t);
        s.dropFileHash(t.idHex);
      }
      _finishTask(t, TaskStatus.canceled, error: 'Karşı taraf iptal etti');
    }
    if (id == null && !b.isFinished) {
      b.status = BatchStatus.canceled;
      b.reason = 'Karşı taraf iptal etti';
    }
    _settleBatch(b);
  }

  // ---------------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------------

  Future<void> cancelTask(FileTask t) async {
    if (t.status.isFinal) return;
    final b = t.batch;
    if (t.direction == TransferDirection.receive) {
      await _discardPart(t);
      b.session.dropFileHash(t.idHex);
    }
    _finishTask(t, TaskStatus.canceled, error: 'İptal ettin');
    if (b.session.state.isLive) {
      await b.session.sendControl({'t': 'cancel', 'req': b.reqId, 'id': t.idHex}).catchError((_) {});
    }
    _settleBatch(b);
  }

  Future<void> cancelBatch(TransferBatch b) async {
    if (b.isFinished) return;
    if (b.status == BatchStatus.pending && b.direction == TransferDirection.receive) {
      return reject(b);
    }
    final wasPending = b.status == BatchStatus.pending;
    b.status = BatchStatus.canceled;
    b.reason = 'İptal ettin';
    for (final t in b.tasks) {
      if (t.status.isFinal) continue;
      if (b.direction == TransferDirection.receive) {
        await _discardPart(t);
        b.session.dropFileHash(t.idHex);
      }
      _finishTask(t, TaskStatus.canceled, error: 'İptal ettin',
          record: wasPending ? RecordStatus.canceled : null);
    }
    _markDirty();
    if (b.session.state.isLive) {
      await b.session.sendControl({'t': 'cancel', 'req': b.reqId}).catchError((_) {});
    }
  }

  Future<void> setPaused(TransferBatch b, bool paused) async {
    if (b.status != BatchStatus.accepted) return;
    b.paused = paused;
    b.pausedByPeer = false;
    for (final t in b.tasks) {
      if (!t.status.isFinal && (t.status == TaskStatus.active || t.status == TaskStatus.paused)) {
        t.status = paused ? TaskStatus.paused : TaskStatus.active;
      }
    }
    _markDirty();
    await b.session.sendControl({'t': paused ? 'pause' : 'resume', 'req': b.reqId}).catchError((_) {});
  }

  /// Removes finished batches from the live lists (history keeps them).
  void clearFinished() {
    batches.removeWhere((b) {
      final done = b.isFinished || b.tasks.every((t) => t.status.isFinal);
      if (done) {
        for (final t in b.tasks) {
          _tasksById.remove(t.idHex);
        }
      }
      return done;
    });
    notifyListeners();
  }

  /// Called when a session ends: everything still running on it fails.
  void sessionEnded(PeerSession s) {
    for (final b in batches.where((b) => identical(b.session, s)).toList()) {
      if (b.isFinished) continue;
      for (final t in b.tasks) {
        if (t.status.isFinal) continue;
        if (b.direction == TransferDirection.receive) _discardPart(t);
        _finishTask(t, b.status == BatchStatus.pending ? TaskStatus.canceled : TaskStatus.failed,
            error: 'Bağlantı kesildi',
            record: b.status == BatchStatus.pending ? RecordStatus.canceled : null);
      }
      b.status = BatchStatus.failed;
      b.reason = 'Bağlantı kesildi';
    }
    _sendQueues.remove(s.id);
    _markDirty();
  }

  // ---------------------------------------------------------------------------

  TransferBatch? _batch(PeerSession s, Object? req, TransferDirection d) => batches
      .where((b) => identical(b.session, s) && b.reqId == req && b.direction == d)
      .firstOrNull;

  FileTask? _task(PeerSession s, Object? id, TransferDirection d) {
    if (id is! String) return null;
    final t = _tasksById[id];
    if (t == null || !identical(t.batch.session, s) || t.direction != d) return null;
    return t;
  }

  void _finishTask(FileTask t, TaskStatus status, {String? error, RecordStatus? record}) {
    if (t.status.isFinal) return;
    t.status = status;
    t.error = error;
    t.finishedAt = DateTime.now();
    t.speed = 0;
    _markDirty();
    final rs = record ??
        switch (status) {
          TaskStatus.done => RecordStatus.completed,
          TaskStatus.canceled => RecordStatus.canceled,
          _ => RecordStatus.failed,
        };
    onRecord(
      TransferRecord(
        id: t.idHex,
        direction: t.direction,
        fileName: t.relDir.isEmpty ? t.name : '${t.relDir}/${t.name}',
        size: t.size,
        peerName: t.batch.peerName,
        peerKey: t.batch.peerKey,
        status: rs,
        startedAt: t.startedAt ?? t.batch.createdAt,
        finishedAt: t.finishedAt!,
        path: t.path,
        sha256: t.sha256,
        error: status == TaskStatus.done ? null : error,
        batchId: t.batch.reqId,
      ),
      t,
    );
  }

  void _failBatch(TransferBatch b, String reason) {
    b.status = BatchStatus.failed;
    b.reason = reason;
    for (final t in b.tasks) {
      _finishTask(t, TaskStatus.failed, error: reason);
    }
    notice('Aktarım başarısız', reason, error: true);
  }

  void _settleBatch(TransferBatch b) {
    if (b.status != BatchStatus.accepted) {
      _markDirty();
      return;
    }
    if (b.tasks.every((t) => t.status.isFinal)) {
      final ok = b.tasks.where((t) => t.status == TaskStatus.done).length;
      b.status = ok == b.tasks.length ? BatchStatus.done : (ok == 0 ? BatchStatus.failed : BatchStatus.done);
      if (ok == b.tasks.length) {
        notice(
          b.direction == TransferDirection.send ? 'Gönderim tamamlandı' : 'Alım tamamlandı',
          '${b.title} · ${b.peerName}',
        );
      } else if (ok < b.tasks.length) {
        b.reason = '${b.tasks.length - ok} dosya aktarılamadı';
      }
    }
    _markDirty();
  }

  @override
  void dispose() {
    _ticker.cancel();
    for (final t in allTasks) {
      if (t._raf != null) _discardPart(t);
    }
    super.dispose();
  }
}

class _Abort implements Exception {}
