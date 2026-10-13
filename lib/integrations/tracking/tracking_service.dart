// Foxfin: links Trakt/Simkl accounts to the signed-in Jellyfin/Emby user and
// keeps watched state, watchlist (<-> favourites) and resume points in sync.
// GPL-2.0-or-later, see NOTICE.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fox_sso/fox_sync_service.dart';
import 'simkl_tracker.dart';
import 'tracker.dart';
import 'tracking_config.dart';
import 'trakt_tracker.dart';

class TrackerSettings {
  bool scrobble;
  bool syncWatched;
  bool syncWatchlist;
  bool syncResume;
  TrackerSettings({
    this.scrobble = true,
    this.syncWatched = true,
    this.syncWatchlist = false,
    this.syncResume = true,
  });
  Map<String, dynamic> toJson() => {
        'scrobble': scrobble,
        'syncWatched': syncWatched,
        'syncWatchlist': syncWatchlist,
        'syncResume': syncResume,
      };
  static TrackerSettings fromJson(Map? j) => TrackerSettings(
        scrobble: j?['scrobble'] ?? true,
        syncWatched: j?['syncWatched'] ?? true,
        syncWatchlist: j?['syncWatchlist'] ?? false,
        syncResume: j?['syncResume'] ?? true,
      );
}

class SyncReport {
  int importedWatched = 0;
  int exportedWatched = 0;
  int importedFavorites = 0;
  int exportedWatchlist = 0;
  int resumePoints = 0;
  String? error;
  @override
  String toString() => error != null
      ? 'Fehler: $error'
      : 'Gesehen: $importedWatched importiert, $exportedWatched exportiert · '
          'Merkliste: $importedFavorites → Favoriten, $exportedWatchlist exportiert · '
          'Weiterschauen: $resumePoints';
}

class _LocalItem {
  final String id;
  final TrackedItem item;
  final bool played;
  final bool favorite;
  final int positionTicks;
  final int runtimeTicks;
  _LocalItem(this.id, this.item, this.played, this.favorite,
      this.positionTicks, this.runtimeTicks);
}

class TrackingService extends ChangeNotifier {
  TrackingService();

  static const _storage = FlutterSecureStorage();
  static const _autoSyncInterval = Duration(hours: 6);

  final Map<String, Tracker> trackers = {
    if (TrackingConfig.traktAvailable) 'trakt': TraktTracker(),
    if (TrackingConfig.simklAvailable) 'simkl': SimklTracker(),
  };

  final Map<String, Map<String, dynamic>?> _tokens = {};
  final Map<String, TrackerSettings> _settings = {};
  String? _loadedFor;
  bool _syncing = false;
  bool get syncing => _syncing;
  String? lastReport;

  MediaServerClient? get _client => GetIt.instance.isRegistered<MediaServerClient>()
      ? GetIt.instance<MediaServerClient>()
      : null;

  String get _scope {
    final c = _client;
    return '${c?.baseUrl ?? ''}|${c?.userId ?? ''}';
  }

  String _key(String tracker, String what) =>
      'foxfin.$tracker.$what.${base64Url.encode(utf8.encode(_scope))}';

  Future<void> _ensureLoaded() async {
    if (_loadedFor == _scope) return;
    _loadedFor = _scope;
    final prefs = await SharedPreferences.getInstance();
    for (final t in trackers.values) {
      String? raw;
      try {
        raw = await _storage.read(key: _key(t.id, 'token'));
      } catch (_) {}
      final tok = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      _tokens[t.id] = tok;
      t.useToken(tok);
      final s = prefs.getString(_key(t.id, 'settings'));
      _settings[t.id] =
          TrackerSettings.fromJson(s == null ? null : jsonDecode(s) as Map);
    }
    notifyListeners();
  }

  Future<void> load() => _ensureLoaded();

  bool isLinked(String id) => _tokens[id] != null;
  TrackerSettings settingsFor(String id) =>
      _settings[id] ??= TrackerSettings();

