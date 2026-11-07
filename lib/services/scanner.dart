// ignore_for_file: prefer_adjacent_string_concatenation
/// Free malware checks for received files. Runs after the SHA-256 check and
/// before the file is given its real name, so nothing dangerous lands in the
/// download folder without the user's decision.
///
/// Layers (each one optional / platform dependent):
///  1. JinjaPeer checks (all platforms, offline): disguised executables
///     (real type vs. extension), double extensions ("fatura.pdf.exe"),
///     executables inside archives, Office macros, active PDF content and the
///     EICAR test signature.
///  2. Microsoft Defender (Windows, offline): real antivirus engine via
///     MpCmdRun.exe, without letting it delete anything on its own.
///  3. VirusTotal hash lookup (opt-in, needs a free API key): only the
///     file's SHA-256 is sent – never the file itself.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

enum ThreatLevel { clean, warning, threat }

class ScanFinding {
  const ScanFinding(this.level, this.engine, this.message);
  final ThreatLevel level;
  final String engine;
  final String message;

  Map<String, dynamic> toJson() => {'l': level.name, 'e': engine, 'm': message};
  static ScanFinding fromJson(Map<String, dynamic> j) =>
      ScanFinding(ThreatLevel.values.byName(j['l'] as String), j['e'] as String, j['m'] as String);
}

class ScanReport {
  ScanReport(this.findings, this.engines);
  final List<ScanFinding> findings;

  /// Engines that actually ran (e.g. "JinjaPeer", "Microsoft Defender").
  final List<String> engines;

  /// The file disappeared during the scan (an antivirus removed it).
  bool removedByAntivirus = false;

  ThreatLevel get level => findings.fold(
      ThreatLevel.clean, (a, f) => f.level.index > a.index ? f.level : a);
  bool get isThreat => level == ThreatLevel.threat;
  bool get hasWarning => level == ThreatLevel.warning;

  String get summary {
    final threats = findings.where((f) => f.level == ThreatLevel.threat).toList();
    if (threats.isNotEmpty) return threats.map((f) => f.message).join(' · ');
    final warns = findings.where((f) => f.level == ThreatLevel.warning).toList();
    if (warns.isNotEmpty) return warns.map((f) => f.message).join(' · ');
    return 'Temiz (${engines.join(' + ')})';
  }

  /// Short text stored with the history record.
  String get note => '${level.name}|$summary';
}

class ScanOptions {
  const ScanOptions({this.enabled = true, this.virusTotalKey = '', this.useDefender = true});
  final bool enabled;
  final String virusTotalKey;
  final bool useDefender;
}

/// The EICAR anti-virus test string, assembled at runtime so this source file
/// itself is never flagged by an antivirus.
String eicarTestString() =>
    r'X5O!P%@AP[4\PZX54(P^)7CC)7}$' + r'EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*';

const _execExt = {
  'exe', 'msi', 'com', 'scr', 'pif', 'dll', 'sys', 'cpl', 'bat', 'cmd', 'ps1', 'psm1', 'vbs',
  'vbe', 'js', 'jse', 'wsf', 'wsh', 'hta', 'lnk', 'reg', 'msc', 'jar', 'apk', 'appx', 'msix',
  'sh', 'command', 'run', 'app', 'elf', 'so', 'dylib', 'deb', 'rpm', 'pkg', 'dmg',
};

const _docMediaExt = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'tif', 'tiff', 'svg', 'pdf', 'doc', 'docx',
  'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt', 'csv', 'mp3', 'wav', 'flac', 'm4a', 'mp4',
  'mkv', 'mov', 'avi', 'webm', 'zip', 'rar', '7z', 'md', 'json', 'html', 'htm',
};

String _ext(String name) => p.extension(name).toLowerCase().replaceFirst('.', '');

bool _startsWith(Uint8List b, List<int> sig, [int at = 0]) {
  if (b.length < at + sig.length) return false;
  for (var i = 0; i < sig.length; i++) {
    if (b[at + i] != sig[i]) return false;
  }
  return true;
}

