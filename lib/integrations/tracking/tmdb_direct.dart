// Foxfin: direct TMDB fallback for ratings when the Moonfin server plugin is
// not installed. Only active with a TMDB key in the local build config.
// GPL-2.0-or-later, see NOTICE.
import 'package:dio/dio.dart';

import 'tracking_config.dart';

class TmdbDirect {
  TmdbDirect._();
  static final TmdbDirect instance = TmdbDirect._();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.themoviedb.org/3',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (_) => true,
  ));

  bool get available => TrackingConfig.tmdbAvailable;

  Future<Map?> _get(String path) async {
    if (!available) return null;
    final key = TrackingConfig.tmdbApiKey;
    // v4 read tokens are long JWTs, v3 keys are 32 hex chars.
    final r = key.length > 40
        ? await _dio.get(path,
            options: Options(headers: {'Authorization': 'Bearer $key'}))
        : await _dio.get(path, queryParameters: {'api_key': key});
    return r.statusCode == 200 && r.data is Map ? r.data as Map : null;
  }

  Future<double?> episodeRating(String tvId, int season, int episode) async {
    final d = await _get('/tv/$tvId/season/$season/episode/$episode');
    final v = (d?['vote_average'] as num?)?.toDouble();
    return v != null && v > 0 ? v : null;
  }

  Future<Map<int, double>?> seasonRatings(String tvId, int season) async {
    final d = await _get('/tv/$tvId/season/$season');
    final eps = d?['episodes'] as List?;
    if (eps == null) return null;
    final out = <int, double>{};
    for (final e in eps) {
      final n = (e['episode_number'] as num?)?.toInt();
      final v = (e['vote_average'] as num?)?.toDouble();
      if (n != null && v != null && v > 0) out[n] = v;
    }
    return out;
  }
}
