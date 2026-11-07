import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Highlights [path] in the system file manager (or opens its folder).
Future<bool> showInFolder(String path) async {
  try {
    final exists = await File(path).exists() || await Directory(path).exists();
    final target = exists ? path : p.dirname(path);
    if (Platform.isWindows) {
      final isFile = await File(target).exists();
      await Process.start('explorer.exe', isFile ? ['/select,', p.normalize(target)] : [p.normalize(target)]);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', target]);
      return true;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [await File(target).exists() ? p.dirname(target) : target]);
      return true;
    }
    return await launchUrl(Uri.directory(p.dirname(target)));
  } catch (_) {
    return false;
  }
}

Future<bool> openFolder(String dir) async {
  try {
    await Directory(dir).create(recursive: true);
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [p.normalize(dir)]);
      return true;
    }
    return await launchUrl(Uri.directory(dir));
  } catch (_) {
    return false;
  }
}

/// Opens a file with its default app. Only ever called on an explicit click.
Future<bool> openFile(String path) async {
  try {
    if (!await File(path).exists()) return false;
    return await launchUrl(Uri.file(path));
  } catch (_) {
    return false;
  }
}
