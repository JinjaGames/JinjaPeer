/// Defensive helpers for anything a remote peer can influence:
/// file names, folder paths, sizes and counts.
library;

import 'package:path/path.dart' as p;

const int kMaxNameLength = 160;
const int kMaxPathDepth = 24;

const _reservedWindowsNames = {
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Turns any peer supplied string into a single, safe path segment.
/// - removes path separators, control chars and characters illegal on Windows
/// - blocks `.` / `..`, Windows reserved device names, trailing dots/spaces
/// - removes bidi override characters used to disguise extensions
///   (an RTL override can make "x.exe" look like "x.png")
String sanitizeFileName(String input, {String fallback = 'dosya'}) {
  var name = input
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
      .replaceAll(RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '')
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .trim();
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') name = fallback;
  final stem = name.split('.').first.toUpperCase();
  if (_reservedWindowsNames.contains(stem)) name = '_$name';
  if (name.length > kMaxNameLength) {
    final ext = p.extension(name);
    final keepExt = ext.length <= 16 ? ext : '';
    name = name.substring(0, kMaxNameLength - keepExt.length) + keepExt;
  }
  return name;
}

/// Splits a relative path sent by a peer ("Tatil/2024/foto.jpg") into
/// sanitized segments. Absolute paths, drive letters and `..` are dropped.
List<String> sanitizeRelativeDir(String? rel) {
  if (rel == null || rel.isEmpty) return const [];
  return rel
      .split(RegExp(r'[\\/]+'))
      .where((s) => s.isNotEmpty && s != '.' && s != '..' && !s.contains(':'))
      .map((s) => sanitizeFileName(s, fallback: 'klasor'))
      .take(kMaxPathDepth)
      .toList();
}

/// Final guard: the resolved [candidate] must live inside [root].
bool isInside(String root, String candidate) {
  final r = p.normalize(p.absolute(root));
  final c = p.normalize(p.absolute(candidate));
  return p.isWithin(r, c);
}

const _dangerous = {
  'exe', 'msi', 'bat', 'cmd', 'com', 'scr', 'pif', 'ps1', 'psm1', 'vbs', 'vbe',
  'js', 'jse', 'wsf', 'wsh', 'hta', 'lnk', 'reg', 'cpl', 'msc', 'jar', 'dll',
  'sys', 'apk', 'appx', 'msix', 'dmg', 'pkg', 'app', 'sh', 'command', 'run',
  'deb', 'rpm', 'iso', 'img', 'vhd', 'vhdx', 'docm', 'xlsm', 'pptm', 'chm',
};

/// Executable / script types get a visible warning before accepting.
bool isRiskyFile(String name) {
  final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
  return _dangerous.contains(ext);
}

/// Picks "foto.jpg", "foto (1).jpg", "foto (2).jpg"… that does not exist yet.
String uniquePath(String dir, String fileName, bool Function(String) exists) {
  var candidate = p.join(dir, fileName);
  if (!exists(candidate)) return candidate;
  final ext = p.extension(fileName);
  final stem = p.basenameWithoutExtension(fileName);
  for (var i = 1; i < 10000; i++) {
    candidate = p.join(dir, '$stem ($i)$ext');
    if (!exists(candidate)) return candidate;
  }
  return p.join(dir, '$stem (${DateTime.now().millisecondsSinceEpoch})$ext');
}

/// Sanitizes a display name a peer claims for itself.
String sanitizeDisplayName(String? input) {
  final s = (input ?? '')
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '')
      .trim();
  if (s.isEmpty) return 'İsimsiz';
  return s.length > 40 ? s.substring(0, 40) : s;
}
