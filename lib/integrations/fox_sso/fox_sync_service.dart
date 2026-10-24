// Foxfin: sign-in through the FOX Store (SSO) and sync of theme, favourites,
// progress and Trakt/Simkl link status with the shop account.
// Only content of the shop Jellyfin (server_id 37f9a5dd4a4e49fba3dc493068b2397d)
// is ever uploaded; private servers are never synced.
// GPL-2.0-or-later, see NOTICE.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../preference/user_preferences.dart';
import '../../ui/theme/app_theme_controller.dart';

import 'package:moonfin/fox/fox_errors.dart';
class FoxSyncService extends ChangeNotifier {
  FoxSyncService._();
  static final FoxSyncService instance = FoxSyncService._();

  static const shopServerId = '37f9a5dd4a4e49fba3dc493068b2397d';
  static const _ch = MethodChannel('fox_sso');

  bool get supported => defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  bool storeAvailable = false;
  bool storeLoggedIn = false;
  bool loggedIn = false;
  bool busy = false;
  String? lastMessage;

  AppThemeController? _theme;
  UserPreferences? _prefs;
  String? _lastThemeKey;
  String? _settingsUpdatedAt;
  Timer? _themeDebounce;
  bool _applyingRemote = false;

  // ------------------------------------------------------------- status/auth

  Future<void> refreshStatus() async {
    if (!supported) return;
    try {
      final m = Map<String, dynamic>.from(await _ch.invokeMethod('status') as Map);
      storeAvailable = m['storeAvailable'] == true;
      storeLoggedIn = m['storeLoggedIn'] == true;
      loggedIn = m['loggedIn'] == true;
    } catch (e) {
      debugPrint('[Foxfin] fox_sso status: $e');
    }
    notifyListeners();
  }

  /// Returns a user-facing German message.
  Future<String> signInViaStore() async {
    if (!supported) return 'Nur auf Android verfügbar.';
    busy = true;
    notifyListeners();
    String msg;
    try {
      final r = (await _ch.invokeMethod('signInViaStore')).toString();
      if (r == 'ok') {
        msg = 'Mit dem FOX-Konto angemeldet.';
        await refreshStatus();
        unawaited(syncAll());
      } else if (r == 'store_not_logged_in') {
        msg = 'Bitte zuerst im FOX Store anmelden.';
      } else if (r == 'store_unavailable') {
        msg = 'FOX Store nicht gefunden (installiert und gleich signiert?).';
      } else {
        msg = 'Anmeldung fehlgeschlagen: $r';
      }
    } catch (e) {
      msg = 'Anmeldung fehlgeschlagen: $e';
    }
    busy = false;
    lastMessage = msg;
    notifyListeners();
    return msg;
  }

  /// Fallback without the FOX Store: shop username/password (never stored).
  Future<String> signInPassword(String user, String password) async {
    if (!supported) return 'Nur auf Android verfügbar.';
    busy = true;
    notifyListeners();
    String msg;
    try {
      await _ch.invokeMethod('signInPassword', {'username': user, 'password': password});
      msg = 'Mit dem FOX-Konto angemeldet.';
      await refreshStatus();
      unawaited(syncAll());
    } on PlatformException catch (e) {
      msg = 'Anmeldung fehlgeschlagen: ${e.message ?? e.code}';
    } catch (e) {
      msg = 'Anmeldung fehlgeschlagen: $e';
    }
    busy = false;
    lastMessage = msg;
    notifyListeners();
    return msg;
  }

