import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small JSON document store in the application support directory.
/// Writes are atomic (temp file + rename) and debounced.
class JsonStore {
  JsonStore._(this.root);

  final Directory root;
  final _timers = <String, Timer>{};
  final _pending = <String, Object?>{};

  static Future<JsonStore> open() async {
    final base = await getApplicationSupportDirectory();
    // JINJAPEER_PROFILE lets two instances run side by side on one machine
    // (each gets its own identity) – handy for testing.
    final profile = Platform.environment['JINJAPEER_PROFILE'];
    final name = profile == null || profile.isEmpty
        ? 'data'
        : 'data-${profile.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}';
    final dir = Directory(p.join(base.path, name));
    await dir.create(recursive: true);
    return JsonStore._(dir);
  }

  /// Store rooted at an explicit folder (tests, portable mode).
  static Future<JsonStore> at(Directory dir) async {
    await dir.create(recursive: true);
    return JsonStore._(dir);
  }

  File _file(String name) => File(p.join(root.path, '$name.json'));

  Future<Object?> read(String name) async {
    final f = _file(name);
    try {
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      // Corrupt file – keep a copy for inspection and start fresh.
      try {
        await f.rename('${f.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  void write(String name, Object? value, {Duration delay = const Duration(milliseconds: 400)}) {
    _pending[name] = value;
    _timers[name]?.cancel();
    _timers[name] = Timer(delay, () => _flush(name));
  }

  Future<void> writeNow(String name, Object? value) async {
    _timers.remove(name)?.cancel();
    _pending[name] = value;
    await _flush(name);
  }

  /// One write chain per file: two writes of the same file never overlap
  /// (overlapping temp-file renames fail on Windows).
  final _chains = <String, Future<void>>{};

  Future<void> _flush(String name) {
    final next = (_chains[name] ?? Future.value()).then((_) async {
      if (!_pending.containsKey(name)) return;
      final value = _pending.remove(name);
      final f = _file(name);
      final tmp = File('${f.path}.tmp');
      try {
        await tmp.writeAsString(jsonEncode(value), flush: true);
        await tmp.rename(f.path);
      } on FileSystemException {
        // Keep the newest value queued so the next flush retries it.
        _pending.putIfAbsent(name, () => value);
      }
    });
    _chains[name] = next;
    return next;
  }

  Future<void> flushAll() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final name in _pending.keys.toList()) {
      await _flush(name);
    }
    await Future.wait(_chains.values);
  }

  Future<void> delete(String name) async {
    _timers.remove(name)?.cancel();
    _pending.remove(name);
    await (_chains[name] ?? Future.value());
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }
}
