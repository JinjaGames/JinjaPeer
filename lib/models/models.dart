import 'package:flutter/material.dart';

enum TransferDirection { send, receive }

enum RecordStatus { completed, failed, canceled, rejected }

/// A finished transfer, persisted in history.
class TransferRecord {
  TransferRecord({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.size,
    required this.peerName,
    required this.peerKey,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    this.path,
    this.sha256,
    this.error,
    this.batchId,
    this.scan,
  });

  /// Scan outcome: "clean|...", "warning|...", "threat|..." or "override|...".
  final String? scan;

  final String id;
  final TransferDirection direction;
  final String fileName;
  final int size;
  final String peerName;
  final String peerKey;
  final RecordStatus status;
  final DateTime startedAt;
  final DateTime finishedAt;

  /// Saved path (receive) or source path (send), if known.
  final String? path;
  final String? sha256;
  final String? error;
  final String? batchId;

  double get averageSpeed {
    final ms = finishedAt.difference(startedAt).inMilliseconds;
    if (ms <= 0) return 0;
    return size / (ms / 1000);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'dir': direction.name,
        'name': fileName,
        'size': size,
        'peer': peerName,
        'peerKey': peerKey,
        'status': status.name,
        'start': startedAt.millisecondsSinceEpoch,
        'end': finishedAt.millisecondsSinceEpoch,
        'path': path,
        'sha': sha256,
        'err': error,
        'batch': batchId,
        'scan': scan,
      };

  static TransferRecord fromJson(Map<String, dynamic> j) => TransferRecord(
        id: j['id'] as String,
        direction: TransferDirection.values.byName(j['dir'] as String),
        fileName: j['name'] as String,
        size: j['size'] as int,
        peerName: j['peer'] as String,
        peerKey: (j['peerKey'] as String?) ?? '',
        status: RecordStatus.values.byName(j['status'] as String),
        startedAt: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        finishedAt: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        path: j['path'] as String?,
        sha256: j['sha'] as String?,
        error: j['err'] as String?,
        batchId: j['batch'] as String?,
        scan: j['scan'] as String?,
      );
}

/// A peer this user decided to remember. Identified by its identity key,
/// so the app can tell on later connections that it really is them.
class Contact {
  Contact({
    required this.identityKey,
    required this.fingerprint,
    required this.name,
    required this.addedAt,
    required this.lastSeen,
    this.trusted = false,
    this.favorite = false,
    this.sentBytes = 0,
    this.receivedBytes = 0,
    this.fileCount = 0,
    this.colorSeed = 0,
  });

  final String identityKey;
  final String fingerprint;
  String name;
  final DateTime addedAt;
  DateTime lastSeen;

  /// Files from trusted contacts can be accepted automatically (if enabled).
  bool trusted;
  bool favorite;
  int sentBytes;
  int receivedBytes;
  int fileCount;
  int colorSeed;

  Map<String, dynamic> toJson() => {
        'ik': identityKey,
        'fp': fingerprint,
        'name': name,
        'added': addedAt.millisecondsSinceEpoch,
        'seen': lastSeen.millisecondsSinceEpoch,
        'trusted': trusted,
        'fav': favorite,
        'sent': sentBytes,
        'recv': receivedBytes,
        'files': fileCount,
        'color': colorSeed,
      };

  static Contact fromJson(Map<String, dynamic> j) => Contact(
        identityKey: j['ik'] as String,
        fingerprint: j['fp'] as String,
        name: j['name'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(j['added'] as int),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(j['seen'] as int),
        trusted: j['trusted'] as bool? ?? false,
        favorite: j['fav'] as bool? ?? false,
        sentBytes: j['sent'] as int? ?? 0,
        receivedBytes: j['recv'] as int? ?? 0,
        fileCount: j['files'] as int? ?? 0,
        colorSeed: j['color'] as int? ?? 0,
      );
}

class AppSettings {
  AppSettings({
    this.displayName = '',
    this.downloadDir = '',
    this.askWhereToSave = false,
    this.autoAcceptTrusted = false,
    this.themeMode = ThemeMode.dark,
    this.inviteMinutes = 15,
    this.iceServers = const [
      'stun:stun.l.google.com:19302',
      'stun:stun.cloudflare.com:3478',
    ],
    this.turnUrl = '',
    this.turnUser = '',
    this.turnPass = '',
    this.maxIncomingGb = 0,
    this.reduceMotion = false,
    this.onboarded = false,
    this.keepFolderStructure = true,
    this.scanEnabled = true,
    this.virusTotalKey = '',
  });

  bool scanEnabled;
  String virusTotalKey;

  String displayName;
  String downloadDir;
  bool askWhereToSave;
  bool autoAcceptTrusted;
  ThemeMode themeMode;
  int inviteMinutes;
  List<String> iceServers;
  String turnUrl;
  String turnUser;
  String turnPass;

  /// 0 = unlimited. Requests above this size are rejected automatically.
  int maxIncomingGb;
  bool reduceMotion;
  bool onboarded;
  bool keepFolderStructure;

  Map<String, dynamic> toJson() => {
        'name': displayName,
        'dl': downloadDir,
        'ask': askWhereToSave,
        'auto': autoAcceptTrusted,
        'theme': themeMode.name,
        'inviteMin': inviteMinutes,
        'ice': iceServers,
        'turnUrl': turnUrl,
        'turnUser': turnUser,
        'turnPass': turnPass,
        'maxGb': maxIncomingGb,
        'reduceMotion': reduceMotion,
        'onboarded': onboarded,
        'keepTree': keepFolderStructure,
        'scan': scanEnabled,
        'vtKey': virusTotalKey,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        displayName: j['name'] as String? ?? '',
        downloadDir: j['dl'] as String? ?? '',
        askWhereToSave: j['ask'] as bool? ?? false,
        autoAcceptTrusted: j['auto'] as bool? ?? false,
        themeMode: ThemeMode.values.asNameMap()[j['theme']] ?? ThemeMode.dark,
        inviteMinutes: j['inviteMin'] as int? ?? 15,
        iceServers: (j['ice'] as List?)?.cast<String>() ??
            const ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
        turnUrl: j['turnUrl'] as String? ?? '',
        turnUser: j['turnUser'] as String? ?? '',
        turnPass: j['turnPass'] as String? ?? '',
        maxIncomingGb: j['maxGb'] as int? ?? 0,
        reduceMotion: j['reduceMotion'] as bool? ?? false,
        onboarded: j['onboarded'] as bool? ?? false,
        keepFolderStructure: j['keepTree'] as bool? ?? true,
        scanEnabled: j['scan'] as bool? ?? true,
        virusTotalKey: j['vtKey'] as String? ?? '',
      );
}