int _indexOf(Uint8List hay, List<int> needle, [int start = 0]) {
  outer:
  for (var i = start; i <= hay.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// What kind of executable the bytes are, or null.
String? executableKind(Uint8List head) {
  if (_startsWith(head, [0x4D, 0x5A])) return 'Windows programı (PE)';
  if (_startsWith(head, [0x7F, 0x45, 0x4C, 0x46])) return 'Linux programı (ELF)';
  for (final sig in const [
    [0xFE, 0xED, 0xFA, 0xCE], [0xFE, 0xED, 0xFA, 0xCF], [0xCE, 0xFA, 0xED, 0xFE], [0xCF, 0xFA, 0xED, 0xFE],
  ]) {
    if (_startsWith(head, sig)) return 'macOS programı (Mach-O)';
  }
  if (_startsWith(head, [0x23, 0x21])) return 'betik (#!)';
  if (_startsWith(head, [0x4C, 0x00, 0x00, 0x00, 0x01, 0x14, 0x02, 0x00])) return 'Windows kısayolu (.lnk)';
  return null;
}

/// Lists file names in a ZIP's central directory (best effort, no extraction).
List<String> zipEntryNames(Uint8List tail) {
  final names = <String>[];
  var i = 0;
  while (true) {
    i = _indexOf(tail, const [0x50, 0x4B, 0x01, 0x02], i);
    if (i < 0 || i + 46 > tail.length) break;
    final bd = ByteData.sublistView(tail);
    final n = bd.getUint16(i + 28, Endian.little);
    final x = bd.getUint16(i + 30, Endian.little);
    final c = bd.getUint16(i + 32, Endian.little);
    if (i + 46 + n > tail.length) break;
    names.add(utf8.decode(tail.sublist(i + 46, i + 46 + n), allowMalformed: true));
    i += 46 + n + x + c;
    if (names.length > 20000) break;
  }
  return names;
}

/// Offline JinjaPeer checks on the first bytes (and ZIP directory) of a file.
List<ScanFinding> inspect(String name, Uint8List head, {Uint8List? tail}) {
  const engine = 'JinjaPeer';
  final out = <ScanFinding>[];
  final ext = _ext(name);

  if (_indexOf(head, ascii.encode(eicarTestString())) >= 0 ||
      (tail != null && _indexOf(tail, ascii.encode(eicarTestString())) >= 0)) {
    out.add(const ScanFinding(ThreatLevel.threat, engine, 'EICAR test virüsü imzası'));
  }

  final kind = executableKind(head);
  if (kind == 'betik (#!)' && !_execExt.contains(ext)) {
    out.add(const ScanFinding(ThreatLevel.warning, engine, 'İçinde çalıştırılabilir betik var (#!)'));
  } else if (kind != null && !_execExt.contains(ext)) {
    out.add(ScanFinding(ThreatLevel.threat, engine,
        'Uzantısı gizlenmiş çalıştırılabilir dosya: ".$ext" görünüyor ama gerçekte $kind'));
  } else if (kind != null || _execExt.contains(ext)) {
    out.add(const ScanFinding(ThreatLevel.warning, engine, 'Çalıştırılabilir program / betik'));
  }

  final parts = name.toLowerCase().split('.');
  if (parts.length >= 3 && _execExt.contains(parts.last) && _docMediaExt.contains(parts[parts.length - 2])) {
    out.add(ScanFinding(ThreatLevel.threat, engine,
        'Çift uzantı hilesi: ".${parts[parts.length - 2]}" gibi görünen bir ".${parts.last}" programı'));
  }
  if (name.contains(RegExp(r'[\u202A-\u202E\u2066-\u2069]'))) {
    out.add(const ScanFinding(ThreatLevel.threat, engine, 'Dosya adında yön değiştirme hilesi'));
  }

  // ZIP based formats (zip, docx/xlsx/pptx, jar, apk…)
  if (_startsWith(head, const [0x50, 0x4B, 0x03, 0x04]) && tail != null) {
    final entries = zipEntryNames(tail).map((e) => e.toLowerCase()).toList();
    if (entries.any((e) => e.endsWith('vbaproject.bin'))) {
      out.add(const ScanFinding(ThreatLevel.warning, engine, 'Makro (VBA) içeren Office belgesi'));
    }
    if (entries.contains('androidmanifest.xml') && entries.contains('classes.dex') && ext != 'apk') {
      out.add(const ScanFinding(ThreatLevel.threat, engine, 'Uzantısı gizlenmiş Android uygulaması (APK)'));
    }
    final inner = entries.where((e) => _execExt.contains(_ext(e)) && !e.endsWith('/')).toList();
    if (inner.isNotEmpty && !const {'jar', 'apk', 'appx', 'msix'}.contains(ext)) {
      out.add(ScanFinding(ThreatLevel.warning, engine,
          'Arşivde ${inner.length} çalıştırılabilir dosya var (ör. ${p.basename(inner.first)})'));
    }
  }

  // Legacy Office (OLE2) with macros.
  if (_startsWith(head, const [0xD0, 0xCF, 0x11, 0xE0]) &&
      _indexOf(head, const [0x5F, 0x00, 0x56, 0x00, 0x42, 0x00, 0x41, 0x00]) >= 0) {
    out.add(const ScanFinding(ThreatLevel.warning, engine, 'Makro içeren eski Office belgesi'));
  }

  // PDF with active content.
  if (_startsWith(head, ascii.encode('%PDF'))) {
    final body = tail == null ? head : Uint8List.fromList([...head, ...tail]);
    for (final k in const ['/JavaScript', '/Launch', '/EmbeddedFile']) {
      if (_indexOf(body, ascii.encode(k)) >= 0) {
        out.add(ScanFinding(ThreatLevel.warning, engine, 'PDF etkin içerik barındırıyor ($k)'));
        break;
      }
    }
  }
  return out;
}

class MalwareScanner {
  MalwareScanner(this.options);
  ScanOptions Function() options;

  static String? get defenderPath {
    if (!Platform.isWindows) return null;
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final path = p.join(pf, 'Windows Defender', 'MpCmdRun.exe');
    return File(path).existsSync() ? path : null;
  }

  /// Engines available on this device (for the settings page).
  List<String> availableEngines() => [
        'JinjaPeer kontrolleri',
        if (options().useDefender && defenderPath != null) 'Microsoft Defender',
        if (options().virusTotalKey.trim().isNotEmpty) 'VirusTotal (özet sorgusu)',
      ];

  Future<ScanReport?> scanFile(String path, {required String displayName, required String sha256}) async {
    final opt = options();
    if (!opt.enabled) return null;
    final engines = <String>['JinjaPeer'];
    final findings = <ScanFinding>[];
    final report = ScanReport(findings, engines);
    final f = File(path);

    try {
      final len = await f.length();
      final raf = await f.open();
      try {
        final head = await raf.read(64 * 1024);
        Uint8List? tail;
        if (len > head.length) {
          final tailLen = len > 4 * 1024 * 1024 ? 1024 * 1024 : len - head.length;
          await raf.setPosition(len - tailLen);
          tail = await raf.read(tailLen);
        }
        findings.addAll(inspect(displayName, head, tail: tail));
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      report.removedByAntivirus = true;
      findings.add(const ScanFinding(ThreatLevel.threat, 'Antivirüs',
          'Dosya sistemdeki antivirüs tarafından engellendi ya da silindi'));
      return report;
    }

    final defender = opt.useDefender ? defenderPath : null;
    if (defender != null) {
      engines.add('Microsoft Defender');
      findings.addAll(await _defender(defender, path, report));
    }

    final vtKey = opt.virusTotalKey.trim();
    if (vtKey.isNotEmpty && sha256.isNotEmpty) {
      final vt = await _virusTotal(vtKey, sha256);
      if (vt != null) {
        engines.add('VirusTotal');
        findings.addAll(vt);
      }
    }
    if (!report.removedByAntivirus && !await f.exists()) {
      report.removedByAntivirus = true;
      findings.add(const ScanFinding(ThreatLevel.threat, 'Antivirüs',
          'Dosya sistemdeki antivirüs tarafından engellendi ya da silindi'));
    }
    return report;
  }

  Future<List<ScanFinding>> _defender(String exe, String path, ScanReport report) async {
    try {
      final r = await Process.run(
        exe,
        ['-Scan', '-ScanType', '3', '-File', path, '-DisableRemediation'],
        stdoutEncoding: const SystemEncoding(),
      ).timeout(const Duration(minutes: 3));
      final out = '${r.stdout}';
      if (r.exitCode == 2) {
        final names = RegExp(r'Threat\s*:\s*(.+)', caseSensitive: false)
            .allMatches(out)
            .map((m) => m.group(1)!.trim())
            .toSet();
        return [
          ScanFinding(ThreatLevel.threat, 'Microsoft Defender',
              names.isEmpty ? 'Microsoft Defender tehdit buldu' : 'Microsoft Defender: ${names.join(', ')}'),
        ];
      }
      if (r.exitCode == 0) return const [];
      // Defender off / replaced by another antivirus: not a verdict.
      report.engines.remove('Microsoft Defender');
      return const [];
    } catch (_) {
      report.engines.remove('Microsoft Defender');
      return const [];
    }
  }

  Future<List<ScanFinding>?> _virusTotal(String key, String sha256) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('https://www.virustotal.com/api/v3/files/$sha256'));
      req.headers.set('x-apikey', key);
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) {
        return const [ScanFinding(ThreatLevel.clean, 'VirusTotal', 'VirusTotal bu dosyayı daha önce görmemiş')];
      }
      if (res.statusCode != 200) return null;
      final stats = ((jsonDecode(body) as Map)['data']['attributes']['last_analysis_stats']) as Map;
      final mal = (stats['malicious'] as num?)?.toInt() ?? 0;
      final sus = (stats['suspicious'] as num?)?.toInt() ?? 0;
      final total = stats.values.whereType<num>().fold<int>(0, (a, b) => a + b.toInt());
      if (mal > 0) {
        return [ScanFinding(ThreatLevel.threat, 'VirusTotal', 'VirusTotal: $mal/$total motor zararlı buldu')];
      }
      if (sus > 0) {
        return [ScanFinding(ThreatLevel.warning, 'VirusTotal', 'VirusTotal: $sus/$total motor şüpheli buldu')];
      }
      return const [];
    } catch (_) {
      return null; // offline / rate limited – not a verdict
    } finally {
      client.close(force: true);
    }
  }
}
