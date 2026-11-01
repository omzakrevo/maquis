// Import / export des produits au format Excel (.xlsx) ou CSV.
// Pur Dart : utilisable et testable sans Flutter.
import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'models.dart';

const productColumns = ['Nom', 'Catégorie', 'Prix (FCFA)', 'Poste (Bar/Cuisine)', 'Suivi stock (Oui/Non)', 'Stock', 'Alerte stock', 'En vente (Oui/Non)', 'Code-barres', 'Prix d\'achat (FCFA)'];

/// Une ligne lue dans le fichier. Les champs null n'étaient pas renseignés
/// (on garde alors la valeur actuelle du produit lors d'une mise à jour).
class ProductRow {
  ProductRow({required this.line, required this.name, this.category, this.price, this.station, this.trackStock, this.stock, this.alertQty, this.active, this.barcode, this.cost});
  final int line;
  final String name;
  final String? category;
  final int? price;
  final Station? station;
  final bool? trackStock;
  final int? stock;
  final int? alertQty;
  final bool? active;
  final String? barcode;
  final int? cost;
}

class ImportIssue {
  ImportIssue(this.line, this.message);
  final int line;
  final String message;
  @override
  String toString() => 'Ligne $line : $message';
}

class ProductFile {
  ProductFile(this.rows, this.issues);
  final List<ProductRow> rows;
  final List<ImportIssue> issues;
}

class ImportResult {
  ImportResult({required this.created, required this.updated, required this.stockAdjusted});
  final int created;
  final int updated;
  final int stockAdjusted;
}

String _yn(bool v) => v ? 'Oui' : 'Non';

/// Fichier Excel des produits (sert aussi de modèle pour l'import).
Uint8List exportProductsXlsx(List<Product> products) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaultName, 'Produits');
  final sheet = excel['Produits'];
  final head = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#FFE8590C'), fontColorHex: ExcelColor.white);
  sheet.appendRow([for (final c in productColumns) TextCellValue(c)]);
  for (var i = 0; i < productColumns.length; i++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = head;
    sheet.setColumnWidth(i, i == 0 ? 28 : (i == 1 ? 18 : 16));
  }
  for (final p in products) {
    sheet.appendRow([
      TextCellValue(p.name),
      TextCellValue(p.category),
      IntCellValue(p.price),
      TextCellValue(p.station == Station.kitchen ? 'Cuisine' : 'Bar'),
      TextCellValue(_yn(p.trackStock)),
      p.trackStock ? IntCellValue(p.stockQty) : null,
      p.trackStock ? IntCellValue(p.alertQty) : null,
      TextCellValue(_yn(p.active)),
      p.barcode == null ? null : TextCellValue(p.barcode!),
      p.cost == null ? null : IntCellValue(p.cost!),
    ]);
  }
  final help = excel['Mode d\'emploi'];
  for (final l in [
    'Import des produits — CAISSE PRO',
    '',
    '• Une ligne par produit. Seules les colonnes « Nom » et « Prix (FCFA) » sont obligatoires pour un nouveau produit.',
    '• Un produit dont le nom existe déjà est MIS À JOUR (prix, catégorie…) ; sinon il est CRÉÉ.',
    '• Catégorie : Bières, Sodas, Eaux, Jus, Plats… (libre). Vide = « Divers » pour un nouveau produit.',
    '• Poste : « Bar » ou « Cuisine » (bon de préparation). Vide = Bar.',
    '• Suivi stock : Oui/Non. Stock : quantité comptée — l\'écart est enregistré comme un inventaire « Import Excel ».',
    '• En vente : Non pour retirer un produit de la caisse sans le supprimer.',
    '• Code-barres : chiffres imprimés sous le code-barres du produit (mode boutique : le produit s\'ajoute au panier quand on le scanne).',
    '• Prix d\'achat : coût unitaire chez le fournisseur (facultatif) ; sert au calcul des marges et bénéfices.',
    '• Les prix sont en FCFA, sans décimales. Un fichier CSV (séparateur ; ou ,) avec les mêmes colonnes est aussi accepté.',
  ]) {
    help.appendRow([TextCellValue(l)]);
  }
  help.setColumnWidth(0, 110);
  excel.setDefaultSheet('Produits');
  return Uint8List.fromList(excel.encode()!);
}

