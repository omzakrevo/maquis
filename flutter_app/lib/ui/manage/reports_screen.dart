import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/report_export.dart';
import '../common.dart';
import '../motion.dart';
import '../theme.dart';
import '../ticket_preview.dart';

enum ReportPeriod { today, yesterday, day, week, month, lastMonth, monthPick, custom }

/// Rapports détaillés : journalier, mensuel ou sur une période ; export PDF, Excel et ticket.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initial = ReportPeriod.today});
  final ReportPeriod initial;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late ReportPeriod period = widget.initial;
  DateTime? day;
  DateTime? month;
  DateTimeRange? custom;
  SalesReport? report;
  bool loading = true;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTimeRange get range {
    final t = _today;
    DateTimeRange oneDay(DateTime d) => DateTimeRange(start: d, end: DateTime(d.year, d.month, d.day + 1));
    return switch (period) {
      ReportPeriod.today => oneDay(t),
      ReportPeriod.yesterday => oneDay(DateTime(t.year, t.month, t.day - 1)),
      ReportPeriod.day => oneDay(day ?? t),
      ReportPeriod.week => DateTimeRange(start: DateTime(t.year, t.month, t.day - (t.weekday - 1)), end: DateTime(t.year, t.month, t.day + 1)),
      ReportPeriod.month => DateTimeRange(start: DateTime(t.year, t.month), end: DateTime(t.year, t.month + 1)),
      ReportPeriod.lastMonth => DateTimeRange(start: DateTime(t.year, t.month - 1), end: DateTime(t.year, t.month)),
      ReportPeriod.monthPick => DateTimeRange(start: month ?? DateTime(t.year, t.month), end: DateTime((month ?? t).year, (month ?? t).month + 1)),
      ReportPeriod.custom => custom ?? oneDay(t),
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && report == null) _load();
  }

  Future<void> _load() async {
    final scope = AppScope.read(context);
    final r = range;
    setState(() => loading = true);
    final data = await guard(context, () => scope.repo.salesReport(scope.user, r.start, r.end));
    if (!mounted) return;
    setState(() {
      report = data;
      loading = false;
    });
  }

  Future<void> _select(ReportPeriod p) async {
    final now = DateTime.now();
    switch (p) {
      case ReportPeriod.day:
        final d = await showDatePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: _today, initialDate: day ?? _today, helpText: 'Rapport du jour');
        if (d == null) return;
        day = d;
      case ReportPeriod.monthPick:
        final m = await _pickMonth();
        if (m == null) return;
        month = m;
      case ReportPeriod.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 3),
          lastDate: _today,
          initialDateRange: custom == null ? null : DateTimeRange(start: custom!.start, end: custom!.end.subtract(const Duration(days: 1))),
          helpText: 'Période du rapport',
        );
        if (picked == null) return;
        custom = DateTimeRange(start: picked.start, end: DateTime(picked.end.year, picked.end.month, picked.end.day + 1));
      default:
        break;
    }
    setState(() => period = p);
    await _load();
  }

  Future<DateTime?> _pickMonth() {
    const names = ['Janv.', 'Févr.', 'Mars', 'Avril', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.'];
    var year = (month ?? _today).year;
    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Row(
            children: [
              IconButton(onPressed: () => set(() => year--), icon: const Icon(Icons.chevron_left)),
              Expanded(child: Text('$year', textAlign: TextAlign.center)),
              IconButton(onPressed: year >= _today.year ? null : () => set(() => year++), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var m = 1; m <= 12; m++)
                  SizedBox(
                    width: 88,
                    child: OutlinedButton(onPressed: DateTime(year, m).isAfter(_today) ? null : () => Navigator.pop(ctx, DateTime(year, m)), child: Text(names[m - 1])),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final scope = AppScope.read(context);
    final r = report!;
    final bytes = salesReportPdf(await scope.repo.shopInfo(), r, accentRgb: AppColors.orange.toARGB32() & 0xFFFFFF);
    final name = reportFileName(r, 'pdf');
    final saved = await FilePicker.saveFile(dialogTitle: 'Enregistrer le rapport PDF', fileName: name, bytes: bytes, type: FileType.custom, allowedExtensions: ['pdf']);
    if (saved != null && mounted) toast(context, 'Rapport PDF enregistré : $name');
  }

  Future<void> _exportXlsx() async {
    final scope = AppScope.read(context);
    final r = report!;
    final bytes = salesReportXlsx(await scope.repo.shopInfo(), r);
    final name = reportFileName(r, 'xlsx');
    final saved = await FilePicker.saveFile(dialogTitle: 'Enregistrer le rapport Excel', fileName: name, bytes: bytes, type: FileType.custom, allowedExtensions: ['xlsx']);
    if (saved != null && mounted) toast(context, 'Rapport Excel enregistré : $name');
  }

  Future<void> _printTicket() async {
    final scope = AppScope.read(context);
    final ticket = salesReportTicket(await scope.repo.shopInfo(), report!);
    if (mounted) await printOrPreview(context, ticket);
  }

  String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1).replaceAll('.', ',')} %';

  @override
  Widget build(BuildContext context) {
    final labels = {
      ReportPeriod.today: 'Aujourd\'hui',
      ReportPeriod.yesterday: 'Hier',
      ReportPeriod.day: day == null || period != ReportPeriod.day ? 'Un jour…' : reportPeriodLabel(range.start, range.end).replaceFirst('Journée du ', ''),
      ReportPeriod.week: 'Cette semaine',
      ReportPeriod.month: 'Ce mois',
      ReportPeriod.lastMonth: 'Mois dernier',
      ReportPeriod.monthPick: month == null || period != ReportPeriod.monthPick ? 'Un mois…' : reportPeriodLabel(range.start, range.end),
      ReportPeriod.custom: 'Période…',
    };
    final r = report;
    final ready = !loading && r != null;
    return Scaffold(
      appBar: gradientAppBar(
        context,
        title: const Text('Rapports'),
        actions: [
          IconButton(tooltip: 'Imprimer en ticket', onPressed: ready ? () => guard(context, _printTicket) : null, icon: const Icon(Icons.print)),
          PopupMenuButton<String>(
            tooltip: 'Exporter',
            enabled: ready,
            icon: const Icon(Icons.ios_share),
            onSelected: (v) => guard(context, v == 'pdf' ? _exportPdf : _exportXlsx),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf, color: Color(0xFFC92A2A)),
                  title: Text('Exporter en PDF'),
                ),
              ),
              PopupMenuItem(
                value: 'xlsx',
                child: ListTile(
                  leading: Icon(Icons.table_chart, color: Color(0xFF2F9E44)),
                  title: Text('Exporter en Excel'),
                ),
              ),
            ],
          ),
        ],
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
                  for (final p in ReportPeriod.values)
                    ChoiceChip(
                      key: ValueKey('period-${p.name}'),
                      label: Text(labels[p]!),
                      selected: period == p,
                      showCheckmark: false,
                      selectedColor: AppColors.ink,
                      labelStyle: TextStyle(color: period == p ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600),
                      onSelected: (_) => _select(p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event, size: 18, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(reportPeriodLabel(range.start, range.end), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!ready)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    KpiCard(label: 'Chiffre d\'affaires', value: fcfa(r.revenue), icon: Icons.payments, color: AppColors.orange),
                    KpiCard(label: 'Nombre de ventes', value: '${r.orders}', icon: Icons.receipt_long, color: AppColors.ink),
                    KpiCard(label: 'Articles vendus', value: '${r.items}', icon: Icons.shopping_basket_outlined, color: AppColors.ink),
                    KpiCard(label: 'Panier moyen', value: fcfa(r.averageBasket), icon: Icons.shopping_cart_outlined, color: AppColors.amber),
                    KpiCard(label: 'Encaissé', value: fcfa(r.collected), icon: Icons.account_balance_wallet_outlined, color: AppColors.green),
                    KpiCard(label: 'Reste à encaisser', value: fcfa(r.unpaid), icon: Icons.hourglass_bottom, color: r.unpaid > 0 ? AppColors.red : AppColors.muted),
                    if (r.hasCost) KpiCard(label: 'Bénéfice brut', value: fcfa(r.profit), icon: Icons.trending_up, color: r.profit < 0 ? AppColors.red : AppColors.green),
                    if (r.hasCost) KpiCard(label: 'Marge', value: _pct(r.marginRate), icon: Icons.percent, color: AppColors.orange),
                    KpiCard(label: 'Annulations', value: '${r.cancelledCount} · ${fcfa(r.cancelledTotal)}', icon: Icons.block, color: AppColors.muted),
                  ],
                ),
                const SizedBox(height: 8),
                _ExportBar(onPdf: () => guard(context, _exportPdf), onXlsx: () => guard(context, _exportXlsx), onPrint: () => guard(context, _printTicket)),
                if (r.orders == 0) const EmptyState(Icons.query_stats, 'Aucune vente sur cette période.'),
                if (r.orders > 0) ...[
                  if (r.days.length > 1) ...[
                    SectionTitle('Chiffre d\'affaires par jour${r.bestDay == null ? '' : ' · meilleur : ${r.bestDay!.label}'}'),
                    _ChartCard(labels: [for (final d in r.days) d.label], values: [for (final d in r.days) d.revenue]),
                  ],
                  SectionTitle('Par heure${r.bestHour == null ? '' : ' · pic à ${r.bestHour!.label}'}'),
                  _ChartCard(labels: [for (final h in r.hours.sublist(6)) h.label], values: [for (final h in r.hours.sublist(6)) h.revenue], height: 110),
                  if (r.byMethod.isNotEmpty) ...[
                    const SectionTitle('Encaissements par mode de paiement'),
                    _ShareCard(rows: [for (final e in r.byMethod.entries) (methodLabel(e.key), e.value)]),
                  ],
                  if (r.days.length > 1) ...[
                    const SectionTitle('Détail jour par jour'),
                    Card(
                      child: Column(
                        children: [
                          for (final d in r.days.where((d) => d.orders > 0))
                            ListTile(
                              dense: true,
                              title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${d.orders} vente(s) · ${d.items} article(s)${r.hasCost ? ' · bénéfice ${fcfa(d.profit)}' : ''}'),
                              trailing: Text(fcfa(d.revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                  ],
                  SectionTitle('Articles vendus (${r.products.length})'),
                  for (final (i, p) in r.products.take(30).indexed)
                    FadeSlideIn(
                      key: ValueKey('${p.productId}-${range.start}-${range.end}'),
                      index: i,
                      child: Card(
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 15,
                            backgroundColor: AppColors.gold,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                          ),
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              '${p.quantity} vendu(s)',
                              _pct(r.revenue == 0 ? null : p.revenue * 100 / r.revenue),
                              if (r.hasCost && p.quantityWithoutCost < p.quantity) 'bénéfice ${fcfa(p.profit)}',
                            ].join(' · '),
                          ),
                          trailing: Text(fcfa(p.revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  if (r.products.length > 30)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('… et ${r.products.length - 30} autres : liste complète dans le PDF ou l\'Excel.', style: TextStyle(color: AppColors.muted)),
                    ),
                  if (r.categories.length > 1) ...[
                    const SectionTitle('Par catégorie'),
                    _ShareCard(rows: [for (final c in r.categories) (c.name, c.revenue)]),
                  ],
                  if (r.employees.isNotEmpty) ...[
                    SectionTitle(r.business == BusinessMode.restaurant ? 'Par serveuse / serveur' : 'Par vendeur'),
                    Card(
                      child: Column(
                        children: [
                          for (final e in r.employees)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_outline),
                              title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${e.orders} vente(s) · ${e.items} article(s)'),
                              trailing: Text(fcfa(e.revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SectionTitle('Stock (aujourd\'hui)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    KpiCard(label: 'Valeur au prix d\'achat', value: fcfa(r.stockValueCost), icon: Icons.inventory_2_outlined, color: AppColors.ink),
                    KpiCard(label: 'Valeur au prix de vente', value: fcfa(r.stockValueSale), icon: Icons.sell_outlined, color: AppColors.orange),
                  ],
                ),
                if (r.lowStock.isNotEmpty)
                  Card(
                    color: const Color(0xFFFFF4E6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r.lowStock.length} article(s) à recommander', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(r.lowStock.take(12).map((s) => '${s.name} (${s.qty})').join(' · '), style: TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportBar extends StatelessWidget {
  const _ExportBar({required this.onPdf, required this.onXlsx, required this.onPrint});
  final VoidCallback onPdf, onXlsx, onPrint;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton.tonalIcon(onPressed: onPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF')),
      FilledButton.tonalIcon(onPressed: onXlsx, icon: const Icon(Icons.table_chart), label: const Text('Excel')),
      FilledButton.tonalIcon(onPressed: onPrint, icon: const Icon(Icons.receipt), label: const Text('Ticket')),
    ],
  );
}

/// Barres verticales simples (dessinées à la main : aucune dépendance).
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.labels, required this.values, this.height = 150});
  final List<String> labels;
  final List<int> values;
  final double height;
  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<int>(0, (a, v) => v > a ? v : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('max ${fcfa(maxV)}', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            SizedBox(
              height: height,
              child: CustomPaint(size: Size.infinite, painter: _BarsPainter(values, maxV, AppColors.orange, AppColors.line)),
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, c) {
                final every = (labels.length / (c.maxWidth / 34)).ceil().clamp(1, 1000);
                return Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Text(
                          i % every == 0 ? labels[i] : '',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          softWrap: false,
                          style: TextStyle(fontSize: 9, color: AppColors.muted),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.maxV, this.color, this.grid);
  final List<int> values;
  final int maxV;
  final Color color;
  final Color grid;
  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), g);
    }
    if (values.isEmpty || maxV == 0) return;
    final slot = size.width / values.length;
    final w = (slot * 0.7).clamp(1.5, 26.0);
    final p = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final h = size.height * values[i] / maxV;
      final x = slot * i + (slot - w) / 2;
      canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, w, h), topLeft: const Radius.circular(3), topRight: const Radius.circular(3)), p);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.values != values || old.color != color;
}

/// Répartition (mode de paiement, catégorie) : montant et barre de proportion.
class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.rows});
  final List<(String, int)> rows;
  @override
  Widget build(BuildContext context) {
    final total = rows.fold(0, (a, r) => a + r.$2);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        Text('${fcfa(r.$2)}  ', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(total == 0 ? '' : '${(r.$2 * 100 / total).round()} %', style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: total == 0 ? 0 : r.$2 / total, minHeight: 7, backgroundColor: AppColors.line, color: AppColors.orange),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
