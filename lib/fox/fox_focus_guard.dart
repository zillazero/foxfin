// Foxfin 2.8.3: D-Pad-Fokus-Wächter. GPL-3.0, see NOTICE.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hält den D-Pad-Fokus am Leben: geht der Fokus verloren (Widget entfernt,
/// Liste neu geladen, Dialog geschlossen), wird der zuletzt fokussierte
/// Knoten wiederhergestellt oder – falls weg – das erste fokussierbare
/// Element im aktuellen Bereich. Drückt man eine Pfeiltaste, während nichts
/// fokussiert ist, wird ebenfalls neu fokussiert statt die Taste zu verlieren.
class FoxFocusGuard {
  FoxFocusGuard._();
  static FocusNode? _last;
  static bool _scheduled = false;
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    FocusManager.instance.addListener(_onChange);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static bool _lost(FocusNode? f) =>
      f == null || (f is FocusScopeNode && f.focusedChild == null);

  static void _onChange() {
    final f = FocusManager.instance.primaryFocus;
    if (!_lost(f)) {
      _last = f;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    // Zwei Frames warten: Routen/Listen setzen ihren Fokus oft selbst.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (_lost(FocusManager.instance.primaryFocus)) _restore();
      });
    });
  }

  static bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final arrows = {
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    };
    if (!arrows.contains(e.logicalKey)) return false;
    if (!_lost(FocusManager.instance.primaryFocus)) return false;
    return _restore();
  }

  static bool _restore() {
    try {
      final last = _last;
      if (last != null &&
          last.context != null &&
          last.canRequestFocus &&
          !last.skipTraversal) {
        final route = ModalRoute.of(last.context!);
        if (route == null || route.isCurrent) {
          last.requestFocus();
          return true;
        }
      }
      final f = FocusManager.instance.primaryFocus;
      final scope = f is FocusScopeNode ? f : f?.nearestScope;
      if (scope == null) return false;
      for (final n in scope.traversalDescendants) {
        if (n.canRequestFocus && n is! FocusScopeNode && n.context != null) {
          n.requestFocus();
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}
