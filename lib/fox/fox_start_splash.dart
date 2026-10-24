// Foxfin 2.8.5: kurzer animierter Start (<1s): Fuchs glüht/pulsiert in der
// Theme-Akzentfarbe und blendet aus. Bei reduzierten/aus Animationen nur
// kurzes Ausblenden bzw. gar nichts.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../preference/fox_ui_prefs.dart';

class FoxStartSplash extends StatefulWidget {
  const FoxStartSplash({super.key});
  static bool _shown = false;
  @override
  State<FoxStartSplash> createState() => _FoxStartSplashState();
}

class _FoxStartSplashState extends State<FoxStartSplash>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _done = FoxStartSplash._shown;

  @override
  void initState() {
    super.initState();
    if (_done) return;
    FoxStartSplash._shown = true;
    final anim = FoxUi.animations;
    if (anim == FoxAnimationLevel.aus) {
      _done = true;
      return;
    }
    final reduced = anim == FoxAnimationLevel.reduziert || FoxUi.lowMemoryDevice;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: reduced ? 350 : 850),
    )..forward().whenComplete(() {
        if (mounted) setState(() => _done = true);
      });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_done || c == null) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    final reduced = c.duration!.inMilliseconds < 500;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final t = c.value;
          final fade = t < 0.7 ? 1.0 : 1.0 - (t - 0.7) / 0.3;
          // 2.10.0: gleiche Choreografie wie die AnimatedVectorDrawable der
          // Kotlin-Apps: Einzoomen 0,86 -> 1 (0-50 %), danach Puls 1 -> 1,05 -> 1.
          final zoom = reduced ? 1.0 : 0.86 + 0.14 * Curves.fastOutSlowIn.transform((t / 0.5).clamp(0.0, 1.0));
          final pulse = reduced || t < 0.5 ? 0.0 : Curves.easeInOut.transform(t < 0.75 ? (t - 0.5) * 4 : (1 - t) * 4);
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: ColoredBox(
              color: const Color(0xFF0A0A0B),
              child: Center(
                child: Container(
                  width: 144,
                  height: 144,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: reduced
                        ? null
                        : [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.25 + 0.4 * pulse),
                              blurRadius: 24 + 36 * pulse,
                              spreadRadius: 2 + 10 * pulse,
                            ),
                          ],
                  ),
                  child: Transform.scale(
                    scale: zoom * (1.0 + 0.05 * pulse),
                    child: SvgPicture.asset('assets/images/foxfin_logo_a.svg', semanticsLabel: 'Foxfin',
                        width: 144, height: 144,
                        semanticsLabel: 'Foxfin'),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
