// Foxfin: common tracker model (GPL-2.0-or-later, see NOTICE).

/// External ids of a movie or show, as both Trakt and Simkl understand them.
class MediaIds {
  final String? tmdb;
  final String? imdb;
  final String? tvdb;
  const MediaIds({this.tmdb, this.imdb, this.tvdb});

  bool get isEmpty =>
      (tmdb ?? '').isEmpty && (imdb ?? '').isEmpty && (tvdb ?? '').isEmpty;

  /// Lookup keys, most specific first. Two ids match when any key matches.
  List<String> get keys => [
        if ((tmdb ?? '').isNotEmpty) 'tmdb:$tmdb',
        if ((imdb ?? '').isNotEmpty) 'imdb:$imdb',
        if ((tvdb ?? '').isNotEmpty) 'tvdb:$tvdb',
      ];

  Map<String, dynamic> toJson() => {
        if ((tmdb ?? '').isNotEmpty) 'tmdb': int.tryParse(tmdb!) ?? tmdb,
        if ((imdb ?? '').isNotEmpty) 'imdb': imdb,
        if ((tvdb ?? '').isNotEmpty) 'tvdb': int.tryParse(tvdb!) ?? tvdb,
      };

  static MediaIds fromJson(Map? ids) => MediaIds(
        tmdb: ids?['tmdb']?.toString(),
        imdb: ids?['imdb']?.toString(),
        tvdb: ids?['tvdb']?.toString(),
      );

  /// From a Jellyfin/Emby `ProviderIds` map.
  static MediaIds fromProviderIds(Map? p) {
    String? pick(String k) {
      if (p == null) return null;
      for (final e in p.entries) {
        if (e.key.toString().toLowerCase() == k) return e.value?.toString();
      }
      return null;
    }

    return MediaIds(tmdb: pick('tmdb'), imdb: pick('imdb'), tvdb: pick('tvdb'));
  }
}

/// A movie, or an episode addressed through its show + season/number.
class TrackedItem {
  final bool isEpisode;
  final MediaIds ids; // movie ids, or the show's ids for an episode
  final int? season;
  final int? episode;
  const TrackedItem.movie(this.ids)
      : isEpisode = false,
        season = null,
        episode = null;
  const TrackedItem.episode(this.ids, this.season, this.episode)
      : isEpisode = true;

  /// A whole show (watchlist entries).
  const TrackedItem.show(this.ids)
      : isEpisode = true,
        season = null,
        episode = null;

  bool get isShow => isEpisode && season == null;

  List<String> get keys => isShow
      ? [for (final k in ids.keys) 'show:$k']
      : isEpisode
          ? [for (final k in ids.keys) '$k:S${season}E$episode']
          : ids.keys;
}

class DeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final Duration interval;
  final DateTime expiresAt;
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresAt,
  });
}

class PlaybackProgress {
  final TrackedItem item;
  final double percent; // 0..100
  const PlaybackProgress(this.item, this.percent);
}

enum ScrobbleAction { start, pause, stop }

abstract class Tracker {
  String get id; // 'trakt' | 'simkl'
  String get displayName;

  Future<DeviceCode> startDeviceAuth();

  /// Returns the token JSON once the user approved, null while pending.
  /// Throws when the code expired or was denied.
  Future<Map<String, dynamic>?> pollDeviceAuth(DeviceCode code);

  /// Refreshes the token if needed; returns a new token JSON or null.
  Future<Map<String, dynamic>?> refreshIfNeeded(Map<String, dynamic> token);

  void useToken(Map<String, dynamic>? token);

  Future<void> scrobble(ScrobbleAction action, TrackedItem item, double percent);

  Future<List<TrackedItem>> getWatched();
  Future<void> addToHistory(List<TrackedItem> items);
  Future<List<TrackedItem>> getWatchlist();
  Future<void> addToWatchlist(List<TrackedItem> items);
  Future<List<PlaybackProgress>> getPlaybackProgress();
}

/// Groups items into the {movies:[...], shows:[{ids, seasons:[...]}]} body
/// both services use for history/watchlist writes.
Map<String, dynamic> groupedBody(List<TrackedItem> items,
    {Map<String, dynamic> Function(TrackedItem)? movieExtra}) {
  final movies = <Map<String, dynamic>>[];
  final shows = <String, Map<String, dynamic>>{};
  for (final it in items) {
    if (!it.isEpisode) {
      movies.add({'ids': it.ids.toJson(), ...?movieExtra?.call(it)});
      continue;
    }
    final key = it.ids.keys.first;
    final show = shows.putIfAbsent(
        key, () => {'ids': it.ids.toJson(), 'seasons': <Map<String, dynamic>>[]});
    final seasons = show['seasons'] as List<Map<String, dynamic>>;
    if (it.season == null) continue; // whole show (watchlist)
    var s = seasons.where((x) => x['number'] == it.season).firstOrNull;
    if (s == null) {
      s = {'number': it.season, 'episodes': <Map<String, dynamic>>[]};
      seasons.add(s);
    }
    (s['episodes'] as List).add({'number': it.episode});
  }
  for (final s in shows.values) {
    if ((s['seasons'] as List).isEmpty) s.remove('seasons');
  }
  return {
    if (movies.isNotEmpty) 'movies': movies,
    if (shows.isNotEmpty) 'shows': shows.values.toList(),
  };
}
