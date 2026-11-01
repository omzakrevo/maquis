import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../data/models.dart';
import '../../data/product_io.dart';
import '../common.dart';
import '../motion.dart';
import '../theme.dart';

enum _Period { today, week, month, lastMonth, custom }

/// Ventes par serveuse sur une période + prime calculée (paie de fin de mois).
class ServerSalesScreen extends StatefulWidget {
  const ServerSalesScreen({super.key});
  @override
  State<ServerSalesScreen> createState() => _ServerSalesScreenState();
}

class _ServerSalesScreenState extends State<ServerSalesScreen> {
  _Period period = _Period.month;
  DateTimeRange? custom;
  List<ServerSales> rows = [];
  BonusRules rules = const BonusRules();
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
    if (loading && rows.isEmpty) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final r = range;
    final data = await repo.serverSales(r.start, r.end);
    final b = await repo.bonusRules();
    if (!mounted) return;
    setState(() {
      rows = data;
      rules = b;
      loading = false;
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: custom,
      helpText: 'Période des ventes',
    );
    if (picked == null) return;
    setState(() {
      period = _Period.custom;
      custom = DateTimeRange(start: picked.start, end: picked.end.add(const Duration(days: 1)));
    });
    await _load();
  }

  Future<void> _editRules() async {
    final scope = AppScope.read(context);
    final perDrink = TextEditingController(text: rules.perDrink == 0 ? '' : '${rules.perDrink}');
    final percent = TextEditingController(text: rules.percent == 0 ? '' : '${rules.percent}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Règle de prime'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('La prime de chaque serveuse = boissons vendues × montant par boisson + pourcentage de son chiffre d\'affaires. Laissez vide ce que vous n\'utilisez pas.'),
              const SizedBox(height: 12),
              TextField(
                controller: perDrink,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Par boisson vendue', suffixText: 'F'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: percent,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Pourcentage du chiffre d\'affaires', suffixText: '%'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = BonusRules(perDrink: parseFcfa(perDrink.text) ?? 0, percent: double.tryParse(percent.text.replaceAll(',', '.').trim()) ?? 0);
    await guard(context, () => scope.repo.saveBonusRules(scope.user, r), success: 'Règle de prime enregistrée');
    await _load();
  }

  Future<void> _export() async {
    final bytes = exportServerSalesXlsx(rows, rules, periodLabel);
    final r = range;
    String two(int v) => '$v'.padLeft(2, '0');
    final name = 'ventes_serveuses_${r.start.year}${two(r.start.month)}${two(r.start.day)}.xlsx';
    final saved = await FilePicker.saveFile(dialogTitle: 'Enregistrer le fichier Excel', fileName: name, bytes: bytes, type: FileType.custom, allowedExtensions: ['xlsx']);
    if (saved != null && mounted) toast(context, 'Exporté : $name');
  }

  Future<void> _detail(ServerSales s) async {
    final r = range;
    final items = await AppScope.read(context).repo.serverProducts(s.userId, r.start, r.end);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(s.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(periodLabel, style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            for (final i in items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.cream,
                  child: Text(
                    '${i.quantity}',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink),
                  ),
                ),
                trailing: Text(fcfa(i.total), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {bool strong = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      Text(
        value,
        style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w700, fontSize: strong ? 16 : 15, color: strong ? AppColors.orange : AppColors.ink),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user;
    int sum(int Function(ServerSales) f) => rows.fold(0, (a, r) => a + f(r));
    final labels = {_Period.today: 'Aujourd\'hui', _Period.week: 'Cette semaine', _Period.month: 'Ce mois', _Period.lastMonth: 'Mois dernier', _Period.custom: 'Autre…'};
    return Scaffold(
      appBar: gradientAppBar(
        context,
        title: const Text('Ventes par serveuse'),
        actions: [IconButton(tooltip: 'Exporter vers Excel', onPressed: rows.isEmpty ? null : () => guard(context, _export), icon: const Icon(Icons.download))],
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
              Card(
                child: ListTile(
                  leading: Icon(Icons.workspace_premium, color: AppColors.orange),
                  title: const Text('Règle de prime', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    rules.isSet
                        ? '${rules.perDrink > 0 ? '${fcfa(rules.perDrink)} par boisson' : ''}${rules.perDrink > 0 && rules.percent > 0 ? ' + ' : ''}${rules.percent > 0 ? '${rules.percent} % du CA' : ''}'
                        : 'Aucune prime définie',
                  ),
                  trailing: user.can(Permission.manageSettings) ? TextButton(onPressed: _editRules, child: const Text('Modifier')) : null,
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (rows.isEmpty)
                const EmptyState(Icons.person_search, 'Aucune vente sur cette période.')
              else ...[
                for (final (i, s) in rows.indexed)
                  FadeSlideIn(
                    key: ValueKey('${s.userId}-${period.name}-${range.start}'),
                    index: i,
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _detail(s),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppColors.orange.withValues(alpha: 0.12),
                                    child: Text(
                                      s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                                      style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(s.role.label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: AppColors.muted),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 18,
                                runSpacing: 8,
                                children: [
                                  _stat('Commandes', '${s.orders}'),
                                  _stat('Boissons', '${s.drinks}'),
                                  _stat('Articles', '${s.items}'),
                                  _stat('Chiffre d\'affaires', fcfa(s.revenue)),
                                  _stat('Encaissé', fcfa(s.collected)),
                                  if (rules.isSet) _stat('Prime', fcfa(rules.bonusFor(s)), strong: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Card(
                  color: AppColors.cream,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _stat('TOTAL boissons', '${sum((r) => r.drinks)}'),
                        _stat('TOTAL CA', fcfa(sum((r) => r.revenue))),
                        if (rules.isSet) _stat('TOTAL primes', fcfa(sum(rules.bonusFor)), strong: true),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    '« Boissons » = articles du poste Bar. Les commandes annulées ne comptent pas. Touchez une serveuse pour le détail par produit.',
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
