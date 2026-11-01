import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/product_io.dart';
import '../common.dart';
import '../motion.dart';
import '../theme.dart';

enum _Period { today, week, month, lastMonth, custom }

/// Marges et bénéfices (prix d'achat des produits / médicaments) et valeur du stock.
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key});
  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  _Period period = _Period.month;
  DateTimeRange? custom;
  ProfitReport? report;
  bool loading = true;

  DateTimeRange get range {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (period) {
      _Period.today => DateTimeRange(start: today, end: today.add(const Duration(days: 1))),
      _Period.week => DateTimeRange(
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: today.add(const Duration(days: 1)),
      ),
      _Period.month => DateTimeRange(start: DateTime(n.year, n.month), end: DateTime(n.year, n.month + 1)),
      _Period.lastMonth => DateTimeRange(start: DateTime(n.year, n.month - 1), end: DateTime(n.year, n.month)),
      _Period.custom => custom ?? DateTimeRange(start: today, end: today.add(const Duration(days: 1))),
    };
  }

  String get periodLabel {
    String d(DateTime x) => '${'${x.day}'.padLeft(2, '0')}/${'${x.month}'.padLeft(2, '0')}/${x.year}';
    final r = range;
    final last = r.end.subtract(const Duration(days: 1));
    return r.start == last ? d(r.start) : 'du ${d(r.start)} au ${d(last)}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && report == null) _load();
  }

  Future<void> _load() async {
    final scope = AppScope.read(context);
    final r = range;
    final data = await guard(context, () => scope.repo.profitReport(scope.user, r.start, r.end));
    if (!mounted) return;
    setState(() {
      report = data;
      loading = false;
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year, now.month, now.day), initialDateRange: custom, helpText: 'Période');
    if (picked == null) return;
    setState(() {
      period = _Period.custom;
      custom = DateTimeRange(start: picked.start, end: picked.end.add(const Duration(days: 1)));
    });
    await _load();
  }

  Future<void> _export() async {
    final r = report;
    if (r == null) return;
    final bytes = exportProfitXlsx(r, periodLabel);
    final s = range.start;
    String two(int v) => '$v'.padLeft(2, '0');
    final name = 'marges_${s.year}${two(s.month)}${two(s.day)}.xlsx';
    final saved = await FilePicker.saveFile(dialogTitle: 'Enregistrer le fichier Excel', fileName: name, bytes: bytes, type: FileType.custom, allowedExtensions: ['xlsx']);
    if (saved != null && mounted) toast(context, 'Exporté : $name');
  }

  String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)} %';

  Widget _kpi(String label, String value, IconData icon, Color color) => KpiCard(label: label, value: value, icon: icon, color: color);

  @override
  Widget build(BuildContext context) {
    final labels = {_Period.today: 'Aujourd\'hui', _Period.week: 'Cette semaine', _Period.month: 'Ce mois', _Period.lastMonth: 'Mois dernier', _Period.custom: 'Autre…'};
    final r = report;
    return Scaffold(
      appBar: gradientAppBar(
        context,
        title: const Text('Marges et bénéfices'),
        actions: [IconButton(tooltip: 'Exporter vers Excel', onPressed: r == null || r.products.isEmpty ? null : () => guard(context, _export), icon: const Icon(Icons.download))],
      ),
      body: PatternBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _Period.values)
                    ChoiceChip(
                      label: Text(labels[p]!),
                      selected: period == p,
                      showCheckmark: false,
                      selectedColor: AppColors.ink,
                      labelStyle: TextStyle(color: period == p ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600),
                      onSelected: (_) {
                        if (p == _Period.custom) {
                          _pickCustom();
                        } else {
                          setState(() => period = p);
                          _load();
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(periodLabel, style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              if (loading || r == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _kpi('Chiffre d\'affaires', fcfa(r.revenue), Icons.payments, AppColors.ink),
                    _kpi('Coût d\'achat', fcfa(r.cost), Icons.local_shipping_outlined, AppColors.amber),
                    _kpi('Bénéfice brut', fcfa(r.profit), Icons.trending_up, r.profit < 0 ? AppColors.red : AppColors.green),
                    _kpi('Marge', _pct(r.rate), Icons.percent, AppColors.orange),
                  ],
                ),
                const SectionTitle('Valeur du stock (aujourd\'hui)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _kpi('Au prix d\'achat', fcfa(r.stockValueCost), Icons.inventory_2_outlined, AppColors.ink),
                    _kpi('Au prix de vente', fcfa(r.stockValueSale), Icons.sell_outlined, AppColors.orange),
                  ],
                ),
                if (r.productsWithoutCost > 0 || r.unitsWithoutCost > 0)
                  Card(
                    color: const Color(0xFFFFF4E6),
                    child: ListTile(
                      leading: const Icon(Icons.info_outline, color: AppColors.amber),
                      title: Text(
                        [
                          if (r.productsWithoutCost > 0) '${r.productsWithoutCost} produit(s) sans prix d\'achat',
                          if (r.unitsWithoutCost > 0) '${r.unitsWithoutCost} unité(s) vendue(s) sans prix d\'achat, exclues du bénéfice',
                        ].join(' · '),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text('Renseignez-le dans Gestion > Produits, à l\'entrée de stock, ou dans la colonne « Prix d\'achat » du fichier Excel.'),
                    ),
                  ),
                SectionTitle('Par produit (${r.products.length})'),
                if (r.products.isEmpty) const EmptyState(Icons.query_stats, 'Aucune vente sur cette période.'),
                for (final (i, p) in r.products.indexed)
                  FadeSlideIn(
                    key: ValueKey('${p.productId}-${period.name}-${range.start}'),
                    index: i,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  p.quantityWithoutCost == p.quantity ? '—' : fcfa(p.profit),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: p.quantityWithoutCost == p.quantity ? AppColors.muted : (p.profit < 0 ? AppColors.red : AppColors.green),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                '${p.quantity} vendu(s)',
                                'CA ${fcfa(p.revenue)}',
                                'coût ${fcfa(p.cost)}',
                                'marge ${_pct(p.rate)}',
                                if (p.quantityWithoutCost > 0) '${p.quantityWithoutCost} sans prix d\'achat',
                              ].join(' · '),
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Bénéfice brut = ventes − prix d\'achat des unités vendues (prix d\'achat figé au moment de la vente). Les commandes annulées ne comptent pas.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
