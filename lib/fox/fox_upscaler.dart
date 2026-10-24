// Foxfin 2.8.3: GPU-Upscaling-Shader für mpv (FSR 1.0 / Anime4K, beide MIT,
// siehe NOTICE). GPL-3.0, see NOTICE.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../preference/fox_ui_prefs.dart';

const _fsr = ['FSR.glsl'];
const _anime4k = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_S.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl',
];

/// Liefert den Wert für mpv `glsl-shaders` (leer = aus). Die Shader werden
/// einmalig aus den Assets in den App-Support-Ordner kopiert.
Future<String> foxUpscalerShaderList() async {
  if (FoxUi.lowMemoryDevice) return '';
  final files = switch (FoxUi.upscaler) {
    'fsr' => _fsr,
    'anime4k' => _anime4k,
    _ => const <String>[],
  };
  if (files.isEmpty) return '';
  try {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/fox_shaders');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final paths = <String>[];
    for (final f in files) {
      final out = File('${dir.path}/$f');
      if (!out.existsSync() || out.lengthSync() == 0) {
        final data = await rootBundle.load('assets/shaders/$f');
        await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      paths.add(out.path);
    }
    return paths.join(Platform.isWindows ? ';' : ':');
  } catch (_) {
    return '';
  }
}
