import 'package:flutter/material.dart';

import '../data/models.dart';
import 'common.dart';
import 'motion.dart';
import 'theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<AppUser> users = [];
  AppUser? selected;
  String pin = '';
  String shopName = '';
  bool busy = false;
  String? error;
  int failures = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (users.isEmpty) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final u = await repo.users();
    final s = await repo.shopInfo();
    if (!mounted) return;
    setState(() {
      users = u;
      shopName = s.name;
      if (u.length == 1) selected = u.first;
    });
  }

  Future<void> _submit() async {
    if (selected == null || pin.length < 4 || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final scope = AppScope.read(context);
    try {
      final user = await scope.repo.login(selected!.id, pin);
      scope.session.signIn(user);
    } catch (e) {
      setState(() {
        error = '$e';
        pin = '';
        failures++;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _key(String k) {
    setState(() {
      error = null;
      if (k == '<') {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
      } else if (pin.length < 6) {
        pin += k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Terminaux de caisse 5" : tout doit tenir sans défiler.
    final compact = MediaQuery.sizeOf(context).height < 760;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Pharmacie : fond sobre sans photo de nourriture.
          if (!Brand.pharmacy) Image.asset('assets/products/poulet_braise.jpg', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: Brand.pharmacy
                  ? LinearGradient(colors: [AppColors.night, Color.lerp(AppColors.night, AppColors.orange, 0.35)!], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                  : LinearGradient(colors: [AppColors.night.withValues(alpha: 0.9), AppColors.night.withValues(alpha: 0.7)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 8 : 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: FadeSlideIn(
                    offset: 30,
                    duration: const Duration(milliseconds: 600),
                    child: Card(
                      color: Colors.white,
                      elevation: 12,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 22, vertical: compact ? 12 : 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BrandMark(size: compact ? 52 : 84, shopName: shopName),
                            SizedBox(height: compact ? 8 : 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final u in users)
                                  ChoiceChip(
                                    visualDensity: compact ? VisualDensity.compact : null,
                                    materialTapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
                                    avatar: CircleAvatar(child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase())),
                                    label: Text('${u.name} · ${u.role.label}'),
                                    selected: selected?.id == u.id,
                                    onSelected: (_) => setState(() {
                                      selected = u;
                                      pin = '';
                                      error = null;
                                    }),
                                  ),
                              ],
                            ),
                            SizedBox(height: compact ? 12 : 20),
                            Shake(
                              trigger: failures,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < 6; i++)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      curve: Curves.easeOutBack,
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      width: i < pin.length ? 16 : 14,
                                      height: i < pin.length ? 16 : 14,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: i < pin.length ? cs.primary : Colors.transparent,
                                        border: Border.all(color: error != null ? cs.error : (i < 4 || i < pin.length ? cs.primary : cs.outlineVariant), width: 2),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: compact ? 28 : 40,
                              child: Center(
                                child: error == null
                                    ? null
                                    : Text(
                                        error!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: cs.error),
                                      ),
                              ),
                            ),
                            _PinPad(onKey: _key, onSubmit: _submit, enabled: selected != null && !busy, canSubmit: pin.length >= 4, compact: compact),
                            if (users.length == 1 && users.first.mustChangePin) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Premier démarrage : PIN 0000, à changer immédiatement.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.outline),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onKey, required this.onSubmit, required this.enabled, required this.canSubmit, this.compact = false});
  final bool compact;
  final void Function(String) onKey;
  final VoidCallback onSubmit;
  final bool enabled;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    Widget key(String k, {Widget? child, VoidCallback? onTap}) => Padding(
      padding: EdgeInsets.all(compact ? 4 : 5),
      child: SizedBox(
        width: 76,
        height: compact ? 50 : 60,
        child: FilledButton.tonal(
          onPressed: enabled ? (onTap ?? () => onKey(k)) : null,
          child: child ?? Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        ),
      ),
    );
    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final k in row) key(k)]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key('<', child: const Icon(Icons.backspace_outlined)),
            key('0'),
            Padding(
              padding: EdgeInsets.all(compact ? 4 : 5),
              child: SizedBox(
                width: 76,
                height: compact ? 50 : 60,
                child: FilledButton(onPressed: enabled && canSubmit ? onSubmit : null, child: const Icon(Icons.login)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Écran imposé quand le PIN doit être changé (premier démarrage, réinitialisation).
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, this.forced = true});
  final bool forced;
  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;

  Future<void> _save() async {
    if (a.text != b.text) {
      setState(() => error = 'Les deux PIN ne correspondent pas');
      return;
    }
    final scope = AppScope.read(context);
    try {
      await scope.repo.setPin(scope.user, scope.user.id, a.text);
      final fresh = await scope.repo.reloadUser(scope.user.id);
      scope.session.signIn(fresh);
      if (!widget.forced && mounted) {
        Navigator.pop(context);
        toast(context, 'PIN modifié');
      }
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: gradientAppBar(
        context,
        title: const Text('Choisir un nouveau PIN'),
        actions: [if (widget.forced) TextButton(onPressed: scope.session.signOut, child: const Text('Déconnexion'))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text('${scope.user.name}, choisissez un PIN personnel de 4 à 6 chiffres. Ne le communiquez à personne : toutes vos actions sont enregistrées à votre nom.'),
              const SizedBox(height: 16),
              TextField(
                controller: a,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Nouveau PIN', border: OutlineInputBorder()),
              ),
              TextField(
                controller: b,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Confirmer le PIN', border: OutlineInputBorder()),
                onSubmitted: (_) => _save(),
              ),
              if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _save, child: const Text('Enregistrer')),
            ],
          ),
        ),
      ),
    );
  }
}
