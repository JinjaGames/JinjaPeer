import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper over the native Android helpers in MainActivity.kt.
abstract final class AndroidBridge {
  static const _ch = MethodChannel('jinjapeer/android');

  static bool get available => Platform.isAndroid;

  /// Moves [path] into the public Downloads/JinjaPeer folder.
  /// Returns `{uri, path}` or null when it had to stay in the app folder.
  static Future<Map<String, String>?> saveToDownloads(String path, String name, String relDir) async {
    if (!available) return null;
    final r = await _ch.invokeMapMethod<String, String>(
        'saveToDownloads', {'path': path, 'name': name, 'relDir': relDir});
    return r;
  }

  static Future<bool> open(String target) async =>
      available && (await _ch.invokeMethod<bool>('open', {'target': target}) ?? false);

  static Future<bool> share(String target) async =>
      available && (await _ch.invokeMethod<bool>('share', {'target': target}) ?? false);

  static Future<bool> openDownloads() async =>
      available && (await _ch.invokeMethod<bool>('openDownloads') ?? false);

  static Future<bool> exists(String target) async =>
      available && (await _ch.invokeMethod<bool>('exists', {'target': target}) ?? false);

  static Future<void> transferRunning(String text, int progress) async {
    if (!available) return;
    await _ch.invokeMethod('updateTransfer', {'text': text, 'progress': progress});
  }

  static Future<void> transferStopped() async {
    if (!available) return;
    await _ch.invokeMethod('stopTransfer');
  }
}
