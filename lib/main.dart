import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'services/app_controller.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/chrome.dart';
import 'ui/widgets/liquid_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  if (desktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(960, 640),
      center: true,
      title: 'JinjaPeer',
      backgroundColor: Color(0xFF0A0E1A),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  final controller = await AppController.load();
  Motion.reduce = controller.settings.reduceMotion;
  if (desktop) {
    await windowManager.setPreventClose(true);
    windowManager.addListener(_CloseGuard(controller));
  }
  runApp(JinjaPeerApp(controller: controller));
}

/// Closes peer connections cleanly and flushes data before the window closes.
class _CloseGuard with WindowListener {
  _CloseGuard(this.controller);
  final AppController controller;

  @override
  void onWindowClose() async {
    try {
      await controller.shutdown().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await windowManager.destroy();
  }
}

class JinjaPeerApp extends StatelessWidget {
  const JinjaPeerApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: Builder(builder: (context) {
        final mode = context.app.settings.themeMode;
        return MaterialApp(
          title: 'JinjaPeer',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(JP.light),
          darkTheme: buildTheme(JP.dark),
          themeMode: mode,
          themeAnimationDuration: Motion.d(350),
          home: const Scaffold(
            backgroundColor: Colors.transparent,
            body: ToastHost(child: Shell()),
          ),
        );
      }),
    );
  }
}
