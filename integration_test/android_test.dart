// ignore_for_file: avoid_print
// Runs on an Android device/emulator: native bridge + scanner on Android.
//   flutter test integration_test/android_test.dart -d emulator-5554
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jinja_peer/services/android_bridge.dart';
import 'package:jinja_peer/services/scanner.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('received file is published to public Downloads/JinjaPeer', (tester) async {
    await tester.runAsync(() async {
      if (!Platform.isAndroid) return;
      final dir = await getTemporaryDirectory();
      final name = 'jp_test_${DateTime.now().millisecondsSinceEpoch}.png';
      final src = File('${dir.path}/$name')..writeAsBytesSync(List.generate(50000, (i) => i % 251));
      final r = await AndroidBridge.saveToDownloads(src.path, name, 'Deneme');
      expect(r, isNotNull, reason: 'MediaStore insert must succeed');
      expect(r!['uri'], startsWith('content://'));
      expect(r['path'], contains('JinjaPeer/Deneme/$name'));
      expect(src.existsSync(), isFalse, reason: 'private copy is removed');
      expect(await AndroidBridge.exists(r['uri']!), isTrue);

      // Same name again → Android picks a new name, nothing is overwritten.
      final src2 = File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);
      final r2 = await AndroidBridge.saveToDownloads(src2.path, name, 'Deneme');
      expect(r2!['uri'], isNot(r['uri']));
      print('saved: ${r['path']}  |  second: ${r2['path']}');
    });
  });

  testWidgets('foreground transfer service starts and stops', (tester) async {
    await tester.runAsync(() async {
      if (!Platform.isAndroid) return;
      await AndroidBridge.transferRunning('Test aktarımı · %40', 40);
      await Future<void>.delayed(const Duration(seconds: 1));
      await AndroidBridge.transferRunning('Test aktarımı · %80', 80);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await AndroidBridge.transferStopped();
    });
  });

  testWidgets('scanner works on Android (JinjaPeer engine)', (tester) async {
    await tester.runAsync(() async {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/kedi.jpg')..writeAsBytesSync([0x4D, 0x5A, 0x90, 0, ...List.filled(500, 0)]);
      final r = (await MalwareScanner(() => const ScanOptions()).scanFile(f.path, displayName: 'kedi.jpg', sha256: ''))!;
      expect(r.isThreat, isTrue);
      expect(r.engines, ['JinjaPeer']);
      final ok = File('${dir.path}/not.txt')..writeAsStringSync('merhaba');
      final r2 = (await MalwareScanner(() => const ScanOptions()).scanFile(ok.path, displayName: 'not.txt', sha256: ''))!;
      expect(r2.level, ThreatLevel.clean);
    });
  });
}
