// Exports du rapport de ventes : PDF (A4), Excel (plusieurs feuilles) et ticket thermique.
// N'importe pas Flutter : testable et réutilisable.
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../core/money.dart';
import '../printing/pdf_writer.dart';
import '../printing/ticket.dart';
import 'models.dart';

String _d(DateTime d) => '${'${d.day}'.padLeft(2, '0')}/${'${d.month}'.padLeft(2, '0')}/${d.year}';
String _dt(DateTime d) => '${_d(d)} ${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';
String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1).replaceAll('.', ',')} %';

const _months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

/// « Journée du 09/11/2026 », « Novembre 2026 » ou « Du 01/11/2026 au 15/11/2026 » ([to] exclu).
String reportPeriodLabel(DateTime from, DateTime to) {
  final last = to.subtract(const Duration(seconds: 1));
  if (from.year == last.year && from.month == last.month && from.day == last.day) return 'Journée du ${_d(from)}';
  final nextMonth = DateTime(from.year, from.month + 1);
  if (from.day == 1 && to == nextMonth) {
    final m = _months[from.month - 1];
    return '${m[0].toUpperCase()}${m.substring(1)} ${from.year}';
  }
  return 'Du ${_d(from)} au ${_d(last)}';
}

String reportFileName(SalesReport r, String ext) {
  String s(DateTime d) => '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
  final last = r.to.subtract(const Duration(seconds: 1));
  return 'Rapport_ventes_${s(r.from)}${s(last) == s(r.from) ? '' : '_au_${s(last)}'}.$ext';
}

String _businessLabel(BusinessMode m) => switch (m) {
  BusinessMode.restaurant => 'Maquis / Restaurant',
  BusinessMode.shop => 'Boutique',
  BusinessMode.pharmacy => 'Pharmacie',
};

String _sellerTitle(BusinessMode m) => m == BusinessMode.restaurant ? 'Serveur / serveuse' : 'Vendeur';

// ------------------------------------------------------------------ ticket
Ticket salesReportTicket(ShopInfo shop, SalesReport r) {
  final days = r.days.where((d) => d.orders > 0).toList();
  return Ticket('Rapport ${reportPeriodLabel(r.from, r.to)}', [
    TextLine(shop.name, align: TAlign.center, bold: true, big: true),
    if (shop.address.isNotEmpty) TextLine(shop.address, align: TAlign.center),
    Separator(),
    TextLine('RAPPORT DES VENTES', align: TAlign.center, bold: true),
    TextLine(reportPeriodLabel(r.from, r.to), align: TAlign.center, bold: true),
    Separator(),
    PairLine('Nombre de ventes', '${r.orders}', bold: true),
    PairLine('Articles vendus', '${r.items}'),
    PairLine('Panier moyen', fcfa(r.averageBasket)),
    TextLine('CA ${fcfa(r.revenue)}', align: TAlign.right, bold: true, big: true),
    PairLine('Encaissé', fcfa(r.collected)),
    if (r.unpaid > 0) PairLine('Reste à encaisser', fcfa(r.unpaid)),
    if (r.cancelledCount > 0) PairLine('Annulées', '${r.cancelledCount} (${fcfa(r.cancelledTotal)})'),
    if (r.hasCost) ...[PairLine('Bénéfice brut', fcfa(r.profit), bold: true), PairLine('Marge', _pct(r.marginRate))],
    if (r.byMethod.isNotEmpty) ...[Separator(), TextLine('PAR MODE DE PAIEMENT', bold: true), for (final e in r.byMethod.entries) PairLine('  ${methodLabel(e.key)}', fcfa(e.value))],
    if (days.length > 1) ...[Separator(), TextLine('PAR JOUR', bold: true), for (final d in days) PairLine('  ${d.label}  ${d.orders} v.', fcfa(d.revenue))],
    if (r.products.isNotEmpty) ...[Separator(), TextLine('ARTICLES LES PLUS VENDUS', bold: true), for (final p in r.products.take(15)) PairLine('  ${p.quantity} x ${p.name}', fcfa(p.revenue))],
    if (r.categories.length > 1) ...[Separator(), TextLine('PAR CATÉGORIE', bold: true), for (final c in r.categories) PairLine('  ${c.name}', fcfa(c.revenue))],
    if (r.employees.isNotEmpty) ...[
      Separator(),
      TextLine('PAR ${_sellerTitle(r.business).toUpperCase()}', bold: true),
      for (final e in r.employees) PairLine('  ${e.name} (${e.orders})', fcfa(e.revenue)),
    ],
    if (r.lowStock.isNotEmpty) ...[Separator(), TextLine('STOCK À RECOMMANDER', bold: true), for (final s in r.lowStock.take(15)) PairLine('  ${s.name}', '${s.qty}')],
    Feed(),
    TextLine('Imprimé le ${_dt(DateTime.now())}', align: TAlign.center),
  ]);
}

