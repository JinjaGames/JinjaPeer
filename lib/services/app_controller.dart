import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/codes.dart';
import '../core/crypto.dart';
import '../models/models.dart';
import 'peer_session.dart';
import 'storage.dart';
import 'transfer_service.dart';

class AppNotice {
  AppNotice(this.title, this.body, {this.error = false, this.action, this.actionLabel})
      : at = DateTime.now(),
        id = _seq++;
  static int _seq = 0;
  final int id;
  final String title;
  final String body;
  final bool error;
  final DateTime at;
  final VoidCallback? action;
  final String? actionLabel;
}

/// Pages of the main shell.
enum AppPage { home, connections, transfers, requests, history, contacts, settings }

class AppController extends ChangeNotifier {
  AppController._(this._store, this.identity, this.settings);

  final JsonStore _store;
  final Identity identity;
  final AppSettings settings;
  late final TransferService transfers;

  final List<PeerSession> sessions = [];
  final List<Contact> contacts = [];
  final List<TransferRecord> history = [];
  final _notices = StreamController<AppNotice>.broadcast();
  Stream<AppNotice> get notices => _notices.stream;

  final page = ValueNotifier<AppPage>(AppPage.home);
  final selectedSession = ValueNotifier<String?>(null);
  Timer? _expiryTimer;
  String defaultDownloadDir = '';

  static const _historyCap = 5000;

