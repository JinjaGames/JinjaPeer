import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../services/peer_session.dart';
import '../services/transfer_service.dart';
import 'theme.dart';
import 'widgets/chrome.dart';
import 'widgets/dialogs.dart';
import 'widgets/glass.dart';

/// Collects all regular files below [dir]; relDir keeps the folder name so
/// the receiver gets the same structure. Symlinks are skipped on purpose.
Future<List<SendSource>> sourcesFromDirectory(String dir) async {
  final root = Directory(dir);
  final parent = p.dirname(root.path);
  final out = <SendSource>[];
  await for (final e in root.list(recursive: true, followLinks: false)) {
    if (e is File) {
      try {
        final rel = p.relative(p.dirname(e.path), from: parent).replaceAll('\\', '/');
        out.add(SendSource.fromFile(e, relDir: rel == '.' ? '' : rel));
      } catch (_) {}
    }
    if (out.length > kMaxItemsPerRequest) break;
  }
  return out;
}

/// Turns dropped / picked paths (files or folders) into send sources.
Future<List<SendSource>> sourcesFromPaths(Iterable<String> paths) async {
  final out = <SendSource>[];
  for (final path in paths) {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      out.add(SendSource.fromFile(File(path)));
    } else if (type == FileSystemEntityType.directory) {
      out.addAll(await sourcesFromDirectory(path));
    }
  }
  return out;
}

Future<List<SendSource>> pickFilesToSend() async {
  final picked = await FilePicker.pickFiles(dialogTitle: 'Gönderilecek dosyaları seç');
  final out = <SendSource>[];
  for (final f in picked) {
    final path = f.path;
    if (path != null && File(path).existsSync()) {
      out.add(SendSource.fromFile(File(path)));
    } else {
      final size = await f.length() ?? 0;
      out.add(SendSource(name: f.name, size: size, open: () => f.readAsByteStream()));
    }
  }
  return out;
}

Future<List<SendSource>> pickFolderToSend() async {
  final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Gönderilecek klasörü seç');
  if (dir == null) return const [];
  return sourcesFromDirectory(dir);
}

/// Sends [sources] to [session], or asks which connection to use.
Future<void> sendTo(BuildContext context, PeerSession? session, List<SendSource> sources) async {
  if (sources.isEmpty) return;
  final app = context.appRead;
  var target = session;
  if (target == null) {
    final live = app.liveSessions;
    if (live.isEmpty) {
      app.notify('Önce bağlan', 'Dosya göndermek için bir kişiyle bağlantı kurmalısın.', error: true);
      return;
    }
    target = live.length == 1 ? live.first : await pickSession(context, live);
    if (target == null) return;
  }
  final batch = await app.transfers.offer(target, sources);
  if (batch != null) {
    final total = sources.fold<int>(0, (a, s) => a + s.size);
    app.notify('İstek gönderildi',
        '${target.displayName} onaylayınca ${sources.length} dosya (${formatBytes(total)}) aktarılmaya başlayacak.');
  }
}

Future<PeerSession?> pickSession(BuildContext context, List<PeerSession> sessions) {
  return showGlassDialog<PeerSession>(
    context,
    maxWidth: 420,
    child: Builder(
      builder: (context) {
        final jp = context.jp;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DialogHeader(icon: Icons.send_rounded, title: 'Kime gönderilsin?'),
            const SizedBox(height: S.lg),
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: GlassTile(
                  padding: const EdgeInsets.all(S.md),
                  radius: R.md,
                  onTap: () => Navigator.of(context).pop(s),
                  child: Row(
                    children: [
                      Avatar(name: s.displayName, seed: seedOf(s.peerKeyB64), size: 34, online: true),
                      const SizedBox(width: S.md),
                      Expanded(child: Text(s.displayName, style: context.tt.titleSmall)),
                      Icon(Icons.chevron_right_rounded, color: jp.textMuted),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