// ------------------------------------------------------------------- Excel
Uint8List salesReportXlsx(ShopInfo shop, SalesReport r) {
  final excel = Excel.createExcel();
  final first = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(first, 'Résumé');
  TextCellValue t(String s) => TextCellValue(s);
  IntCellValue n(int v) => IntCellValue(v);
  CellValue pct(double? v) => v == null ? t('') : DoubleCellValue(double.parse(v.toStringAsFixed(1)));

  final s = excel['Résumé'];
  s.appendRow([t('${shop.name} — Rapport des ventes (${_businessLabel(r.business)})')]);
  s.appendRow([t(reportPeriodLabel(r.from, r.to))]);
  s.appendRow([t('Édité le ${_dt(DateTime.now())}')]);
  s.appendRow([]);
  for (final (label, value) in <(String, CellValue)>[
    ('Nombre de ventes', n(r.orders)),
    ('Articles vendus', n(r.items)),
    ('Chiffre d\'affaires (F)', n(r.revenue)),
    ('Encaissé (F)', n(r.collected)),
    ('Reste à encaisser (F)', n(r.unpaid)),
    ('Panier moyen (F)', n(r.averageBasket)),
    ('Ventes annulées', n(r.cancelledCount)),
    ('Montant annulé (F)', n(r.cancelledTotal)),
    ('Coût d\'achat des ventes (F)', n(r.cost)),
    ('Bénéfice brut (F)', n(r.profit)),
    ('Marge (%)', pct(r.marginRate)),
    ('Jours avec ventes', n(r.activeDays)),
    ('Valeur du stock au prix d\'achat (F)', n(r.stockValueCost)),
    ('Valeur du stock au prix de vente (F)', n(r.stockValueSale)),
  ]) {
    s.appendRow([t(label), value]);
  }
  s.appendRow([]);
  s.appendRow([t('Mode de paiement'), t('Montant (F)')]);
  for (final e in r.byMethod.entries) {
    s.appendRow([t(methodLabel(e.key)), n(e.value)]);
  }

  final dd = excel['Par jour'];
  dd.appendRow([
    for (final c in ['Jour', 'Ventes', 'Articles', 'Chiffre d\'affaires (F)', 'Bénéfice brut (F)']) t(c),
  ]);
  for (final d in r.days) {
    dd.appendRow([t(d.label), n(d.orders), n(d.items), n(d.revenue), n(d.profit)]);
  }
  dd.appendRow([t('TOTAL'), n(r.orders), n(r.items), n(r.revenue), n(r.profit)]);

  final hh = excel['Par heure'];
  hh.appendRow([
    for (final c in ['Heure', 'Ventes', 'Articles', 'Chiffre d\'affaires (F)']) t(c),
  ]);
  for (final h in r.hours.where((h) => h.orders > 0)) {
    hh.appendRow([t(h.label), n(h.orders), n(h.items), n(h.revenue)]);
  }

  final pp = excel['Articles'];
  pp.appendRow([
    for (final c in ['Article', 'Quantité', 'Chiffre d\'affaires (F)', 'Coût d\'achat (F)', 'Bénéfice brut (F)', 'Marge (%)', 'Part du CA (%)']) t(c),
  ]);
  for (final p in r.products) {
    pp.appendRow([t(p.name), n(p.quantity), n(p.revenue), n(p.cost), n(p.profit), pct(p.rate), pct(r.revenue == 0 ? null : p.revenue * 100 / r.revenue)]);
  }

  final cc = excel['Catégories'];
  cc.appendRow([
    for (final c in ['Catégorie', 'Articles', 'Chiffre d\'affaires (F)', 'Part du CA (%)']) t(c),
  ]);
  for (final c in r.categories) {
    cc.appendRow([t(c.name), n(c.items), n(c.revenue), pct(r.revenue == 0 ? null : c.revenue * 100 / r.revenue)]);
  }

  final ee = excel['Vendeurs'];
  ee.appendRow([
    for (final c in [_sellerTitle(r.business), 'Ventes', 'Articles', 'Chiffre d\'affaires (F)']) t(c),
  ]);
  for (final e in r.employees) {
    ee.appendRow([t(e.name), n(e.orders), n(e.items), n(e.revenue)]);
  }

  final st = excel['Stock bas'];
  st.appendRow([
    for (final c in ['Article', 'Stock', 'Seuil d\'alerte']) t(c),
  ]);
  for (final l in r.lowStock) {
    st.appendRow([t(l.name), n(l.qty), n(l.alert)]);
  }
  excel.setDefaultSheet('Résumé');
  return Uint8List.fromList(excel.encode()!);
}