String _norm(String s) {
  const from = 'àâäéèêëîïôöùûüç';
  const to = 'aaaeeeeiioouuuc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Associe chaque colonne du fichier à un champ, d'après son en-tête.
Map<String, int> _mapHeader(List<String> header) {
  final m = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final h = _norm(header[i]);
    if (h.isEmpty) continue;
    String? key;
    if (h.startsWith('nom') || h.contains('produit') || h.contains('designation') || h.contains('article')) {
      key = 'name';
    } else if (h.startsWith('cat')) {
      key = 'category';
    } else if (h.contains('achat') || h.contains('cout') || h.contains('revient') || h.contains('cost')) {
      key = 'cost';
    } else if (h.contains('prix') || h.contains('price') || h.contains('tarif')) {
      key = 'price';
    } else if (h.contains('poste') || h.contains('station')) {
      key = 'station';
    } else if (h.contains('suivi')) {
      key = 'track';
    } else if (h.contains('alerte') || h.contains('seuil')) {
      key = 'alert';
    } else if (h.contains('stock') || h.contains('quantite') || h == 'qte') {
      key = 'stock';
    } else if (h.contains('vente') || h.contains('actif')) {
      key = 'active';
    } else if (h.contains('barre') || h.contains('barcode') || h.contains('ean') || h == 'code' || h.contains('gencod')) {
      key = 'barcode';
    }
    if (key != null) m.putIfAbsent(key, () => i);
  }
  return m;
}

bool? _bool(String v) {
  final n = _norm(v);
  if (n.isEmpty) return null;
  if (['oui', 'o', 'yes', 'y', '1', 'vrai', 'true', 'x'].contains(n)) return true;
  if (['non', 'n', 'no', '0', 'faux', 'false'].contains(n)) return false;
  return null;
}

int? _int(String v) {
  final cleaned = v.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(RegExp(r'(fcfa|cfa|f)$', caseSensitive: false), '');
  if (cleaned.isEmpty) return null;
  final d = double.tryParse(cleaned.replaceAll(',', '.'));
  return d?.round();
}

List<List<String>> _readXlsx(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  // Feuille « Produits » si elle existe, sinon la première non vide.
  final sheets = excel.tables;
  final sheet = sheets['Produits'] ?? sheets.values.firstWhere((s) => s.maxRows > 0, orElse: () => sheets.values.first);
  return [
    for (final row in sheet.rows)
      [
        for (final c in row)
          switch (c?.value) {
            null => '',
            IntCellValue(:final value) => '$value',
            DoubleCellValue(:final value) => value == value.roundToDouble() ? '${value.round()}' : '$value',
            TextCellValue(:final value) => value.toString(),
            BoolCellValue(:final value) => value ? 'Oui' : 'Non',
            final v => v.toString(),
          },
      ],
  ];
}

List<List<String>> _readCsv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return [];
  final sep = lines.first.split(';').length >= lines.first.split(',').length ? ';' : ',';
  List<String> split(String line) {
    final out = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == sep && !quoted) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }

  return lines.map(split).toList();
}

/// Lit un fichier .xlsx ou .csv et vérifie chaque ligne.
ProductFile parseProductsFile(Uint8List bytes, String fileName) {
  final isCsv = fileName.toLowerCase().endsWith('.csv');
  final List<List<String>> table;
  try {
    table = isCsv ? _readCsv(bytes) : _readXlsx(bytes);
  } catch (e) {
    return ProductFile([], [ImportIssue(0, 'Fichier illisible (${isCsv ? 'CSV' : 'Excel .xlsx'} attendu)')]);
  }
  final headerIndex = table.indexWhere((r) => r.any((c) => c.trim().isNotEmpty));
  if (headerIndex < 0) return ProductFile([], [ImportIssue(0, 'Le fichier est vide')]);
  final cols = _mapHeader(table[headerIndex]);
  if (!cols.containsKey('name')) {
    return ProductFile([], [ImportIssue(headerIndex + 1, 'Colonne « Nom » introuvable. Exportez d\'abord vos produits pour obtenir le modèle.')]);
  }
  String cell(List<String> r, String key) {
    final i = cols[key];
    return i == null || i >= r.length ? '' : r[i].trim();
  }

  final rows = <ProductRow>[];
  final issues = <ImportIssue>[];
  final seen = <String>{};
  for (var i = headerIndex + 1; i < table.length; i++) {
    final r = table[i];
    final line = i + 1;
    if (r.every((c) => c.trim().isEmpty)) continue;
    final name = cell(r, 'name');
    if (name.isEmpty) {
      issues.add(ImportIssue(line, 'nom manquant, ligne ignorée'));
      continue;
    }
    final key = _norm(name);
    if (!seen.add(key)) {
      issues.add(ImportIssue(line, '« $name » apparaît plusieurs fois, seule la première ligne est gardée'));
      continue;
    }
    final priceText = cell(r, 'price');
    final price = _int(priceText);
    if (priceText.isNotEmpty && (price == null || price < 0)) {
      issues.add(ImportIssue(line, 'prix invalide « $priceText » pour « $name »'));
      continue;
    }
    final costText = cell(r, 'cost');
    final cost = _int(costText);
    if (costText.isNotEmpty && (cost == null || cost < 0)) {
      issues.add(ImportIssue(line, 'prix d\'achat invalide « $costText » pour « $name »'));
      continue;
    }
    final stockText = cell(r, 'stock');
    final stock = _int(stockText);
    if (stockText.isNotEmpty && stock == null) {
      issues.add(ImportIssue(line, 'stock invalide « $stockText » pour « $name »'));
      continue;
    }
    final stationText = _norm(cell(r, 'station'));
    rows.add(
      ProductRow(
        line: line,
        name: name,
        category: cell(r, 'category').isEmpty ? null : cell(r, 'category'),
        price: price,
        station: stationText.isEmpty ? null : (stationText.startsWith('cui') || stationText.startsWith('kit') ? Station.kitchen : Station.bar),
        trackStock: _bool(cell(r, 'track')) ?? (stock != null ? true : null),
        stock: stock,
        alertQty: _int(cell(r, 'alert')),
        active: _bool(cell(r, 'active')),
        barcode: cell(r, 'barcode').isEmpty ? null : cell(r, 'barcode'),
        cost: costText.isEmpty ? null : cost,
      ),
    );
  }
  return ProductFile(rows, issues);
}

