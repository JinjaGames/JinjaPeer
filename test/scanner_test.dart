import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jinja_peer/services/scanner.dart';

Uint8List b(List<int> x) => Uint8List.fromList(x);

/// Minimal ZIP central directory entry for [name] (enough for the scanner).
List<int> cdEntry(String name) {
  final n = utf8.encode(name);
  final e = Uint8List(46 + n.length);
  e.setAll(0, [0x50, 0x4B, 0x01, 0x02]);
  ByteData.sublistView(e).setUint16(28, n.length, Endian.little);
  e.setAll(46, n);
  return e;
}

Uint8List zipOf(List<String> names) =>
    b([0x50, 0x4B, 0x03, 0x04, ...List.filled(60, 0), for (final n in names) ...cdEntry(n)]);

ThreatLevel levelOf(List<ScanFinding> f) =>
    f.fold(ThreatLevel.clean, (a, x) => x.level.index > a.index ? x.level : a);

void main() {
  final png = File('assets/icon.png').readAsBytesSync();

  test('real image is clean', () {
    expect(inspect('tatil.png', b(png.sublist(0, 65536))), isEmpty);
  });

  test('EICAR test signature is a threat', () {
    final f = inspect('not.txt', b(ascii.encode(eicarTestString())));
    expect(levelOf(f), ThreatLevel.threat);
    expect(f.first.message, contains('EICAR'));
  });

  test('program disguised as a photo is a threat', () {
    final pe = b([0x4D, 0x5A, 0x90, 0x00, ...List.filled(200, 0)]);
    final f = inspect('tatil.jpg', pe);
    expect(levelOf(f), ThreatLevel.threat);
    expect(f.map((x) => x.message).join(), contains('Windows programı'));
    // A real .exe is only a warning (the user knowingly receives a program).
    expect(levelOf(inspect('kurulum.exe', pe)), ThreatLevel.warning);
  });

  test('double extension trick is a threat', () {
    final f = inspect('fatura.pdf.exe', b([0x4D, 0x5A, 0, 0]));
    expect(levelOf(f), ThreatLevel.threat);
    expect(f.map((x) => x.message).join(), contains('Çift uzantı'));
  });

  test('ELF / Mach-O disguised as documents are threats, scripts warn', () {
    expect(levelOf(inspect('rapor.pdf', b([0x7F, 0x45, 0x4C, 0x46, 2, 1]))), ThreatLevel.threat);
    expect(levelOf(inspect('rapor.docx', b([0xCF, 0xFA, 0xED, 0xFE, 7]))), ThreatLevel.threat);
    expect(levelOf(inspect('liste.txt', b(ascii.encode('#!/bin/sh\nrm -rf ~')))), ThreatLevel.warning);
  });

  test('archives and office files', () {
    final withExe = zipOf(['foto.jpg', 'gizli/setup.exe']);
    final f = inspect('fotolar.zip', withExe.sublist(0, 64), tail: withExe);
    expect(levelOf(f), ThreatLevel.warning);
    expect(f.single.message, contains('setup.exe'));

    final macro = zipOf(['[Content_Types].xml', 'word/document.xml', 'word/vbaProject.bin']);
    expect(inspect('teklif.docx', macro.sublist(0, 64), tail: macro).single.message, contains('Makro'));

    final apk = zipOf(['AndroidManifest.xml', 'classes.dex', 'res/a.png']);
    expect(levelOf(inspect('oyun.zip', apk.sublist(0, 64), tail: apk)), ThreatLevel.threat);

    final clean = zipOf(['a.txt', 'b/c.png']);
    expect(inspect('arsiv.zip', clean.sublist(0, 64), tail: clean), isEmpty);
  });

  test('PDF with JavaScript is a warning, plain PDF is clean', () {
    expect(levelOf(inspect('a.pdf', b(ascii.encode('%PDF-1.7\n1 0 obj << /OpenAction << /JavaScript (x) >> >>')))),
        ThreatLevel.warning);
    expect(inspect('a.pdf', b(ascii.encode('%PDF-1.7\n1 0 obj << /Type /Page >>'))), isEmpty);
  });

  test('scanFile: disabled scanning returns null, file scan finds disguised exe', () async {
    final dir = await Directory.systemTemp.createTemp('jp_scan');
    final f = File('${dir.path}/kedi.png')..writeAsBytesSync([0x4D, 0x5A, ...List.filled(100, 0)]);
    final off = MalwareScanner(() => const ScanOptions(enabled: false));
    expect(await off.scanFile(f.path, displayName: 'kedi.png', sha256: ''), isNull);
    final on = MalwareScanner(() => const ScanOptions(useDefender: false));
    final r = (await on.scanFile(f.path, displayName: 'kedi.png', sha256: ''))!;
    expect(r.isThreat, isTrue);
    expect(r.engines, ['JinjaPeer']);
    await dir.delete(recursive: true);
  });
}