// --------------------------------------------------------------------- PDF
class _Layout {
  _Layout(this.doc, this.accent, this.footer) {
    _newPage();
  }
  final PdfDoc doc;
  final PdfColor accent;
  final String footer;
  static const left = 40.0, right = 555.0, bottom = 800.0;
  double y = 0;

  void _newPage() {
    doc.addPage();
    y = 40;
    doc.text(left, 822, footer, size: 7.5, color: const PdfColor(0.5, 0.5, 0.5));
    doc.text(right, 822, 'Page ${doc.pageCount}', size: 7.5, color: const PdfColor(0.5, 0.5, 0.5), align: PdfAlign.right);
  }

  void need(double h) {
    if (y + h > bottom) _newPage();
  }

  void title(String s) {
    need(40);
    y += 14;
    doc.rect(left, y - 11, 4, 15, accent);
    doc.text(left + 10, y, s, size: 12.5, bold: true, color: accent);
    y += 12;
  }

  /// Tableau : colonnes (largeur, alignement) ; la 1re ligne est l'en-tête.
  void table(List<String> head, List<List<String>> rows, List<double> widths, {Set<int> boldRows = const {}}) {
    const rowH = 15.0;
    void header() {
      need(rowH * 2);
      doc.rect(left, y, right - left, rowH, const PdfColor(0.94, 0.95, 0.96));
      var x = left;
      for (var i = 0; i < head.length; i++) {
        final w = widths[i];
        final s = PdfDoc.fit(head[i], w - 8, 8, bold: true);
        doc.text(i == 0 ? x + 4 : x + w - 4, y + 10.5, s, size: 8, bold: true, align: i == 0 ? PdfAlign.left : PdfAlign.right);
        x += w;
      }
      y += rowH;
    }

    header();
    for (var r = 0; r < rows.length; r++) {
      if (y + rowH > bottom) {
        _newPage();
        header();
      }
      final bold = boldRows.contains(r);
      if (bold) doc.rect(left, y, right - left, rowH, const PdfColor(0.97, 0.97, 0.97));
      var x = left;
      for (var i = 0; i < rows[r].length; i++) {
        final w = widths[i];
        final s = PdfDoc.fit(rows[r][i], w - 8, 8.5, bold: bold);
        doc.text(i == 0 ? x + 4 : x + w - 4, y + 10.5, s, size: 8.5, bold: bold, align: i == 0 ? PdfAlign.left : PdfAlign.right);
        x += w;
      }
      doc.line(left, y + rowH, right, y + rowH, color: const PdfColor(0.9, 0.9, 0.9), width: 0.4);
      y += rowH;
    }
    y += 4;
  }

