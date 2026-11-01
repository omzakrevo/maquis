import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/money.dart';
import '../core/security.dart';
import '../data/models.dart';
import 'common.dart';
import 'scan_screen.dart';

/// Boîte d'encaissement. Renvoie le résultat si un paiement a été enregistré.
/// Résultat de l'encaissement + choix « imprimer le reçu » fait dans la boîte.
class PaymentOutcome {
  PaymentOutcome(this.result, {required this.printReceipt});
  final PaymentResult result;
  final bool printReceipt;
}

/// Dernier choix « Imprimer le reçu » (retenu pour la session de l'application).
bool _printReceiptChoice = true;

Future<PaymentOutcome?> showPaymentDialog(BuildContext context, OrderSummary order) => showDialog<PaymentOutcome>(context: context, barrierDismissible: false, builder: (_) => _PaymentDialog(order));

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog(this.order);
  final OrderSummary order;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  // Clé générée une seule fois : un double appui ne crée pas deux paiements.
  final idempotencyKey = const Uuid().v4();
  String method = 'cash';
  late final amount = TextEditingController(text: '${widget.order.balance}');
  final received = TextEditingController();
  final reference = TextEditingController();
  final code = TextEditingController();
  String operator = 'Orange Money';
  bool changeAsCredit = false;
  bool printReceipt = _printReceiptChoice;
  bool busy = false;
  String? error;
  Credit? credit;

  int get amountValue => parseFcfa(amount.text) ?? 0;
  int get receivedValue => parseFcfa(received.text) ?? amountValue;
  int get change => method == 'cash' ? (receivedValue - amountValue).clamp(0, 1 << 31) : 0;

  Future<void> _lookupCredit() async {
    final c = await AppScope.read(context).repo.creditByCode(code.text);
    setState(() {
      credit = c;
      error = c == null ? 'Code d\'avoir inconnu' : (c.status != 'active' ? 'Avoir ${c.status == 'exhausted' ? 'épuisé' : 'annulé'}' : null);
      if (c != null && c.status == 'active') {
        final use = c.balance < widget.order.balance ? c.balance : widget.order.balance;
        amount.text = '$use';
      }
    });
  }

  Future<void> _submit() async {
    if (busy) return;
    final scope = AppScope.read(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await scope.repo.pay(
        scope.user,
        PaymentRequest(
          orderId: widget.order.id,
          amount: amountValue,
          method: method,
          idempotencyKey: idempotencyKey,
          receivedCash: method == 'cash' ? receivedValue : null,
          changeAsCredit: changeAsCredit,
          reference: method == 'mobile_money' && reference.text.trim().isNotEmpty ? '$operator ${reference.text.trim()}' : null,
          creditCode: method == 'credit' ? code.text : null,
        ),
      );
      _printReceiptChoice = printReceipt;
      if (mounted) Navigator.pop(context, PaymentOutcome(r, printReceipt: printReceipt));
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final cs = Theme.of(context).colorScheme;
    // Billets probables : montant exact, arrondi au millier, aux 5 000, puis 10 000 / 20 000.
    int up(int step) => ((o.balance + step - 1) ~/ step) * step;
    final quick = ({o.balance, up(1000), up(5000), up(10000), 10000, 20000}.where((v) => v >= o.balance).toList()..sort()).take(4).toList();
    final compact = isCompact(context);
    return AlertDialog(
      titlePadding: EdgeInsets.fromLTRB(compact ? 18 : 24, compact ? 16 : 24, compact ? 18 : 24, 0),
      contentPadding: EdgeInsets.fromLTRB(compact ? 18 : 24, 12, compact ? 18 : 24, 0),
      actionsPadding: EdgeInsets.fromLTRB(12, 8, compact ? 12 : 24, compact ? 12 : 20),
      title: Text('Encaisser · N° ${o.number}${o.tableLabel == 'Vente directe' ? '' : ' · ${o.tableLabel}'}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [Expanded(child: Text('Total ${fcfa(o.total)} · déjà payé ${fcfa(o.paid)}'))]),
              Text(
                'Reste à payer : ${fcfa(o.balance)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: !compact,
                style: compact ? SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)) : null,
                segments: [
                  ButtonSegment(value: 'cash', icon: compact ? null : const Icon(Icons.payments_outlined), label: const Text('Espèces', maxLines: 1, softWrap: false)),
                  ButtonSegment(value: 'mobile_money', icon: compact ? null : const Icon(Icons.phone_android), label: const Text('Mobile', maxLines: 1, softWrap: false)),
                  ButtonSegment(value: 'credit', icon: compact ? null : const Icon(Icons.confirmation_number_outlined), label: const Text('Avoir', maxLines: 1, softWrap: false)),
                ],
                selected: {method},
                onSelectionChanged: (s) => setState(() {
                  method = s.first;
                  error = null;
                  if (method != 'credit') amount.text = '${o.balance}';
                }),
              ),
              const SizedBox(height: 12),
              if (method == 'credit') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Code de l\'avoir (ex. ABCD-EFGH)', border: OutlineInputBorder()),
                        onSubmitted: (_) => _lookupCredit(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(onPressed: _lookupCredit, icon: const Icon(Icons.search)),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      tooltip: 'Scanner le QR du bon d\'avoir',
                      onPressed: () async {
                        final v = await scanCode(context, title: 'Scanner le bon d\'avoir');
                        if (v == null) return;
                        code.text = v.toUpperCase().startsWith('AVOIR:') ? v.substring(6) : v;
                        await _lookupCredit();
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ],
                ),
                if (credit != null && credit!.status == 'active') Padding(padding: const EdgeInsets.only(top: 6), child: Text('Solde de l\'avoir : ${fcfa(credit!.balance)}')),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Montant encaissé', suffixText: 'F', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              if (method == 'cash') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: received,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Somme donnée par le client', suffixText: 'F', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [for (final v in quick) ActionChip(label: Text(fcfa(v)), onPressed: () => setState(() => received.text = '$v'))],
                ),
                if (change > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Monnaie à rendre : ${fcfa(change)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.tertiary),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: changeAsCredit,
                    onChanged: (v) => setState(() => changeAsCredit = v ?? false),
                    title: const Text('Pas de monnaie : donner un bon d\'avoir'),
                    subtitle: const Text('Le client reçoit un code à utiliser plus tard'),
                  ),
                ],
              ],
              if (method == 'mobile_money') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: operator,
                  decoration: const InputDecoration(labelText: 'Opérateur', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Orange Money', child: Text('Orange Money')),
                    DropdownMenuItem(value: 'Moov Money', child: Text('Moov Money')),
                    DropdownMenuItem(value: 'Wave', child: Text('Wave')),
                    DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                  ],
                  onChanged: (v) => setState(() => operator = v ?? 'Orange Money'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Référence (SMS)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 6),
                Text('Vérifiez le SMS de confirmation avant de valider : l\'application n\'interroge pas l\'opérateur.', style: TextStyle(color: cs.outline, fontSize: 12)),
              ],
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: printReceipt,
                onChanged: (v) => setState(() => printReceipt = v),
                secondary: const Icon(Icons.receipt_long),
                title: const Text('Imprimer le reçu', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(printReceipt ? 'Le reçu « PAYÉ » sortira après validation' : 'Pas de ticket pour ce paiement'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton.icon(
          onPressed: busy || amountValue <= 0 || (method == 'credit' && normalizeCreditCode(code.text).length != 8) ? null : _submit,
          icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
          label: Text('Valider ${fcfa(amountValue)}'),
        ),
      ],
    );
  }
}