/// Export Excel des ventes par serveuse (paie de fin de mois).
Uint8List exportServerSalesXlsx(List<ServerSales> rows, BonusRules rules, String periodLabel) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaultName, 'Ventes serveuses');
  final sheet = excel['Ventes serveuses'];
  sheet.appendRow([TextCellValue('Ventes par serveuse — $periodLabel')]);
  sheet.appendRow([TextCellValue('Règle de prime : ${rules.perDrink} F par boisson + ${rules.percent} % du chiffre d\'affaires')]);
  sheet.appendRow([]);
  sheet.appendRow([
    for (final c in ['Serveuse', 'Rôle', 'Commandes', 'Articles', 'Boissons', 'Chiffre d\'affaires (F)', 'Encaissé (F)', 'Prime (F)']) TextCellValue(c),
  ]);
  for (final r in rows) {
    sheet.appendRow([
      TextCellValue(r.name),
      TextCellValue(r.role.label),
      IntCellValue(r.orders),
      IntCellValue(r.items),
      IntCellValue(r.drinks),
      IntCellValue(r.revenue),
      IntCellValue(r.collected),
      IntCellValue(rules.bonusFor(r)),
    ]);
  }
  int sum(int Function(ServerSales) f) => rows.fold(0, (a, r) => a + f(r));
  sheet.appendRow([
    TextCellValue('TOTAL'),
    TextCellValue(''),
    IntCellValue(sum((r) => r.orders)),
    IntCellValue(sum((r) => r.items)),
    IntCellValue(sum((r) => r.drinks)),
    IntCellValue(sum((r) => r.revenue)),
    IntCellValue(sum((r) => r.collected)),
    IntCellValue(sum(rules.bonusFor)),
  ]);
  excel.setDefaultSheet('Ventes serveuses');
  return Uint8List.fromList(excel.encode()!);
}

/// Export Excel des marges et bénéfices par produit.
Uint8List exportProfitXlsx(ProfitReport r, String periodLabel) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaultName, 'Marges');
  final sheet = excel['Marges'];
  sheet.appendRow([TextCellValue('Marges et bénéfices — $periodLabel')]);
  sheet.appendRow([TextCellValue('Valeur du stock : ${r.stockValueCost} F au prix d\'achat, ${r.stockValueSale} F au prix de vente')]);
  sheet.appendRow([]);
  sheet.appendRow([
    for (final c in ['Produit', 'Quantité vendue', 'Chiffre d\'affaires (F)', 'Coût d\'achat (F)', 'Bénéfice brut (F)', 'Marge (%)', 'Unités sans prix d\'achat']) TextCellValue(c),
  ]);
  for (final p in r.products) {
    sheet.appendRow([
      TextCellValue(p.name),
      IntCellValue(p.quantity),
      IntCellValue(p.revenue),
      IntCellValue(p.cost),
      IntCellValue(p.profit),
      p.rate == null ? TextCellValue('') : DoubleCellValue(double.parse(p.rate!.toStringAsFixed(1))),
      IntCellValue(p.quantityWithoutCost),
    ]);
  }
  sheet.appendRow([
    TextCellValue('TOTAL'),
    IntCellValue(r.products.fold(0, (a, p) => a + p.quantity)),
    IntCellValue(r.revenue),
    IntCellValue(r.cost),
    IntCellValue(r.profit),
    r.rate == null ? TextCellValue('') : DoubleCellValue(double.parse(r.rate!.toStringAsFixed(1))),
    IntCellValue(r.unitsWithoutCost),
  ]);
  excel.setDefaultSheet('Marges');
  return Uint8List.fromList(excel.encode()!);
}