  Future<void> signOut({bool all = false}) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('signOut', {'all': all});
    } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
    await refreshStatus();
  }

  Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!supported || !loggedIn) return null;
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      if (e.code == 'session_expired') {
        loggedIn = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------------ theme

  void attachTheme(AppThemeController controller, UserPreferences prefs) {
    _theme = controller;
    _prefs = prefs;
    _lastThemeKey = _currentThemeKey();
    controller.addListener(_onLocalThemeChanged);
    unawaited(() async {
      await refreshStatus();
      if (loggedIn) await pullSettings();
    }());
  }

  String? _currentThemeKey() {
    final id = _theme?.activeSpec.id;
    return id == null ? null : ThemeRegistry.foxThemeKeys[id];
  }

  void _onLocalThemeChanged() {
    if (_applyingRemote) return;
    final key = _currentThemeKey();
    if (key == null || key == _lastThemeKey) return;
    _lastThemeKey = key;
    _themeDebounce?.cancel();
    _themeDebounce = Timer(const Duration(seconds: 2), () => unawaited(_pushTheme(key)));
  }

  Future<void> _pushTheme(String key) async {
    try {
      final raw = await _call<String>('putSettings', {
        'theme': key,
        if (_settingsUpdatedAt != null) 'baseUpdatedAt': _settingsUpdatedAt,
      });
      if (raw != null) _settingsUpdatedAt = jsonDecode(raw)['updated_at'];
    } on PlatformException catch (e) {
      if (e.code == 'conflict') {
        // Local choice is the newest user intent: retry last-write-wins.
        _settingsUpdatedAt = null;
        try {
          await _call<String>('putSettings', {'theme': key});
        } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
      }
    } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
  }

  Future<void> pullSettings() async {
    try {
      final raw = await _call<String>('getSettings');
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _settingsUpdatedAt = m['updated_at'] as String?;
      var key = (m['theme'] as String?)?.toLowerCase();
      if (key == 'green') key = 'gruen';
      if (key == null || key == _currentThemeKey()) return;
      final id = ThemeRegistry.foxThemeKeys.entries
          .where((e) => e.value == key)
          .map((e) => e.key)
          .firstOrNull;
      if (id == null || _theme == null || _prefs == null) return;
      _applyingRemote = true;
      try {
        await _theme!.applyThemeById(_prefs!, id);
        _lastThemeKey = key;
      } finally {
        _applyingRemote = false;
      }
    } catch (e) {
      debugPrint('[Foxfin] settings pull: $e');
    }
  }

  // ------------------------------------------------------- shop server gate

  final Map<String, bool> _isShop = {};

  MediaServerClient? get _client => GetIt.instance.isRegistered<MediaServerClient>()
      ? GetIt.instance<MediaServerClient>()
      : null;

  /// True only when the active server reports the shop server id.
  Future<bool> isShopServer() async {
    final c = _client;
    if (c == null || c.serverType != ServerType.jellyfin) return false;
    final cached = _isShop[c.baseUrl];
    if (cached != null) return cached;
    try {
      final info = await c.systemApi.getPublicSystemInfo();
      final id = info['Id']?.toString().replaceAll('-', '').toLowerCase();
      return _isShop[c.baseUrl] = id == shopServerId;
    } catch (_) {
      return false;
    }
  }

  static String _norm(String id) => id.replaceAll('-', '').toLowerCase();
  static bool _validId(String id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id);

  // ------------------------------------------------------------- favourites

  Future<String> _favKey() async => 'foxfin.fox.favs.${_client?.userId ?? ''}';

  Future<String> syncFavorites() async {
    if (!await isShopServer()) return 'Favoriten: nur für watch.pk187.site';
    final c = _client!;
    final remoteRaw = await _call<String>('getFavorites');
    if (remoteRaw == null) return 'Favoriten: nicht angemeldet';
    final remote = {
      for (final i in (jsonDecode(remoteRaw)['items'] as List? ?? const []))
        _norm(i['item_id'].toString()),
    };
    final local = <String>{};
    var start = 0;
    while (true) {
      final r = await c.itemsApi.getItems(
        isFavorite: true,
        recursive: true,
        includeItemTypes: const ['Movie', 'Series', 'Episode', 'BoxSet'],
        enableImageTypes: '',
        imageTypeLimit: 0,
        startIndex: start,
        limit: 500,
        enableTotalRecordCount: false,
      );
      final items = r['Items'] as List? ?? const [];
      for (final i in items) {
        local.add(_norm(i['Id'].toString()));
      }
      if (items.length < 500) break;
      start += 500;
    }
    final sp = await SharedPreferences.getInstance();
    final last = (sp.getStringList(await _favKey()) ?? const []).toSet();

    // New locally since last sync -> upload.
    final addRemote = local.difference(remote).difference(last).where(_validId).toList();
    // Removed locally since last sync -> remove remotely.
    final removeRemote = last.intersection(remote).difference(local).toList();
    // Removed remotely since last sync -> unfavourite locally.
    final removeLocal = last.intersection(local).difference(remote);
    // New remotely -> favourite locally.
    final addLocal = remote.difference(local).difference(last);

    // A local favourite that was removed remotely must not be re-uploaded.
    addRemote.removeWhere(removeLocal.contains);

    for (final id in addLocal) {
      try {
        await c.userLibraryApi.markFavorite(id);
      } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
    }
    for (final id in removeLocal) {
      try {
        await c.userLibraryApi.unmarkFavorite(id);
      } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
    }
    if (addRemote.isNotEmpty) {
      await _call<String>('addFavorites', {'ids': addRemote.take(2000).toList()});
    }
    if (removeRemote.isNotEmpty) {
      await _call<String>('removeFavorites', {'ids': removeRemote});
    }
    final now = local.union(addLocal).difference(removeLocal);
    await sp.setStringList(await _favKey(), now.toList());
    return 'Favoriten: +${addLocal.length}/−${removeLocal.length} lokal, '
        '+${addRemote.length}/−${removeRemote.length} Konto';
  }

  // --------------------------------------------------------------- progress

  final Map<String, int> _runtime = {};

  /// Called from the playback decorator on pause/stop. Never throws.
  Future<void> reportProgress(String itemId, Duration position,
      {bool stopped = false}) async {
    try {
      if (!loggedIn || !await isShopServer()) return;
      final id = _norm(itemId);
      if (!_validId(id)) return;
      final c = _client!;
      var runtime = _runtime[id];
      bool played = false;
      if (runtime == null || stopped) {
        final j = await c.itemsApi.getItem(itemId, fields: '');
        runtime = (j['RunTimeTicks'] as num?)?.toInt() ?? 0;
        _runtime[id] = runtime;
        played = (j['UserData'] as Map?)?['Played'] == true;
      }
      final pos = position.inMicroseconds * 10;
      if (runtime > 0 && pos >= runtime * 0.9) played = true;
      final now = DateTime.now().toUtc();
      final iso = '${now.toIso8601String().split('.').first}Z';
      await _call<String>('putProgress', {
        'items': jsonEncode([
          {
            'item_id': id,
            'server_id': shopServerId,
            'position_ticks': played ? 0 : pos,
            'runtime_ticks': runtime,
            'played': played,
            'updated_at': iso,
          }
        ]),
      });
    } catch (e) {
      debugPrint('[Foxfin] progress push: $e');
    }
  }

  Future<String> pullProgress() async {
    if (!await isShopServer()) return 'Fortschritt: nur für watch.pk187.site';
    final sp = await SharedPreferences.getInstance();
    final k = 'foxfin.fox.progressSince.${_client?.userId ?? ''}';
    final raw = await _call<String>('getProgress', {'since': sp.getString(k)});
    if (raw == null) return 'Fortschritt: nicht angemeldet';
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final c = _client!;
    var applied = 0;
    for (final it in (m['items'] as List? ?? const [])) {
      final id = it['item_id'].toString();
      try {
        final j = await c.itemsApi.getItem(id, fields: '');
        final ud = j['UserData'] as Map? ?? const {};
        if (it['played'] == true) {
          if (ud['Played'] != true) {
            await c.userLibraryApi.markPlayed(id);
            applied++;
          }
          continue;
        }
        final remote = (it['position_ticks'] as num?)?.toInt() ?? 0;
        final localPos = (ud['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
        if (remote > localPos + 600000000 && await _setResume(c, id, remote)) {
          applied++;
        }
      } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
    }
    if (m['server_time'] != null) await sp.setString(k, m['server_time']);
    return 'Fortschritt: $applied übernommen';
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
      final r = await dio.post('/UserItems/$itemId/UserData',
          queryParameters: {'userId': c.userId},
          data: {'PlaybackPositionTicks': ticks});
      return (r.statusCode ?? 500) < 300;
    } catch (_) {
      return false;
    } finally {
      dio.close();
    }
  }

  // ------------------------------------------------------------------ links

  /// Only the connection status is shared, never OAuth tokens.
  Future<void> pushLink(String service, bool connected) async {
    if (service != 'trakt' && service != 'simkl') return;
    try {
      await _call<String>('putLink', {'service': service, 'connected': connected});
    } catch (e) {
      debugPrint('[Foxfin] link push: $e');
    }
  }

  // -------------------------------------------------------------------- all

  Future<String> syncAll() async {
    if (!supported) return 'Nur auf Android verfügbar.';
    await refreshStatus();
    if (!loggedIn) return 'Nicht mit dem FOX-Konto angemeldet.';
    busy = true;
    notifyListeners();
    final parts = <String>[];
    try {
      await pullSettings();
      parts.add('Design übernommen');
      parts.add(await syncFavorites());
      parts.add(await pullProgress());
    } catch (e) {
      parts.add('Fehler: $e');
    } finally {
      busy = false;
      lastMessage = parts.join(' · ');
      notifyListeners();
    }
    return lastMessage!;
  }
}
