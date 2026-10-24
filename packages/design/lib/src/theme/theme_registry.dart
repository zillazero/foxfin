import 'oled_derivation.dart';
import 'oled_tuning.dart';
import 'theme_spec.dart';
import 'themes/moonfin_theme_spec.dart';
import 'themes/neon_pulse_theme_spec.dart';
import 'themes/glass_theme_spec.dart';
import 'themes/eightbit_hero_theme_spec.dart';
import 'themes/fox_theme_specs.dart';

class ThemeRegistry {
  const ThemeRegistry._();

  static const String moonfinId = 'moonfin';
  static const String neonPulseId = 'neon_pulse';
  static const String glassId = 'glass';
  static const String eightbitHeroId = '8bit_hero';

  /// IDs that are bundled with the app and cannot be removed.
  static const Set<String> builtInIds = {
    moonfinId,
    neonPulseId,
    glassId,
    eightbitHeroId,
  };

  // Foxfin: the upstream Moonfin/Neon/Glass/8-bit looks are replaced by the
  // five FOX Designsystem themes. Foxhole (default) keeps the internal id
  // 'moonfin' so stored preferences and the default VisualThemeId resolve to it.
  static const String foxholeId = moonfinId;
  static const List<String> foxThemeOrder = [
    moonfinId, 'magenta', 'amber', 'gruen', 'polizei',
  ];
  static const Map<String, String> foxThemeKeys = {
    moonfinId: 'foxhole', 'magenta': 'magenta', 'amber': 'amber',
    'gruen': 'gruen', 'polizei': 'polizei',
  };

  static const Map<String, ThemeSpec> _builtIns = {
    moonfinId: foxFoxholeThemeSpec,
  };

  static const Map<String, ThemeSpec> _fox = {
    'magenta': foxMagentaThemeSpec,
    'amber': foxAmberThemeSpec,
    'gruen': foxGruenThemeSpec,
    'polizei': foxPolizeiThemeSpec,
  };

  // Upstream specs kept referenced for GPL diff clarity; not selectable.
  // ignore: unused_field
  static const List<ThemeSpec> _upstreamUnused = [
    moonfinThemeSpec, neonPulseThemeSpec, glassThemeSpec, eightbitHeroThemeSpec,
  ];

  static final Map<String, ThemeSpec> _custom = {};

  /// Themes the user saved from the Theme Store. Kept separate from [_custom]
  /// so server theme syncs (which call [replaceCustomThemes]) never clear them.
  static final Map<String, ThemeSpec> _store = {};

  /// All themes (built-in + plugin-supplied + store-saved) keyed by id.
  /// Plugin/server themes take precedence over store themes on id clash.
  static Map<String, ThemeSpec> get availableThemes => {
        ..._builtIns,
        ..._fox,
        ..._store,
        ..._custom,
      };

  /// The theme the user picked, before OLED Mode is layered on.
  static ThemeSpec _base = foxFoxholeThemeSpec;
  static OledTuning _oled = OledTuning.off;

  /// [_base] with [_oled] applied. Memoized rather than derived per read:
  /// `AppColorScheme` proxies this getter on every colour lookup, so deriving
  /// lazily would allocate `Color`s in the paint path.
  static ThemeSpec _active = foxFoxholeThemeSpec;

  static ThemeSpec get active => _active;

  static void setActiveById(String id) {
    _base = availableThemes[id] ?? foxFoxholeThemeSpec;
    _recompute();
  }

  static void setOledTuning(OledTuning tuning) {
    if (identical(tuning, _oled)) return;
    _oled = tuning;
    _recompute();
  }

  /// Foxfin 2.9.1: eigener Karten-Eckenradius (null = Theme-Standard).
  static double? foxCardRadius;
  static void setFoxCardRadius(double? r) {
    foxCardRadius = r;
    _recompute();
  }

  static void _recompute() =>
      _active = applyOled(_base, _oled).withFoxRadius(foxCardRadius);

  static ThemeSpec resolveById(String id) {
    return availableThemes[id] ?? foxFoxholeThemeSpec;
  }

  /// Register or replace a plugin-supplied theme. Built-in IDs are reserved
  /// and will be rejected to prevent shadowing.
  static void registerCustom(ThemeSpec spec) {
    if (builtInIds.contains(spec.id)) {
      throw ArgumentError(
        'Cannot register custom theme with reserved id "${spec.id}".',
      );
    }
    _custom[spec.id] = spec;
  }

  /// Replace the entire set of custom themes (e.g. after fetching from the
  /// admin plugin). Built-ins are untouched.
  static void replaceCustomThemes(Iterable<ThemeSpec> specs) {
    _custom
      ..clear()
      ..addEntries(specs
          .where((s) => !builtInIds.contains(s.id) && !_fox.containsKey(s.id))
          .map((s) => MapEntry(s.id, s)));
  }

  static void removeCustom(String id) {
    _custom.remove(id);
  }

  static List<ThemeSpec> get customThemes => List.unmodifiable(_custom.values);

  /// Register a theme saved from the Theme Store. Built-in IDs are rejected.
  static void registerStoreTheme(ThemeSpec spec) {
    if (builtInIds.contains(spec.id)) {
      throw ArgumentError(
        'Cannot register store theme with reserved id "${spec.id}".',
      );
    }
    _store[spec.id] = spec;
  }

  static void removeStoreTheme(String id) {
    _store.remove(id);
  }

  static List<ThemeSpec> get storeThemes => List.unmodifiable(_store.values);
}
