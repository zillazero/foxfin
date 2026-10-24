// Gemeinsames FOX-Designpaket (identisch zu FoxDesign.kt der Kotlin-Apps).
// Kontraste gemessen (WCAG): Text/Hintergrund >= 16,7:1, Muted/Panel >= 6,9:1,
// Akzent/Hintergrund >= 5,5:1, Schwarz auf Akzent >= 5,9:1. Weiss auf Akzent
// liegt bei Amber/Gruen unter 2,1:1 und ist deshalb nicht zulaessig.
import 'package:flutter/widgets.dart';

class FoxRadius {
  static const double s = 8, m = 12, l = 16;
  static const small = BorderRadius.all(Radius.circular(s));
  static const medium = BorderRadius.all(Radius.circular(m));
  static const large = BorderRadius.all(Radius.circular(l));
}

class FoxSpace {
  static const double xs = 4, s = 8, m = 16, l = 24;
}

class FoxType {
  static const double caption = 12, body = 14, bodyL = 16, title = 20, headline = 24, display = 32;
}

class FoxThemeColors {
  const FoxThemeColors(this.key, this.label, this.accent, this.accent2, this.bg, this.panel, this.text, this.muted);
  final String key, label;
  final Color accent, accent2, bg, panel, text, muted;
  Color get onAccent => const Color(0xFF000000);
  static const all = [
    FoxThemeColors('foxhole', 'Foxhole', Color(0xFFFF3B30), Color(0xFFFF8A80), Color(0xFF0A0A0B), Color(0xFF111214), Color(0xFFECECEE), Color(0xFF9A9DA4)),
    FoxThemeColors('magenta', 'Magenta', Color(0xFFFF2D6F), Color(0xFFFF7AA2), Color(0xFF0A0A0B), Color(0xFF111214), Color(0xFFECECEE), Color(0xFF9A9DA4)),
    FoxThemeColors('amber', 'Amber', Color(0xFFFFB000), Color(0xFFFFD36B), Color(0xFF0A0A0B), Color(0xFF111214), Color(0xFFECECEE), Color(0xFF9A9DA4)),
    FoxThemeColors('gruen', 'Grün', Color(0xFF19D26B), Color(0xFF7CF2AE), Color(0xFF0A0A0B), Color(0xFF111214), Color(0xFFECECEE), Color(0xFF9A9DA4)),
    FoxThemeColors('polizei', 'Polizei', Color(0xFF4D8BFF), Color(0xFF36D6FF), Color(0xFF050A17), Color(0xFF091226), Color(0xFFE6EEFF), Color(0xFF9FB2D6)),
  ];
}
