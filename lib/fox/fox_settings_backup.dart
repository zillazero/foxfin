// Foxfin 2.8.5: Einstellungen sichern/wiederherstellen (ohne Geheimnisse).
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

final RegExp _foxSecretKey = RegExp(
  r'token|secret|passw|(^|_)pin(_|$)|apikey|api_key|auth|cookie|session|credential|'
  r'server|user_?id|device_?id|account|login|cert|quick_?connect|sso|keys',
  caseSensitive: false,
);

bool foxBackupKeyAllowed(String key) => !_foxSecretKey.hasMatch(key);

Future<Map<String, Object?>> foxBuildBackup() async {
  final prefs = await SharedPreferences.getInstance();
  final out = <String, Object?>{};
  for (final k in prefs.getKeys()) {
    if (!foxBackupKeyAllowed(k)) continue;
    final v = prefs.get(k);
    if (v is String && v.length > 4096) continue;
    out[k] = v;
  }
  return {'format': 'foxfin-settings', 'version': 1, 'prefs': out};
}

/// Returns 'saved', 'cancel' or an error string.
Future<String> foxExportSettings() async {
  final data = await foxBuildBackup();
  final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent(' ').convert(data)));
  final path = await FilePicker.saveFile(
    dialogTitle: 'Einstellungen sichern',
    fileName: 'foxfin-einstellungen.json',
    bytes: bytes,
  );
  return path == null ? 'cancel' : 'saved';
}

/// Returns the number of restored values, or -1 when cancelled.
Future<int> foxImportSettings() async {
  final res = await FilePicker.pickFiles(
    dialogTitle: 'Einstellungen wiederherstellen',
    withData: true,
  );
  final bytes = res?.files.single.bytes;
  if (bytes == null) return -1;
  final json = jsonDecode(utf8.decode(bytes));
  if (json is! Map || json['format'] != 'foxfin-settings') {
    throw const FormatException('Keine Foxfin-Sicherung');
  }
  final prefs = await SharedPreferences.getInstance();
  var n = 0;
  final map = (json['prefs'] as Map).cast<String, Object?>();
  for (final e in map.entries) {
    if (!foxBackupKeyAllowed(e.key)) continue;
    final v = e.value;
    if (v is bool) {
      await prefs.setBool(e.key, v);
    } else if (v is int) {
      await prefs.setInt(e.key, v);
    } else if (v is double) {
      await prefs.setDouble(e.key, v);
    } else if (v is String) {
      await prefs.setString(e.key, v);
    } else if (v is List) {
      await prefs.setStringList(e.key, v.map((x) => '$x').toList());
    } else {
      continue;
    }
    n++;
  }
  return n;
}

/// 'player' | 'store' | 'web' | 'none'
Future<String> foxOpenFoxPlayer() async {
  try {
    return await const MethodChannel('fox_sso')
            .invokeMethod<String>('openFoxPlayer') ??
        'none';
  } catch (_) {
    return 'none';
  }
}

// Foxfin 2.9.0: lokale Absturzberichte exportieren / löschen.
const _foxCrashKey = 'fox_local_crash_reports_v1';

Future<int> foxCrashReportCount() async =>
    ((await SharedPreferences.getInstance()).getStringList(_foxCrashKey) ??
            const <String>[])
        .length;

Future<String> foxExportCrashReports() async {
  final list = (await SharedPreferences.getInstance())
          .getStringList(_foxCrashKey) ??
      const <String>[];
  if (list.isEmpty) return 'empty';
  final path = await FilePicker.saveFile(
    dialogTitle: 'Absturzberichte exportieren',
    fileName: 'foxfin-absturzberichte.txt',
    bytes: Uint8List.fromList(utf8.encode(list.join('\n\n'))),
  );
  return path == null ? 'cancel' : 'saved';
}

Future<void> foxClearCrashReports() async =>
    (await SharedPreferences.getInstance()).remove(_foxCrashKey);
