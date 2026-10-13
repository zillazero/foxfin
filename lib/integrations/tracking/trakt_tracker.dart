// Foxfin: Trakt.tv client (OAuth device flow, scrobble, sync).
// GPL-2.0-or-later, see NOTICE.
import 'package:dio/dio.dart';

import 'tracker.dart';
import 'tracking_config.dart';

class TraktTracker implements Tracker {
  static const _base = 'https://api.trakt.tv';
  final Dio _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': TrackingConfig.traktClientId,
      'User-Agent': 'Foxfin/2.7.2',
    },
    validateStatus: (_) => true,
  ));

  @override
  String get id => 'trakt';
  @override
  String get displayName => 'Trakt';

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
    final r = await _dio.post('/oauth/device/code',
        data: {'client_id': TrackingConfig.traktClientId});
    if (r.statusCode != 200) throw StateError('Trakt: ${r.statusCode}');
    final d = r.data as Map;
    return DeviceCode(
      deviceCode: d['device_code'],
      userCode: d['user_code'],
      verificationUrl: d['verification_url'] ?? 'https://trakt.tv/activate',
      interval: Duration(seconds: (d['interval'] as num?)?.toInt() ?? 5),
      expiresAt: DateTime.now()
          .add(Duration(seconds: (d['expires_in'] as num?)?.toInt() ?? 600)),
    );
  }

  @override
  Future<Map<String, dynamic>?> pollDeviceAuth(DeviceCode code) async {
    final r = await _dio.post('/oauth/device/token', data: {
      'code': code.deviceCode,
      'client_id': TrackingConfig.traktClientId,
      'client_secret': TrackingConfig.traktClientSecret,
    });
    switch (r.statusCode) {
      case 200:
        return _stamp(Map<String, dynamic>.from(r.data as Map));
      case 400: // pending
      case 429: // slow down
        return null;
      default:
        throw StateError('Trakt-Anmeldung fehlgeschlagen (${r.statusCode})');
    }
  }

  Map<String, dynamic> _stamp(Map<String, dynamic> t) {
    final created = (t['created_at'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expires = (t['expires_in'] as num?)?.toInt() ?? 86400 * 7;
    t['expires_at'] = created + expires;
    return t;
  }

  @override
  Future<Map<String, dynamic>?> refreshIfNeeded(
      Map<String, dynamic> token) async {
    final exp = (token['expires_at'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp - now > 86400) return null;
    final r = await _dio.post('/oauth/token', data: {
      'refresh_token': token['refresh_token'],
      'client_id': TrackingConfig.traktClientId,
      'client_secret': TrackingConfig.traktClientSecret,
      'redirect_uri': 'urn:ietf:wg:oauth:2.0:oob',
      'grant_type': 'refresh_token',
    });
    if (r.statusCode != 200) return null;
    return _stamp(Map<String, dynamic>.from(r.data as Map));
  }

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

  Future<List> _getList(String path) async {
    final r = await _dio.get(path);
    if (r.statusCode != 200 || r.data is! List) {
      throw StateError('Trakt $path: ${r.statusCode}');
    }
    return r.data as List;
  }

  @override
  Future<List<TrackedItem>> getWatched() async {
    final out = <TrackedItem>[];
    for (final m in await _getList('/sync/watched/movies')) {
      out.add(TrackedItem.movie(MediaIds.fromJson(m['movie']?['ids'])));
    }
    for (final s in await _getList('/sync/watched/shows')) {
      final ids = MediaIds.fromJson(s['show']?['ids']);
      for (final season in (s['seasons'] as List? ?? const [])) {
        for (final e in (season['episodes'] as List? ?? const [])) {
          out.add(TrackedItem.episode(ids, (season['number'] as num).toInt(),
              (e['number'] as num).toInt()));
        }
      }
    }
    return out;
  }

  Future<void> _postChunked(String path, List<TrackedItem> items) async {
    for (var i = 0; i < items.length; i += 100) {
      final chunk = items.sublist(i, (i + 100).clamp(0, items.length));
      await _dio.post(path, data: groupedBody(chunk));
      // Trakt allows ~1 write per second.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
  }

  @override
  Future<void> addToHistory(List<TrackedItem> items) =>
      _postChunked('/sync/history', items);

  @override
  Future<List<TrackedItem>> getWatchlist() async {
    final out = <TrackedItem>[];
    for (final m in await _getList('/sync/watchlist/movies')) {
      out.add(TrackedItem.movie(MediaIds.fromJson(m['movie']?['ids'])));
    }
    for (final s in await _getList('/sync/watchlist/shows')) {
      out.add(TrackedItem.show(MediaIds.fromJson(s['show']?['ids'])));
    }
    return out;
  }

  @override
  Future<void> addToWatchlist(List<TrackedItem> items) =>
      _postChunked('/sync/watchlist', items);

  @override
  Future<List<PlaybackProgress>> getPlaybackProgress() async {
    final out = <PlaybackProgress>[];
    for (final p in await _getList('/sync/playback?limit=100')) {
      final pct = (p['progress'] as num?)?.toDouble() ?? 0;
      if (p['type'] == 'movie') {
        out.add(PlaybackProgress(
            TrackedItem.movie(MediaIds.fromJson(p['movie']?['ids'])), pct));
      } else if (p['type'] == 'episode') {
        out.add(PlaybackProgress(
            TrackedItem.episode(
                MediaIds.fromJson(p['show']?['ids']),
                (p['episode']?['season'] as num?)?.toInt(),
                (p['episode']?['number'] as num?)?.toInt()),
            pct));
      }
    }
    return out;
  }
}