  /// Graphique en barres verticales (valeurs ≥ 0) avec étiquettes.
  void bars(List<String> labels, List<int> values, {double h = 120}) {
    need(h + 40);
    final maxV = values.fold<int>(0, (a, v) => v > a ? v : a);
    final top = y + 10;
    final base = top + h;
    final n = values.length;
    final slot = (right - left - 40) / n;
    final bw = (slot * 0.7).clamp(2.0, 28.0);
    doc.text(left, top - 2, fcfa(maxV), size: 7, color: const PdfColor(0.5, 0.5, 0.5));
    doc.line(left + 40, base, right, base, color: const PdfColor(0.7, 0.7, 0.7));
    doc.line(left + 40, top, right, top, color: const PdfColor(0.92, 0.92, 0.92), width: 0.4);
    doc.line(left + 40, top + h / 2, right, top + h / 2, color: const PdfColor(0.92, 0.92, 0.92), width: 0.4);
    final every = (n / 16).ceil().clamp(1, 1000);
    for (var i = 0; i < n; i++) {
      final cx = left + 40 + slot * i + slot / 2;
      if (values[i] > 0 && maxV > 0) {
        final bh = h * values[i] / maxV;
        doc.rect(cx - bw / 2, base - bh, bw, bh, accent);
      }
      if (i % every == 0) doc.text(cx, base + 10, labels[i], size: 6.5, color: const PdfColor(0.35, 0.35, 0.35), align: PdfAlign.center);
    }
    y = base + 20;
  }
}

