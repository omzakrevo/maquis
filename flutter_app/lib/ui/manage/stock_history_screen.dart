import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../common.dart';
import '../theme.dart';
import '../motion.dart';

enum _Period {
  today('Aujourd\'hui'),
  week('7 jours'),
  month('30 jours'),
  all('Tout');

  const _Period(this.label);
  final String label;

  DateTime? get from {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Period.today => midnight,
      _Period.week => midnight.subtract(const Duration(days: 6)),
      _Period.month => midnight.subtract(const Duration(days: 29)),
      _Period.all => null,
    };
  }
}

/// Historique des mouvements de stock : quelle entrée, combien, quand, par qui.
class StockHistoryScreen extends StatefulWidget {
  const StockHistoryScreen({super.key, this.product});
  final Product? product;
  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  List<StockMovement> moves = [];
  List<Product> products = [];
  StockKind? kind = StockKind.entry; // par défaut : les entrées (livraisons)
  _Period period = _Period.month;
  String? productId;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    productId = widget.product?.id;
    if (widget.product != null) kind = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && products.isEmpty) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = (await repo.products(includeInactive: true)).where((x) => x.trackStock || x.id == productId).toList();
    final m = await repo.stockMovements(productId: productId, kind: kind, from: period.from, limit: 1000);
    if (!mounted) return;
    setState(() {
      products = p;
      moves = m;
      loading = false;
    });
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  static Color colorOf(StockKind k) => switch (k) {
    StockKind.entry => AppColors.green,
    StockKind.exit => AppColors.red,
    StockKind.sale => AppColors.orange,
    StockKind.count => AppColors.ink,
    StockKind.cancel => AppColors.muted,
  };

  static IconData iconOf(StockKind k) => switch (k) {
    StockKind.entry => Icons.local_shipping,
    StockKind.exit => Icons.remove_shopping_cart,
    StockKind.sale => Icons.point_of_sale,
    StockKind.count => Icons.fact_check,
    StockKind.cancel => Icons.undo,
  };

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    const days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Hier';
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _chip(String label, bool selected, Color color, VoidCallback onTap, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(right: 6, bottom: 6),
    child: ChoiceChip(
      avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? Colors.white : color),
      backgroundColor: Colors.white,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.ink,
      labelStyle: TextStyle(color: selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600),
      side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
      onSelected: (_) => onTap(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final entries = moves.where((m) => m.kind == StockKind.entry).fold<int>(0, (a, m) => a + m.delta);
    final exits = moves.where((m) => m.kind == StockKind.exit).fold<int>(0, (a, m) => a - m.delta);
    final sales = moves.where((m) => m.kind == StockKind.sale).fold<int>(0, (a, m) => a - m.delta);
    final rows = <Widget>[];
    String? lastDay;
    for (final m in moves) {
      final day = _day(m.createdAt);
      if (day != lastDay) {
        rows.add(SectionTitle(day));
        lastDay = day;
      }
      final k = m.kind;
      final c = colorOf(k);
      rows.add(
        FadeSlideIn(
          key: ValueKey('${m.createdAt.microsecondsSinceEpoch}-${m.productName}-${m.delta}-${kind?.name}-${period.name}-$productId'),
          index: rows.length,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 6, color: c),
                  Expanded(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: ProductImage(image: m.productImage, category: '', name: m.productName),
                            ),
                          ),
                          Positioned(
                            right: -6,
                            bottom: -6,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: c,
                              child: Icon(iconOf(k), size: 13, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      title: Text(m.productName, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [m.reason, if (m.orderNumber != null) 'commande N° ${m.orderNumber}', if (m.unitCost != null) 'achat ${fcfa(m.unitCost!)} / u', if (m.note != null) m.note!].join(' · '),
                          ),
                          Row(
                            children: [
                              Icon(Icons.person, size: 14, color: Colors.grey.shade700),
                              const SizedBox(width: 3),
                              Text(m.userName ?? 'inconnu', style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(width: 10),
                              Icon(Icons.schedule, size: 14, color: Colors.grey.shade700),
                              const SizedBox(width: 3),
                              Text(timeOf(m.createdAt)),
                            ],
                          ),
                        ],
                      ),
                      trailing: Text(
                        m.delta > 0 ? '+${m.delta}' : '${m.delta}',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: gradientAppBar(context, title: Text(widget.product == null ? 'Historique des stocks' : 'Historique · ${widget.product!.name}')),
      body: PatternBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        children: [
                          _chip('Tous', kind == null, AppColors.ink, () => _set(() => kind = null), icon: Icons.all_inclusive),
                          for (final k in StockKind.values) _chip(k.label, kind == k, colorOf(k), () => _set(() => kind = k), icon: iconOf(k)),
                        ],
                      ),
                      Wrap(
                        children: [
                          for (final p in _Period.values) _chip(p.label, period == p, AppColors.ink, () => _set(() => period = p), icon: p == _Period.all ? Icons.calendar_month : Icons.date_range),
                        ],
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue: productId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Produit', isDense: true, prefixIcon: Icon(Icons.local_offer_outlined)),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Tous les produits')),
                          for (final p in products) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (v) => _set(() => productId = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  KpiCard(label: 'Entrées', value: entries == 0 ? '0' : '+$entries', icon: Icons.local_shipping, color: AppColors.green, width: 160),
                  KpiCard(label: 'Sorties / pertes', value: exits == 0 ? '0' : '-$exits', icon: Icons.remove_shopping_cart, color: AppColors.red, width: 160),
                  KpiCard(label: 'Vendus', value: '$sales', icon: Icons.point_of_sale, color: AppColors.orange, width: 160),
                ],
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (moves.isEmpty)
                const EmptyState(Icons.history_toggle_off, 'Aucun mouvement pour ces filtres.')
              else
                ...rows,
            ],
          ),
        ),
      ),
    );
  }
}