  /// [store] and [downloadDir] can be injected (used by tests).
  static Future<AppController> load({JsonStore? store, String? downloadDir}) async {
    store ??= await JsonStore.open();
    final settingsJson = await store.read('settings');
    final settings = settingsJson is Map<String, dynamic>
        ? AppSettings.fromJson(settingsJson)
        : AppSettings();

    // Identity
    Identity identity;
    final idJson = await store.read('identity');
    if (idJson is Map && idJson['seed'] is String) {
      identity = await Identity.fromSeed(unb64(idJson['seed'] as String));
    } else {
      final (id, seed) = await Identity.generate();
      identity = id;
      await store.writeNow('identity', {'seed': b64(seed), 'created': DateTime.now().toIso8601String()});
    }

    final c = AppController._(store, identity, settings);
    c.defaultDownloadDir = downloadDir ?? await _resolveDownloadDir();
    if (settings.displayName.isEmpty) {
      settings.displayName = _guessName();
    }
    final contactsJson = await store.read('contacts');
    if (contactsJson is List) {
      for (final e in contactsJson) {
        try {
          c.contacts.add(Contact.fromJson((e as Map).cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    final historyJson = await store.read('history');
    if (historyJson is List) {
      for (final e in historyJson) {
        try {
          c.history.add(TransferRecord.fromJson((e as Map).cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    c._init();
    return c;
  }

  static String _guessName() {
    final env = Platform.environment;
    final user = env['USERNAME'] ?? env['USER'];
    if (user != null && user.isNotEmpty) {
      return user[0].toUpperCase() + user.substring(1);
    }
    return 'Ben';
  }

  static Future<String> _resolveDownloadDir() async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    return p.join(base.path, 'JinjaPeer');
  }

  void _init() {
    transfers = TransferService(
      onRecord: _onRecord,
      notice: (t, b, {error = false}) => notify(
        t,
        b,
        error: error,
        action: t == 'Yeni dosya isteği' ? () => page.value = AppPage.requests : null,
        actionLabel: 'Görüntüle',
      ),
      autoAcceptDestination: _autoAcceptDestination,
      maxIncomingBytes: () => settings.maxIncomingGb * 1024 * 1024 * 1024,
    );
    transfers.addListener(notifyListeners);
    _expiryTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkExpiry());
  }

  String get downloadDir =>
      settings.downloadDir.isNotEmpty ? settings.downloadDir : defaultDownloadDir;

  List<Map<String, dynamic>> get iceServers {
    final list = <Map<String, dynamic>>[
      for (final u in settings.iceServers.where((s) => s.trim().isNotEmpty)) {'urls': u.trim()},
    ];
    if (settings.turnUrl.trim().isNotEmpty) {
      list.add({
        'urls': settings.turnUrl.trim(),
        'username': settings.turnUser,
        'credential': settings.turnPass,
      });
    }
    return list;
  }

  void notify(String title, String body, {bool error = false, VoidCallback? action, String? actionLabel}) {
    _notices.add(AppNotice(title, body, error: error, action: action, actionLabel: actionLabel));
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  void saveSettings() {
    _store.write('settings', settings.toJson());
    notifyListeners();
  }

  void updateSettings(void Function(AppSettings s) change) {
    change(settings);
    saveSettings();
  }

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  List<PeerSession> get liveSessions => sessions.where((s) => s.state.isLive).toList();

  List<PeerSession> get pendingSessions =>
      sessions.where((s) => !s.state.isLive && !s.state.isOver).toList();

  PeerSession? sessionById(String? id) => sessions.where((s) => s.id == id).firstOrNull;

  void _track(PeerSession s) {
    sessions.insert(0, s);
    transfers.attach(s);
    s.addListener(notifyListeners);
    s.onConnected = () => _onConnected(s);
    s.onEnded = () => _onEnded(s);
    notifyListeners();
  }

  @visibleForTesting
  void debugAddSession(PeerSession s) => _track(s);

  Future<PeerSession> createInvite({String? password}) async {
    final s = await PeerSession.createInvite(
      identity: identity,
      myName: settings.displayName,
      iceServers: iceServers,
      validity: Duration(minutes: settings.inviteMinutes.clamp(2, 24 * 60)),
      password: password,
    );
    _track(s);
    return s;
  }

  Future<PeerSession> joinWithCode(ConnectionCode invite, {String? password}) async {
    final s = await PeerSession.acceptInvite(
      identity: identity,
      myName: settings.displayName,
      iceServers: iceServers,
      invite: invite,
      password: password,
    );
    _track(s);
    return s;
  }

  void _onConnected(PeerSession s) {
    final c = contactFor(s);
    if (c != null) {
      c.lastSeen = DateTime.now();
      _saveContacts();
    }
    notify('Bağlantı kuruldu',
        c != null ? '${c.name} ile güvenli bağlantı hazır (kayıtlı kişi, kimlik doğrulandı).'
            : '${s.displayName} ile uçtan uca şifreli bağlantı hazır.');
    selectedSession.value = s.id;
    page.value = AppPage.connections;
    notifyListeners();
  }

  void _onEnded(PeerSession s) {
    transfers.sessionEnded(s);
    if (s.connectedAt != null) {
      notify('Bağlantı sona erdi', '${s.displayName}: ${s.error ?? 'bağlantı kapandı.'}',
          error: s.state == SessionState.failed);
    }
    notifyListeners();
  }

  Future<void> closeSession(PeerSession s) async {
    await s.close(reason: 'Bağlantıyı sen sonlandırdın.');
    notifyListeners();
  }

  void removeSession(PeerSession s) {
    if (!s.state.isOver) s.close();
    sessions.remove(s);
    s.removeListener(notifyListeners);
    if (selectedSession.value == s.id) selectedSession.value = null;
    notifyListeners();
  }

  void _checkExpiry() {
    for (final s in sessions) {
      if (s.state == SessionState.waitingForAnswer && (s.myCode?.isExpired ?? false)) {
        s.close(reason: 'Davet kodunun süresi doldu.');
      }
      if (s.state == SessionState.waitingForPeer && (s.myCode?.isExpired ?? false)) {
        s.close(reason: 'Yanıt kodunun süresi doldu.');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Contacts
  // ---------------------------------------------------------------------------

  Contact? contactByKey(String key) =>
      key.isEmpty ? null : contacts.where((c) => c.identityKey == key).firstOrNull;

  Contact? contactFor(PeerSession s) => contactByKey(s.peerKeyB64);

  /// Another saved contact uses this display name but a *different* key:
  /// could be impersonation – the UI shows a warning.
  Contact? impostorWarning(PeerSession s) {
    if (contactFor(s) != null) return null;
    final n = s.displayName.toLowerCase();
    return contacts.where((c) => c.name.toLowerCase() == n).firstOrNull;
  }

  Contact? contactForInvite(ConnectionCode code) => contactByKey(b64(code.identityKey));

  Future<Contact> addContact(PeerSession s, {String? name, bool trusted = false}) async {
    final existing = contactFor(s);
    if (existing != null) return existing;
    final c = Contact(
      identityKey: s.peerKeyB64,
      fingerprint: s.peerFingerprint ?? await fingerprintOf(s.peerIdentityKey!),
      name: (name ?? s.displayName).trim().isEmpty ? s.displayName : name!.trim(),
      addedAt: DateTime.now(),
      lastSeen: DateTime.now(),
      trusted: trusted,
      colorSeed: s.peerKeyB64.codeUnits.fold(0, (a, b) => a + b), // same as seedOf()
    );
    // Carry over stats from history.
    for (final r in history.where((r) => r.peerKey == c.identityKey && r.status == RecordStatus.completed)) {
      if (r.direction == TransferDirection.send) {
        c.sentBytes += r.size;
      } else {
        c.receivedBytes += r.size;
      }
      c.fileCount++;
    }
    contacts.add(c);
    _saveContacts();
    notify('Kişi kaydedildi', '${c.name} kişilerine eklendi.');
    return c;
  }

  void updateContact(Contact c, void Function(Contact) change) {
    change(c);
    _saveContacts();
  }

  void removeContact(Contact c) {
    contacts.remove(c);
    _saveContacts();
  }

  void _saveContacts() {
    _store.write('contacts', contacts.map((c) => c.toJson()).toList());
    notifyListeners();
  }

  Future<String?> _autoAcceptDestination(TransferBatch b) async {
    if (!settings.autoAcceptTrusted || settings.askWhereToSave) return null;
    final c = contactByKey(b.peerKey);
    if (c == null || !c.trusted) return null;
    return downloadDir;
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  @visibleForTesting
  void debugAddRecord(TransferRecord r) => _onRecord(r, null);

  void _onRecord(TransferRecord r, FileTask? t) {
    history.insert(0, r);
    if (history.length > _historyCap) history.removeRange(_historyCap, history.length);
    if (r.status == RecordStatus.completed) {
      final c = contactByKey(r.peerKey);
      if (c != null) {
        if (r.direction == TransferDirection.send) {
          c.sentBytes += r.size;
        } else {
          c.receivedBytes += r.size;
        }
        c.fileCount++;
        c.lastSeen = DateTime.now();
        _saveContacts();
      }
    }
    _saveHistory();
  }

  void _saveHistory() {
    _store.write('history', history.map((r) => r.toJson()).toList(), delay: const Duration(seconds: 1));
    notifyListeners();
  }

  void removeRecord(TransferRecord r) {
    history.remove(r);
    _saveHistory();
  }

  void clearHistory() {
    history.clear();
    _saveHistory();
  }

  int get totalSent => history
      .where((r) => r.direction == TransferDirection.send && r.status == RecordStatus.completed)
      .fold(0, (a, r) => a + r.size);
  int get totalReceived => history
      .where((r) => r.direction == TransferDirection.receive && r.status == RecordStatus.completed)
      .fold(0, (a, r) => a + r.size);

  // ---------------------------------------------------------------------------

  /// Generates a brand new identity. Saved contacts will no longer recognise
  /// this device, so the UI asks for confirmation first.
  Future<void> resetAll() async {
    for (final s in sessions.toList()) {
      await s.close();
    }
    sessions.clear();
    contacts.clear();
    history.clear();
    await _store.delete('contacts');
    await _store.delete('history');
    await _store.delete('identity');
    await _store.delete('settings');
  }

  Future<void> shutdown() async {
    for (final s in sessions) {
      await s.close();
    }
    await _store.flushAll();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    transfers.dispose();
    _notices.close();
    super.dispose();
  }
}
