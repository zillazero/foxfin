// Foxfin: Simkl client (PIN/device flow, scrobble, sync).
// GPL-2.0-or-later, see NOTICE.
import 'package:dio/dio.dart';

import 'tracker.dart';
import 'tracking_config.dart';

class SimklTracker implements Tracker {
  static const _base = 'https://api.simkl.com';
  final Dio _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Content-Type': 'application/json',
      'simkl-api-key': TrackingConfig.simklClientId,
      'User-Agent': 'Foxfin/2.7.2',
    },
    queryParameters: {
      'client_id': TrackingConfig.simklClientId,
      'app-name': 'foxfin',
      'app-version': '2.7.2',
    },
    validateStatus: (_) => true,
  ));

  @override
  String get id => 'simkl';
  @override
  String get displayName => 'Simkl';

  @override
  void useToken(Map<String, dynamic>? token) {
    final t = token?['access_token'];
    if (t == null) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $t';
    }
  }

  @override
  Future<DeviceCode> startDeviceAuth() async {
    final r = await _dio.get('/oauth/pin');
    if (r.statusCode != 200) throw StateError('Simkl: ${r.statusCode}');
    final d = r.data as Map;
    return DeviceCode(
      deviceCode: d['user_code'],
      userCode: d['user_code'],
      verificationUrl: d['verification_url'] ?? 'https://simkl.com/pin',
      interval: Duration(seconds: (d['interval'] as num?)?.toInt() ?? 5),
      expiresAt: DateTime.now()
          .add(Duration(seconds: (d['expires_in'] as num?)?.toInt() ?? 900)),
    );
  }

  @override
  Future<Map<String, dynamic>?> pollDeviceAuth(DeviceCode code) async {
    final r = await _dio.get('/oauth/pin/${code.deviceCode}');
    if (r.statusCode != 200 || r.data is! Map) return null;
    final d = r.data as Map;
    if (d['result'] == 'OK' && d['access_token'] != null) {
      return {'access_token': d['access_token']};
    }
    if (d['result'] == 'KO' && d['message'] != null &&
        d['message'] != 'Authorization pending') {
      final msg = d['message'].toString();
      if (msg.toLowerCase().contains('expired')) throw StateError(msg);
    }
    return null;
  }

  // Simkl tokens do not expire.
  @override
  Future<Map<String, dynamic>?> refreshIfNeeded(
          Map<String, dynamic> token) async =>
      null;

  Map<String, dynamic> _itemBody(TrackedItem it) => it.isEpisode
      ? {
          'show': {'ids': it.ids.toJson()},
          'episode': {'season': it.season, 'number': it.episode},
        }
      : {
          'movie': {'ids': it.ids.toJson()},
        };

  @override
  Future<void> scrobble(
      ScrobbleAction action, TrackedItem item, double percent) async {
    await _dio.post('/scrobble/${action.name}',
        data: {..._itemBody(item), 'progress': percent.clamp(0, 100)});
  }

  Future<Map> _getMap(String path, [Map<String, dynamic>? q]) async {
    final r = await _dio.get(path, queryParameters: q);
    if (r.statusCode != 200) throw StateError('Simkl $path: ${r.statusCode}');
    return r.data is Map ? r.data as Map : const {};
  }

  @override
  Future<List<TrackedItem>> getWatched() async {
    final out = <TrackedItem>[];
    final movies = await _getMap('/sync/all-items/movies/completed');
    for (final m in (movies['movies'] as List? ?? const [])) {
      out.add(TrackedItem.movie(MediaIds.fromJson(m['movie']?['ids'])));
    }
    for (final type in ['shows', 'anime']) {
      final shows = await _getMap(
          '/sync/all-items/$type', {'extended': 'full', 'episode_watched_at': 'yes'});
      for (final s in (shows[type] as List? ?? const [])) {
        final ids = MediaIds.fromJson(s['show']?['ids']);
        for (final season in (s['seasons'] as List? ?? const [])) {
          for (final e in (season['episodes'] as List? ?? const [])) {
            out.add(TrackedItem.episode(ids, (season['number'] as num).toInt(),
                (e['number'] as num).toInt()));
          }
        }
      }
    }
    return out;
  }

  @override
  Future<void> addToHistory(List<TrackedItem> items) async {
    for (var i = 0; i < items.length; i += 100) {
      await _dio.post('/sync/history',
          data: groupedBody(items.sublist(i, (i + 100).clamp(0, items.length))));
    }
  }

  @override
  Future<List<TrackedItem>> getWatchlist() async {
    final out = <TrackedItem>[];
    final movies = await _getMap('/sync/all-items/movies/plantowatch');
    for (final m in (movies['movies'] as List? ?? const [])) {
      out.add(TrackedItem.movie(MediaIds.fromJson(m['movie']?['ids'])));
    }
    final shows = await _getMap('/sync/all-items/shows/plantowatch');
    for (final s in (shows['shows'] as List? ?? const [])) {
      out.add(TrackedItem.show(MediaIds.fromJson(s['show']?['ids'])));
    }
    return out;
  }

  @override
  Future<void> addToWatchlist(List<TrackedItem> items) async {
    final body = groupedBody(items, movieExtra: (_) => {'to': 'plantowatch'});
    for (final s in (body['shows'] as List? ?? const [])) {
      (s as Map)['to'] = 'plantowatch';
    }
    await _dio.post('/sync/add-to-list', data: body);
  }

  @override
  Future<List<PlaybackProgress>> getPlaybackProgress() async {
    final r = await _dio.get('/sync/playback');
    if (r.statusCode != 200 || r.data is! List) return const [];
    final out = <PlaybackProgress>[];
    for (final p in r.data as List) {
      final pct = (p['progress'] as num?)?.toDouble() ?? 0;
      if (p['type'] == 'movie') {
        out.add(PlaybackProgress(
            TrackedItem.movie(MediaIds.fromJson(p['movie']?['ids'])), pct));
      } else if (p['type'] == 'episode') {
        out.add(PlaybackProgress(
            TrackedItem.episode(
                MediaIds.fromJson(p['show']?['ids']),
                (p['episode']?['season'] as num?)?.toInt(),
                ((p['episode']?['episode'] ?? p['episode']?['number']) as num?)
                    ?.toInt()),
            pct));
      }
    }
    return out;
  }
}
