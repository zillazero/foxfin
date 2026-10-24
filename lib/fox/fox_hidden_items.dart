// Foxfin 2.9.0: Titel lokal ausblenden (nur auf diesem Gerät), mit Rückgängig-Liste.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FoxHidden {
  static const _key = 'fox_hidden_items_v1';
  static final Map<String, String> _items = {}; // id -> Name
  static final changes = ValueNotifier<int>(0);

  static bool get isEmpty => _items.isEmpty;
  static Map<String, String> get items => Map.unmodifiable(_items);

  static bool isHidden(String? id) => id != null && _items.containsKey(id);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _items.clear();
    for (final e in p.getStringList(_key) ?? const <String>[]) {
      final i = e.indexOf('|');
      if (i > 0) _items[e.substring(0, i)] = e.substring(i + 1);
    }
    changes.value++;
  }

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _key, [for (final e in _items.entries) '${e.key}|${e.value}']);
    changes.value++;
  }

  static Future<void> hide(String id, String name) async {
    _items[id] = name;
    await _save();
  }

  static Future<void> unhide(String id) async {
    _items.remove(id);
    await _save();
  }

  static Future<void> clear() async {
    _items.clear();
    await _save();
  }
}
