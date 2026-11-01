import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../common.dart';
import 'stock_history_screen.dart';
import '../theme.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<Product> products = [];
  List<StockMovement> moves = [];
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = (await repo.products(includeInactive: true)).where((p) => p.trackStock).toList();
    final m = await repo.stockMovements(limit: 100);
    if (!mounted) return;
    setState(() {
      products = p;
      moves = m;
      loading = false;
    });
  }

  Future<void> _adjust(Product p) async {
    final scope = AppScope.read(context);
    final qty = TextEditingController();
    final note = TextEditingController();
    final unitCost = TextEditingController(text: p.cost == null ? '' : '${p.cost}');
    var mode = 'in';
    var reason = 'Livraison fournisseur';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${p.name} · stock ${p.stockQty}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: !isCompact(context),
                segments: [
                  ButtonSegment(value: 'in', icon: isCompact(context) ? null : const Icon(Icons.add), label: const Text('Entrée', maxLines: 1, softWrap: false)),
                  ButtonSegment(value: 'out', icon: isCompact(context) ? null : const Icon(Icons.remove), label: const Text('Sortie', maxLines: 1, softWrap: false)),
                  ButtonSegment(value: 'count', icon: isCompact(context) ? null : const Icon(Icons.fact_check_outlined), label: const Text('Inventaire', maxLines: 1, softWrap: false)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => set(() {
                  mode = s.first;
                  reason = switch (mode) {
                    'in' => 'Livraison fournisseur',
                    'out' => 'Casse / perte',
                    _ => 'Inventaire',
                  };
                }),
              ),
              TextField(
                controller: qty,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: mode == 'count' ? 'Quantité comptée' : 'Quantité'),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(mode),
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Motif'),
                items: [
                  for (final r in switch (mode) {
                    'in' => ['Livraison fournisseur', 'Retour', 'Correction'],
                    'out' => ['Casse / perte', 'Consommation personnel', 'Offert', 'Correction'],
                    _ => ['Inventaire'],
                  })
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) => reason = v ?? reason,
              ),
              if (mode == 'in')
                TextField(
                  controller: unitCost,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Prix d\'achat unitaire (facultatif)',
                    suffixText: 'F',
                    prefixIcon: const Icon(Icons.sell_outlined),
                    helperText: p.cost == null ? 'Sert au calcul des marges' : 'Dernier prix d\'achat : ${fcfa(p.cost!)}',
                  ),
                ),
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: mode == 'in' ? 'Fournisseur / n° de bon (facultatif)' : 'Précision (facultatif)', prefixIcon: const Icon(Icons.edit_note)),
              ),
              const SizedBox(height: 8),
              Text('Enregistré au nom de ${scope.user.name}, avec la date et l\'heure.', style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final n = int.tryParse(qty.text);
    if (n == null) return;
    final delta = switch (mode) {
      'in' => n,
      'out' => -n,
      _ => n - p.stockQty,
    };
    if (delta == 0) {
      toast(context, 'Stock déjà juste');
      return;
    }
    final uc = mode == 'in' ? parseFcfa(unitCost.text) : null;
    await guard(
      context,
      () => scope.repo.adjustStock(scope.user, p.id, delta, reason, note: note.text, unitCost: uc),
      success: 'Stock mis à jour',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final low = products.where((p) => p.lowStock).length;
    return Scaffold(
      appBar: gradientAppBar(
        context,
        title: const Text('Stocks'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockHistoryScreen())).then((_) => _load()),
            icon: const Icon(Icons.history_edu),
            label: const Text('Historique'),
          ),
        ],
      ),
      body: PatternBackground(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      KpiCard(label: 'Produits suivis', value: '${products.length}', icon: Icons.inventory_2, color: AppColors.ink, width: 180),
                      KpiCard(label: 'En stock bas', value: '$low', icon: Icons.warning_amber, color: low > 0 ? AppColors.red : AppColors.muted, width: 180),
                      KpiCard(label: 'Mouvements récents', value: '${moves.length}', icon: Icons.swap_vert, color: AppColors.muted, width: 180),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (products.isEmpty) const EmptyState(Icons.inventory_2_outlined, 'Aucun produit suivi.\nActivez « Suivre le stock » dans Produits.'),
                  for (final p in products)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: ProductImage(image: p.image, category: p.category, name: p.name),
                          ),
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          p.lowStock ? 'Stock bas · alerte à ${p.alertQty}' : 'Alerte à ${p.alertQty}',
                          style: TextStyle(color: p.lowStock ? AppColors.red : null, fontWeight: p.lowStock ? FontWeight.w700 : null),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: p.lowStock ? AppColors.red : AppColors.cream,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: p.lowStock ? AppColors.red : AppColors.line),
                              ),
                              child: Text(
                                '${p.stockQty}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Historique de ${p.name}',
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockHistoryScreen(product: p))),
                              icon: const Icon(Icons.history),
                            ),
                          ],
                        ),
                        onTap: () => _adjust(p),
                      ),
                    ),
                  if (products.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Touchez un produit pour enregistrer une entrée (livraison), une sortie ou un inventaire.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
