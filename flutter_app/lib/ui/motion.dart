// Animations légères et réutilisables. Toutes respectent le réglage système
// « Supprimer les animations » (MediaQuery.disableAnimations).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/money.dart';

bool _reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Apparition en fondu + léger glissement vers le haut, décalée selon [index]
/// (effet cascade sur les listes et grilles).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 18, this.duration = const Duration(milliseconds: 380)});
  final Widget child;
  final int index;
  final double offset;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: math.min(widget.index, 12) * 40);
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
    ),
  );
}

/// Montant FCFA qui défile vers sa nouvelle valeur.
class AnimatedAmount extends StatelessWidget {
  const AnimatedAmount(this.value, {super.key, this.style});
  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: _reduced(context) ? Duration.zero : const Duration(milliseconds: 450),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => Text(fcfa(v.round()), style: style),
  );
}

/// Secoue son enfant à chaque changement de [trigger] (ex. PIN erroné).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final Object? trigger;
  final Widget child;
  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger != null && !_reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => Transform.translate(offset: Offset(math.sin(_c.value * math.pi * 6) * 10 * (1 - _c.value), 0), child: child),
  );
}

/// Coche de réussite animée, affichée brièvement au centre de l'écran.
Future<void> showSuccessCheck(BuildContext context, String message, {String? detail}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: message,
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => _SuccessCheck(message: message, detail: detail),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class _SuccessCheck extends StatefulWidget {
  const _SuccessCheck({required this.message, this.detail});
  final String message;
  final String? detail;
  @override
  State<_SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<_SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: _CheckPainter(_c.value)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF2A2420)),
            ),
            if (widget.detail != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF7A716B)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;
  static const green = Color(0xFF2F9E44);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final circle = Curves.easeOut.transform((t / 0.55).clamp(0, 1));
    canvas.drawCircle(c, r * (0.6 + 0.4 * Curves.easeOutBack.transform(circle)), Paint()..color = green.withValues(alpha: 0.12 * circle));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 4),
      -math.pi / 2,
      2 * math.pi * circle,
      false,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    final tick = Curves.easeOutCubic.transform(((t - 0.45) / 0.55).clamp(0, 1));
    if (tick <= 0) return;
    final p1 = Offset(size.width * 0.28, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.67);
    final p3 = Offset(size.width * 0.73, size.height * 0.36);
    final path = Path()..moveTo(p1.dx, p1.dy);
    if (tick < 0.4) {
      final k = tick / 0.4;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * k, p1.dy + (p2.dy - p1.dy) * k);
    } else {
      final k = (tick - 0.4) / 0.6;
      path
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p2.dx + (p3.dx - p2.dx) * k, p2.dy + (p3.dy - p2.dy) * k);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

/// Pulsation douce en boucle (lecteur allumé, attente d'un scan).
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child});
  final Widget child;
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween<double>(begin: 0.92, end: 1.06).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}
