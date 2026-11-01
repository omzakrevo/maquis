import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money.dart';
import '../data/models.dart';
import '../data/pos_repository.dart';
import '../printing/print_service.dart';

/// Session de l'utilisateur connecté.
class SessionController extends ChangeNotifier {
  AppUser? _user;
  AppUser? get user => _user;
  void signIn(AppUser u) {
    _user = u;
    notifyListeners();
  }

  void signOut() {
    _user = null;
    notifyListeners();
  }
}

/// Accès aux services depuis n'importe quel écran : `AppScope.of(context)`.
class AppScope extends InheritedNotifier<SessionController> {
  const AppScope({super.key, required this.repo, required this.printer, required SessionController session, required super.child}) : super(notifier: session);
  final PosRepository repo;
  final PrintService printer;

  SessionController get session => notifier!;
  AppUser get user => notifier!.user!;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;
  static AppScope read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;
}

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Theme.of(context).colorScheme.error : null, behavior: SnackBarBehavior.floating));
}

/// Exécute une action et affiche l'erreur métier proprement.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (success != null && context.mounted) toast(context, success);
    return r;
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
    return null;
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirmer', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptText(BuildContext context, String title, {String label = '', String initial = '', String ok = 'Valider', int minLength = 1}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ok)),
      ],
    ),
  );
  if (r == null || r.trim().length < minLength) return null;
  return r.trim();
}

Future<int?> promptAmount(BuildContext context, String title, {String label = 'Montant (FCFA)', int? initial, bool allowZero = false}) async {
  final ctrl = TextEditingController(text: initial?.toString() ?? '');
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, suffixText: 'F'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Valider')),
      ],
    ),
  );
  if (r == null) return null;
  final v = parseFcfa(r);
  if (v == null || (!allowZero && v == 0)) return null;
  return v;
}

String timeOf(DateTime d) => '${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';
String dateTimeOf(DateTime d) => '${'${d.day}'.padLeft(2, '0')}/${'${d.month}'.padLeft(2, '0')} ${timeOf(d)}';

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.message, {super.key});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF2A2420)),
    );
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: trailing != null && narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                ?trailing,
              ],
            ),
    );
  }
}

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// Terminal de caisse 5" ou téléphone en portrait.
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 520;
