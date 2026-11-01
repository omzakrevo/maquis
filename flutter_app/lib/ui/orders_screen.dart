import 'dart:async';

import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/permissions.dart';
import '../data/models.dart';
import '../printing/ticket_builder.dart';
import 'common.dart';
import 'order_screen.dart';
import 'payment_dialog.dart';
import 'scan_screen.dart';
import 'theme.dart';
import 'ticket_preview.dart';
import 'motion.dart';

/// Commandes ouvertes (non soldées) : ajout, addition, encaissement, annulation.
class OpenOrdersScreen extends StatefulWidget {
  const OpenOrdersScreen({super.key});
  @override
  State<OpenOrdersScreen> createState() => _OpenOrdersScreenState();
}

class _OpenOrdersScreenState extends State<OpenOrdersScreen> {
  List<OrderSummary> orders = [];
  CashSession? session;
  bool loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final o = await repo.openOrders();
    final s = await repo.currentSession();
    if (!mounted) return;
    setState(() {
      orders = o;
      session = s;
      loading = false;
    });
  }

  Future<void> _pay(OrderSummary o) async {
    if (session == null) {
      toast(context, 'Ouvrez la caisse (onglet Caisse) avant d\'encaisser', error: true);
      return;
    }
    await runPaymentFlow(context, o);
    await _load();
  }

  /// Imprime le ticket client de la commande en attente (aperçu si pas d'imprimante).
  Future<void> _bill(OrderSummary o, {bool preview = false}) async {
    final scope = AppScope.read(context);
    final d = await scope.repo.orderDetail(o.id);
    final shop = await scope.repo.shopInfo();
    if (!mounted) return;
    final t = customerReceipt(shop, d);
    final configured = await scope.printer.isConfigured();
    if (!mounted) return;
    if (preview) {
      await showTicket(context, t);
    } else if (configured) {
      final ok = await guard(context, () => scope.printer.print(t).then((_) => true));
      if (!mounted) return;
      if (ok == true) {
        toast(context, 'Ticket N° ${o.number} imprimé');
      } else {
        await showTicket(context, t);
      }
    } else {
      await showTicket(context, t);
    }
  }

  /// Réimprime les bons de préparation (bar / cuisine) de toute la commande.
  Future<void> _reprintPreparation(OrderSummary o) async {
    final scope = AppScope.read(context);
    final d = await scope.repo.orderDetail(o.id);
    final byStation = <Station, List<CartLine>>{};
    for (final i in d.items) {
      byStation.putIfAbsent(i.station, () => []).add(CartLine(Product(id: '', name: i.name, category: '', price: i.price, station: i.station), i.quantity));
    }
    for (final e in byStation.entries) {
      if (!mounted) return;
      await printOrPreview(context, preparationTicket(station: e.key, orderNumber: o.number, tableLabel: o.tableLabel, lines: e.value, note: o.note, serverName: o.serverName));
    }
  }

  Future<void> _add(OrderSummary o) async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddItemsPage(target: o)));
    await _load();
  }

  Future<void> _cancel(OrderSummary o) async {
    final scope = AppScope.read(context);
    final reason = await promptText(context, 'Annuler N° ${o.number}', label: 'Motif (obligatoire)', ok: 'Annuler la commande', minLength: 3);
    if (reason == null || !mounted) return;
    await guard(context, () => scope.repo.cancelOrder(scope.user, o.id, reason), success: 'Commande annulée');
    await _load();
  }

  Future<void> _details(OrderSummary o) async {
    final d = await AppScope.read(context).repo.orderDetail(o.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('N° ${o.number} · ${o.tableLabel}'),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (o.note != null) ListTile(leading: const Icon(Icons.sticky_note_2_outlined), title: Text(o.note!)),
              for (final i in d.items) ListTile(dense: true, title: Text('${i.quantity} × ${i.name}'), subtitle: Text(i.station.label), trailing: Text(fcfa(i.total))),
              const Divider(),
              for (final p in d.payments)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(methodLabel(p.method)),
                  subtitle: Text('${timeOf(p.createdAt)}${p.reference != null ? ' · ${p.reference}' : ''}'),
                  trailing: Text(fcfa(p.amount)),
                ),
              ListTile(
                title: const Text('Reste à payer', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text(fcfa(d.summary.balance), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _reprintPreparation(o);
            },
            icon: const Icon(Icons.soup_kitchen_outlined),
            label: const Text('Bons bar/cuisine'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _bill(o, preview: true);
            },
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Aperçu'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _bill(o);
            },
            icon: const Icon(Icons.print),
            label: const Text('Imprimer le ticket'),
          ),
        ],
      ),
    );
  }

  String _tableShort(String label) {
    final m = RegExp(r'(\d+)$').firstMatch(label);
    if (m != null) return m.group(1)!;
    if (label.toLowerCase().startsWith('à emporter')) return 'EMP';
    return label.isEmpty ? '?' : label.substring(0, label.length < 3 ? label.length : 3).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user;
    if (loading) return const Center(child: CircularProgressIndicator());
    final totalDue = orders.fold<int>(0, (a, o) => a + o.balance);
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (session == null && user.can(Permission.takePayments))
            Card(
              color: cs.errorContainer,
              child: const ListTile(leading: Icon(Icons.lock_outline), title: Text('Caisse fermée'), subtitle: Text('Ouvrez la caisse dans l\'onglet Caisse pour encaisser.')),
            ),
          // Bandeau récapitulatif + scan rapide
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${orders.length} commande(s) non soldée(s)',
                        style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                      ),
                      AnimatedAmount(
                        totalDue,
                        style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 26),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  onPressed: () => scanAndOpen(context, onChanged: _load),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner'),
                ),
              ],
            ),
          ),
          if (orders.isEmpty) const EmptyState(Icons.check_circle_outline, 'Aucune commande en attente de paiement.'),
          for (final (i, o) in orders.indexed)
            FadeSlideIn(
              key: ValueKey(o.id),
              index: i,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 4, color: o.paid > 0 ? AppColors.amber : Colors.transparent),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => _details(o),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.cream,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: AppColors.line),
                                      ),
                                      child: Text(
                                        _tableShort(o.tableLabel),
                                        style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${o.tableLabel} · N° ${o.number}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                          Text(
                                            '${timeOf(o.createdAt)}${o.serverName != null ? ' · ${o.serverName}' : ''}${o.note != null ? ' · « ${o.note} »' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Colors.grey.shade700),
                                          ),
                                          if (o.paid > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: LinearProgressIndicator(value: o.total == 0 ? 0 : o.paid / o.total, minHeight: 6, color: AppColors.orange, backgroundColor: AppColors.line),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          fcfa(o.balance),
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.ink),
                                        ),
                                        if (o.paid > 0) Text('payé ${fcfa(o.paid)} / ${fcfa(o.total)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton.icon(onPressed: () => _add(o), icon: const Icon(Icons.add), label: const Text('Ajouter')),
                                  OutlinedButton.icon(onPressed: () => _bill(o), icon: const Icon(Icons.print_outlined), label: const Text('Imprimer')),
                                  if (user.can(Permission.cancelOrders) && o.paid == 0)
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                                      onPressed: () => _cancel(o),
                                      icon: const Icon(Icons.close),
                                      label: const Text('Annuler'),
                                    ),
                                  if (user.can(Permission.takePayments)) FilledButton.icon(onPressed: () => _pay(o), icon: const Icon(Icons.payments), label: const Text('Encaisser')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Encaissement complet : paiement, bon d'avoir éventuel, reçu. Renvoie true si un paiement a eu lieu.
Future<bool> runPaymentFlow(BuildContext context, OrderSummary o) async {
  final scope = AppScope.read(context);
  if (await scope.repo.currentSession() == null) {
    if (context.mounted) toast(context, 'Ouvrez la caisse (onglet Caisse) avant d\'encaisser', error: true);
    return false;
  }
  if (!context.mounted) return false;
  final outcome = await showPaymentDialog(context, o);
  final r = outcome?.result;
  if (outcome == null || r == null || !context.mounted) return false;
  if (r.orderClosed) {
    await showSuccessCheck(context, 'Commande soldée', detail: r.change > 0 ? 'Rendre ${fcfa(r.change)} au client' : null);
    if (!context.mounted) return true;
  } else {
    final msg = StringBuffer('Paiement partiel enregistré');
    if (r.change > 0) msg.write(' · Rendre ${fcfa(r.change)}');
    toast(context, msg.toString());
  }
  final shop = await scope.repo.shopInfo();
  if (r.issuedCreditCode != null) {
    final c = await scope.repo.creditByCode(r.issuedCreditCode!);
    if (!context.mounted || c == null) return true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bon d\'avoir émis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Montant : ${fcfa(r.issuedCreditAmount)}'),
            const SizedBox(height: 8),
            SelectableText(r.issuedCreditCode!, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 8),
            const Text('Remettez ce code au client (ticket ou photo). Il ne sera plus affiché ensuite.', textAlign: TextAlign.center),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continuer'))],
      ),
    );
    if (!context.mounted) return true;
    await printOrPreview(context, creditVoucher(shop, IssuedCredit(c, r.issuedCreditCode!)));
  }
  if (r.orderClosed && context.mounted) {
    final d = await scope.repo.orderDetail(o.id);
    if (!context.mounted) return true;
    if (outcome.printReceipt) await printOrPreview(context, customerReceipt(shop, d, cashierName: scope.user.name));
  }
  return true;
}
