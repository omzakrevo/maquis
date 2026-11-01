import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/permissions.dart';
import '../data/models.dart';
import '../printing/ticket_builder.dart';
import 'common.dart';
import 'scan_screen.dart';
import 'ticket_preview.dart';

/// Avoirs clients : vérification d'un code, émission manuelle, liste.
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});
  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  List<Credit> credits = [];
  bool activeOnly = true;
  bool loading = true;
  final code = TextEditingController();
  Credit? checked;
  String? checkError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final c = await AppScope.read(context).repo.credits(activeOnly: activeOnly);
    if (!mounted) return;
    setState(() {
      credits = c;
      loading = false;
    });
  }

  Future<void> _check() async {
    final c = await AppScope.read(context).repo.creditByCode(code.text);
    setState(() {
      checked = c;
      checkError = c == null ? 'Code inconnu' : null;
    });
  }

  Future<void> _issue() async {
    final scope = AppScope.read(context);
    final amount = TextEditingController();
    final name = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Émettre un avoir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Montant', suffixText: 'F'),
            ),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nom du client (facultatif)'),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Motif (plat indisponible, geste commercial…)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Émettre')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final issued = await guard(context, () => scope.repo.issueCredit(scope.user, amount: parseFcfa(amount.text) ?? 0, customerName: name.text, reason: reason.text));
    if (issued == null || !mounted) return;
    await _load();
    final shop = await scope.repo.shopInfo();
    if (!mounted) return;
    toast(context, 'Avoir ${issued.code} émis : ${fcfa(issued.credit.initial)}');
    await showTicket(context, creditVoucher(shop, issued));
  }

  Future<void> _cancel(Credit c) async {
    final scope = AppScope.read(context);
    final reason = await promptText(context, 'Annuler l\'avoir …${c.codeHint}', label: 'Motif', ok: 'Annuler l\'avoir', minLength: 3);
    if (reason == null || !mounted) return;
    await guard(context, () => scope.repo.cancelCredit(scope.user, c.id, reason), success: 'Avoir annulé');
    await _load();
  }

  String _status(String s) => switch (s) {
    'active' => 'Actif',
    'exhausted' => 'Épuisé',
    _ => 'Annulé',
  };

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user;
    final cs = Theme.of(context).colorScheme;
    if (loading) return const Center(child: CircularProgressIndicator());
    final outstanding = credits.where((c) => c.status == 'active').fold<int>(0, (a, c) => a + c.balance);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Vérifier un avoir', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(hintText: 'ABCD-EFGH', border: OutlineInputBorder(), isDense: true),
                        onSubmitted: (_) => _check(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _check, child: const Text('Vérifier')),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Scanner le QR',
                      onPressed: () async {
                        final v = await scanCode(context, title: 'Scanner le bon d\'avoir');
                        if (v == null) return;
                        code.text = v.toUpperCase().startsWith('AVOIR:') ? v.substring(6) : v;
                        await _check();
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ],
                ),
                if (checkError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(checkError!, style: TextStyle(color: cs.error)),
                  ),
                if (checked != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Solde : ${fcfa(checked!.balance)} / ${fcfa(checked!.initial)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${_status(checked!.status)} · émis le ${dateTimeOf(checked!.createdAt)}${checked!.customerName != null ? ' · ${checked!.customerName}' : ''}'),
                  ),
                const SizedBox(height: 4),
                Text('Pour utiliser un avoir : En cours > Encaisser > Avoir.', style: TextStyle(color: cs.outline, fontSize: 12)),
              ],
            ),
          ),
        ),
        SectionTitle(
          'Avoirs ${activeOnly ? 'actifs' : ''} · en circulation ${fcfa(outstanding)}',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Actifs seulement'),
                selected: activeOnly,
                onSelected: (v) {
                  activeOnly = v;
                  _load();
                },
              ),
              if (user.can(Permission.issueCredits)) ...[FilledButton.icon(onPressed: _issue, icon: const Icon(Icons.add), label: const Text('Émettre'))],
            ],
          ),
        ),
        if (credits.isEmpty) const EmptyState(Icons.confirmation_number_outlined, 'Aucun avoir.'),
        for (final c in credits)
          Card(
            child: ListTile(
              leading: const Icon(Icons.confirmation_number_outlined),
              title: Text('…${c.codeHint} · ${fcfa(c.balance)} / ${fcfa(c.initial)}'),
              subtitle: Text('${_status(c.status)} · ${dateTimeOf(c.createdAt)}${c.customerName != null ? ' · ${c.customerName}' : ''}${c.reason != null ? '\n${c.reason}' : ''}'),
              isThreeLine: c.reason != null,
              trailing: user.can(Permission.issueCredits) && c.status == 'active' ? IconButton(tooltip: 'Annuler', onPressed: () => _cancel(c), icon: const Icon(Icons.block)) : null,
            ),
          ),
      ],
    );
  }
}