  Future<void> saveSettings(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(id, 'settings'), jsonEncode(settingsFor(id).toJson()));
    notifyListeners();
  }

  Future<void> storeToken(String id, Map<String, dynamic>? token) async {
    _tokens[id] = token;
    trackers[id]?.useToken(token);
    if (token == null) {
      await _storage.delete(key: _key(id, 'token'));
    } else {
      await _storage.write(key: _key(id, 'token'), value: jsonEncode(token));
    }
    // Foxfin: share only the link status with the FOX account.
    unawaited(FoxSyncService.instance.pushLink(id, token != null));
    notifyListeners();
  }

  Future<Tracker?> _ready(String id) async {
    await _ensureLoaded();
    final t = trackers[id];
    final tok = _tokens[id];
    if (t == null || tok == null) return null;
    try {
      final fresh = await t.refreshIfNeeded(tok);
      if (fresh != null) await storeToken(id, fresh);
    } catch (_) {}
    return t;
  }

  // ---------------------------------------------------------------- scrobble

  final Map<String, TrackedItem?> _itemCache = {};

  Future<({TrackedItem item, int runtimeTicks})?> _resolve(String itemId) async {
    final c = _client;
    if (c == null) return null;
    try {
      final j = await c.itemsApi.getItem(itemId);
      final type = j['Type']?.toString();
      final runtime = (j['RunTimeTicks'] as num?)?.toInt() ?? 0;
      if (type == 'Movie') {
        final ids = MediaIds.fromProviderIds(j['ProviderIds'] as Map?);
        if (ids.isEmpty) return null;
        return (item: TrackedItem.movie(ids), runtimeTicks: runtime);
      }
      if (type == 'Episode' && j['SeriesId'] != null) {
        final s = await c.itemsApi.getItem(j['SeriesId'].toString(),
            fields: 'ProviderIds');
        final ids = MediaIds.fromProviderIds(s['ProviderIds'] as Map?);
        final season = (j['ParentIndexNumber'] as num?)?.toInt();
        final ep = (j['IndexNumber'] as num?)?.toInt();
        if (ids.isEmpty || season == null || ep == null) return null;
        return (item: TrackedItem.episode(ids, season, ep), runtimeTicks: runtime);
      }
    } catch (e) {
      debugPrint('[Foxfin] tracking resolve failed: $e');
    }
    return null;
  }

  final Map<String, int> _runtimes = {};

  /// Called from the playback decorator. Never throws.
  Future<void> onPlayback(
      ScrobbleAction action, String itemId, Duration position) async {
    try {
      await _ensureLoaded();
      final active = trackers.keys
          .where((id) => isLinked(id) && settingsFor(id).scrobble)
          .toList();
      if (active.isEmpty) return;
      if (!_itemCache.containsKey(itemId)) {
        final r = await _resolve(itemId);
        _itemCache[itemId] = r?.item;
        if (r != null) _runtimes[itemId] = r.runtimeTicks;
      }
      final item = _itemCache[itemId];
      if (item == null) return;
      final runtime = _runtimes[itemId] ?? 0;
      final pct = runtime > 0
          ? (position.inMicroseconds * 10 / runtime * 100).clamp(0, 100).toDouble()
          : 0.0;
      for (final id in active) {
        final t = await _ready(id);
        try {
          await t?.scrobble(action, item, pct);
        } catch (e) {
          debugPrint('[Foxfin] $id scrobble failed: $e');
        }
      }
      if (action == ScrobbleAction.stop) _itemCache.remove(itemId);
    } catch (_) {}
  }

  // -------------------------------------------------------------------- sync

  Future<void> maybeAutoSync() async {
    await _ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_key('all', 'lastSync')) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last <
        _autoSyncInterval.inMilliseconds) {
      return;
    }
    if (!trackers.keys.any(isLinked)) return;
    await syncAll();
  }

  Future<String> syncAll() async {
    if (_syncing) return lastReport ?? '';
    _syncing = true;
    notifyListeners();
    final parts = <String>[];
    try {
      await _ensureLoaded();
      final local = await _loadLocal();
      for (final id in trackers.keys.where(isLinked)) {
        final r = await _syncOne(id, local);
        parts.add('${trackers[id]!.displayName}: $r');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _key('all', 'lastSync'), DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      parts.add('Fehler: $e');
    } finally {
      _syncing = false;
      lastReport = parts.join('\n');
      notifyListeners();
    }
    return lastReport!;
  }

  Future<List<_LocalItem>> _loadLocal() async {
    final c = _client;
    if (c == null) return const [];
    final out = <_LocalItem>[];
    final seriesIds = <String, MediaIds>{};
    Future<void> page(List<String> types, void Function(Map) each) async {
      var start = 0;
      while (true) {
        final r = await c.itemsApi.getItems(
          includeItemTypes: types,
          recursive: true,
          fields: 'ProviderIds',
          enableImageTypes: '',
          imageTypeLimit: 0,
          startIndex: start,
          limit: 500,
          enableTotalRecordCount: false,
        );
        final items = (r['Items'] as List? ?? const []);
        for (final i in items) {
          each(i as Map);
        }
        if (items.length < 500) break;
        start += 500;
      }
    }

    int ticks(Map j, String k) => (j[k] as num?)?.toInt() ?? 0;

    await page(['Series'], (j) {
      final ids = MediaIds.fromProviderIds(j['ProviderIds'] as Map?);
      seriesIds[j['Id'].toString()] = ids;
      if (!ids.isEmpty) {
        final ud = j['UserData'] as Map? ?? const {};
        out.add(_LocalItem(j['Id'].toString(), TrackedItem.show(ids), false,
            ud['IsFavorite'] == true, 0, 0));
      }
    });
    await page(['Movie'], (j) {
      final ids = MediaIds.fromProviderIds(j['ProviderIds'] as Map?);
      if (ids.isEmpty) return;
      final ud = j['UserData'] as Map? ?? const {};
      out.add(_LocalItem(j['Id'].toString(), TrackedItem.movie(ids),
          ud['Played'] == true, ud['IsFavorite'] == true,
          ticks(ud, 'PlaybackPositionTicks'), ticks(j, 'RunTimeTicks')));
    });
    await page(['Episode'], (j) {
      final ids = seriesIds[j['SeriesId']?.toString()];
      final s = (j['ParentIndexNumber'] as num?)?.toInt();
      final e = (j['IndexNumber'] as num?)?.toInt();
      if (ids == null || ids.isEmpty || s == null || e == null) return;
      final ud = j['UserData'] as Map? ?? const {};
      out.add(_LocalItem(j['Id'].toString(), TrackedItem.episode(ids, s, e),
          ud['Played'] == true, false,
          ticks(ud, 'PlaybackPositionTicks'), ticks(j, 'RunTimeTicks')));
    });
    return out;
  }

  Set<String> _keySet(Iterable<TrackedItem> items) =>
      {for (final i in items) ...i.keys};
  bool _in(Set<String> set, TrackedItem i) => i.keys.any(set.contains);

  Future<SyncReport> _syncOne(String id, List<_LocalItem> local) async {
    final rep = SyncReport();
    final t = await _ready(id);
    final c = _client;
    if (t == null || c == null) return rep..error = 'nicht verbunden';
    final s = settingsFor(id);
    try {
      final playable = local.where((l) => !l.item.isShow).toList();
      if (s.syncWatched) {
        final remote = _keySet(await t.getWatched());
        final localPlayed = _keySet(playable.where((l) => l.played).map((l) => l.item));
        for (final l in playable) {
          if (!l.played && _in(remote, l.item)) {
            try {
              await c.userLibraryApi.markPlayed(l.id);
              rep.importedWatched++;
            } catch (_) {}
          }
        }
        final toExport = playable
            .where((l) => l.played && !_in(remote, l.item))
            .map((l) => l.item)
            .toList();
        if (toExport.isNotEmpty) await t.addToHistory(toExport);
        rep.exportedWatched = toExport.length;
        localPlayed.clear();
      }
      if (s.syncWatchlist) {
        final remote = _keySet(await t.getWatchlist());
        final candidates = local.where((l) => !l.item.isEpisode || l.item.isShow);
        for (final l in candidates) {
          if (!l.favorite && _in(remote, l.item)) {
            try {
              await c.userLibraryApi.markFavorite(l.id);
              rep.importedFavorites++;
            } catch (_) {}
          }
        }
        final toExport = candidates
            .where((l) => l.favorite && !_in(remote, l.item))
            .map((l) => l.item)
            .toList();
        if (toExport.isNotEmpty) await t.addToWatchlist(toExport);
        rep.exportedWatchlist = toExport.length;
      }
      if (s.syncResume && c.serverType == ServerType.jellyfin) {
        final progress = await t.getPlaybackProgress();
        final byKey = <String, _LocalItem>{
          for (final l in playable) for (final k in l.item.keys) k: l,
        };
        for (final p in progress) {
          final l = p.item.keys.map((k) => byKey[k]).whereType<_LocalItem>().firstOrNull;
          if (l == null || l.played || l.runtimeTicks <= 0) continue;
          final remoteTicks = (l.runtimeTicks * p.percent / 100).round();
          // Only move the resume point forward.
          if (remoteTicks <= l.positionTicks + 600000000) continue;
          if (await _setResume(c, l.id, remoteTicks)) rep.resumePoints++;
        }
      }
    } catch (e) {
      rep.error = e.toString();
    }
    return rep;
  }

  Future<bool> _setResume(MediaServerClient c, String itemId, int ticks) async {
    final token = c.accessToken;
    if (token == null) return false;
    final dio = Dio(BaseOptions(
      baseUrl: c.baseUrl,
      headers: {'Authorization': 'MediaBrowser Token="$token"'},
      validateStatus: (_) => true,
    ));
    try {
      final body = {'PlaybackPositionTicks': ticks};
      var r = await dio.post('/UserItems/$itemId/UserData',
          queryParameters: {'userId': c.userId}, data: body);
      if ((r.statusCode ?? 500) >= 300) {
        r = await dio.post('/Users/${c.userId}/Items/$itemId/UserData', data: body);
      }
      return (r.statusCode ?? 500) < 300;
    } catch (_) {
      return false;
    } finally {
      dio.close();
    }
  }
}