Uint8List salesReportPdf(ShopInfo shop, SalesReport r, {int accentRgb = 0xE85D04}) {
  final accent = PdfColor.hex(accentRgb);
  final doc = PdfDoc();
  final period = reportPeriodLabel(r.from, r.to);
  final l = _Layout(doc, accent, '${shop.name} — Rapport des ventes — $period — édité le ${_dt(DateTime.now())} avec CAISSE PRO');

  // En-tête.
  doc.rect(0, 0, PdfDoc.width, 92, accent);
  doc.text(40, 36, shop.name, size: 20, bold: true, color: const PdfColor(1, 1, 1));
  doc.text(40, 58, 'Rapport des ventes · ${_businessLabel(r.business)}', size: 11, color: const PdfColor(1, 1, 1));
  doc.text(40, 76, period, size: 11, bold: true, color: const PdfColor(1, 1, 1));
  if (shop.address.isNotEmpty || shop.phone.isNotEmpty) {
    doc.text(555, 36, [shop.address, shop.phone].where((s) => s.isNotEmpty).join(' · '), size: 9, color: const PdfColor(1, 1, 1), align: PdfAlign.right);
  }
  l.y = 110;

  // Chiffres clés (cartes 4 × 2).
  final kpis = <(String, String)>[
    ('Chiffre d\'affaires', fcfa(r.revenue)),
    ('Nombre de ventes', '${r.orders}'),
    ('Articles vendus', '${r.items}'),
    ('Panier moyen', fcfa(r.averageBasket)),
    ('Encaissé', fcfa(r.collected)),
    ('Reste à encaisser', fcfa(r.unpaid)),
    (r.hasCost ? 'Bénéfice brut' : 'Annulations', r.hasCost ? fcfa(r.profit) : '${r.cancelledCount}'),
    (r.hasCost ? 'Marge' : 'Montant annulé', r.hasCost ? _pct(r.marginRate) : fcfa(r.cancelledTotal)),
  ];
  const cw = (555.0 - 40 - 3 * 8) / 4;
  for (var i = 0; i < kpis.length; i++) {
    final x = 40 + (i % 4) * (cw + 8);
    final y = l.y + (i ~/ 4) * 52;
    doc.rect(x, y, cw, 44, const PdfColor(0.965, 0.965, 0.97));
    doc.rect(x, y, 3, 44, accent);
    doc.text(x + 10, y + 16, kpis[i].$1, size: 8, color: const PdfColor(0.4, 0.4, 0.4));
    doc.text(x + 10, y + 34, PdfDoc.fit(kpis[i].$2, cw - 14, 13, bold: true), size: 13, bold: true);
  }
  l.y += 116;
  final notes = <String>[
    if (r.cancelledCount > 0 && r.hasCost) '${r.cancelledCount} vente(s) annulée(s) pour ${fcfa(r.cancelledTotal)} (non comptées).',
    if (r.openCount > 0) '${r.openCount} vente(s) encore ouverte(s) : ${fcfa(r.unpaid)} restent à encaisser.',
    if (r.unitsWithoutCost > 0) '${r.unitsWithoutCost} article(s) vendu(s) sans prix d\'achat : bénéfice calculé sur le reste.',
    if (r.bestDay != null && r.activeDays > 1) 'Meilleur jour : ${r.bestDay!.label} (${fcfa(r.bestDay!.revenue)}, ${r.bestDay!.orders} ventes).',
    if (r.bestHour != null) 'Heure la plus active : ${r.bestHour!.label} (${fcfa(r.bestHour!.revenue)}).',
  ];
  for (final n in notes) {
    doc.text(44, l.y, '•  $n', size: 9, color: const PdfColor(0.25, 0.25, 0.25));
    l.y += 13;
  }

  if (r.orders == 0) {
    l.title('Aucune vente sur la période');
  }

  if (r.days.length > 1) {
    l.title('Chiffre d\'affaires par jour');
    l.bars([for (final d in r.days) d.label], [for (final d in r.days) d.revenue]);
  }
  if (r.orders > 0) {
    l.title('Chiffre d\'affaires par heure');
    final hs = r.hours.sublist(r.hours.indexWhere((h) => h.orders > 0), r.hours.lastIndexWhere((h) => h.orders > 0) + 1);
    l.bars([for (final h in hs) h.label], [for (final h in hs) h.revenue], h: 90);
  }

  if (r.byMethod.isNotEmpty) {
    l.title('Encaissements par mode de paiement');
    final tot = r.byMethod.values.fold(0, (a, b) => a + b);
    l.table(
      ['Mode', 'Montant', 'Part'],
      [
        for (final e in r.byMethod.entries) [methodLabel(e.key), fcfa(e.value), _pct(tot == 0 ? null : e.value * 100 / tot)],
        ['Total', fcfa(tot), '100 %'],
      ],
      [275, 140, 100],
      boldRows: {r.byMethod.length},
    );
  }

  if (r.days.length > 1) {
    l.title('Détail jour par jour');
    l.table(
      ['Jour', 'Ventes', 'Articles', 'Chiffre d\'affaires', if (r.hasCost) 'Bénéfice'],
      [
        for (final d in r.days) [d.label, '${d.orders}', '${d.items}', fcfa(d.revenue), if (r.hasCost) fcfa(d.profit)],
        ['Total', '${r.orders}', '${r.items}', fcfa(r.revenue), if (r.hasCost) fcfa(r.profit)],
      ],
      r.hasCost ? [115, 70, 70, 135, 125] : [155, 90, 90, 180],
      boldRows: {r.days.length},
    );
  }

  if (r.products.isNotEmpty) {
    l.title('Articles vendus (${r.products.length})');
    l.table(
      ['Article', 'Qté', 'Chiffre d\'affaires', 'Part', if (r.hasCost) 'Bénéfice', if (r.hasCost) 'Marge'],
      [
        for (final p in r.products) [p.name, '${p.quantity}', fcfa(p.revenue), _pct(r.revenue == 0 ? null : p.revenue * 100 / r.revenue), if (r.hasCost) fcfa(p.profit), if (r.hasCost) _pct(p.rate)],
      ],
      r.hasCost ? [190, 40, 90, 55, 85, 55] : [255, 60, 130, 70],
    );
  }

  if (r.categories.isNotEmpty) {
    l.title('Par catégorie');
    l.table(
      ['Catégorie', 'Articles', 'Chiffre d\'affaires', 'Part'],
      [
        for (final c in r.categories) [c.name, '${c.items}', fcfa(c.revenue), _pct(r.revenue == 0 ? null : c.revenue * 100 / r.revenue)],
      ],
      [215, 80, 140, 80],
    );
  }

  if (r.employees.isNotEmpty) {
    l.title('Par ${_sellerTitle(r.business).toLowerCase()}');
    l.table(
      [_sellerTitle(r.business), 'Ventes', 'Articles', 'Chiffre d\'affaires'],
      [
        for (final e in r.employees) [e.name, '${e.orders}', '${e.items}', fcfa(e.revenue)],
      ],
      [215, 80, 80, 140],
    );
  }

  l.title('Stock');
  l.table(
    ['Indicateur', 'Valeur'],
    [
      ['Valeur du stock au prix d\'achat', fcfa(r.stockValueCost)],
      ['Valeur du stock au prix de vente', fcfa(r.stockValueSale)],
      ['Articles à recommander', '${r.lowStock.length}'],
    ],
    [355, 160],
  );
  if (r.lowStock.isNotEmpty) {
    l.table(
      ['Article à recommander', 'Stock', 'Seuil'],
      [
        for (final s in r.lowStock) [s.name, '${s.qty}', '${s.alert}'],
      ],
      [315, 100, 100],
    );
  }
  return doc.save();
}
