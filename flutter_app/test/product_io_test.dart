import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maquis_resto_pro/core/permissions.dart';
import 'package:maquis_resto_pro/data/database.dart';
import 'package:maquis_resto_pro/data/models.dart';
import 'package:maquis_resto_pro/data/pos_repository.dart';
import 'package:maquis_resto_pro/data/product_io.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('export Excel puis relecture : mêmes produits', () {
    final products = [
      Product(id: '1', name: 'Brakina', category: 'Bières', price: 800, trackStock: true, stockQty: 24, alertQty: 6, barcode: '0611234567890', cost: 550),
      Product(id: '2', name: 'Poulet braisé', category: 'Plats', price: 3500, station: Station.kitchen),
      Product(id: '3', name: 'Ancien', category: 'Divers', price: 100, active: false),
    ];
    final bytes = exportProductsXlsx(products);
    expect(bytes.sublist(0, 2), [0x50, 0x4B]); // archive zip (.xlsx)
    final f = parseProductsFile(bytes, 'produits.xlsx');
    expect(f.issues, isEmpty);
    expect(f.rows.map((r) => r.name), ['Brakina', 'Poulet braisé', 'Ancien']);
    expect(f.rows[0].price, 800);
    expect(f.rows[0].trackStock, isTrue);
    expect(f.rows[0].stock, 24);
    expect(f.rows[1].station, Station.kitchen);
    expect(f.rows[2].active, isFalse);
    expect(f.rows[0].barcode, '0611234567890'); // zéro initial conservé
    expect(f.rows[1].barcode, isNull);
    expect(f.rows[0].cost, 550);
    expect(f.rows[0].price, 800); // « Prix d'achat » ne doit pas être pris pour le prix de vente
    expect(f.rows[1].cost, isNull);
  });

  test('CSV avec point-virgule, en-têtes approximatifs, erreurs signalées', () {
    const csv =
        'Désignation;Catégorie;Prix;Poste;Stock\n'
        'Castel;Bières;1 000 F;Bar;12\n'
        'Riz gras;Plats;1000;Cuisine;\n'
        ';Bières;500;;\n'
        'Fanta;Sodas;abc;;\n'
        'Castel;Bières;1100;;\n';
    final f = parseProductsFile(Uint8List.fromList(utf8.encode(csv)), 'p.csv');
    expect(f.rows.map((r) => r.name), ['Castel', 'Riz gras']);
    expect(f.rows.first.price, 1000);
    expect(f.rows.first.stock, 12);
    expect(f.rows.first.trackStock, isTrue);
    expect(f.rows[1].station, Station.kitchen);
    expect(f.issues.length, 3); // nom manquant, prix invalide, doublon
  });

  test('fichier sans colonne Nom refusé', () {
    final f = parseProductsFile(Uint8List.fromList(utf8.encode('a;b\n1;2\n')), 'x.csv');
    expect(f.rows, isEmpty);
    expect(f.issues.single.message, contains('Nom'));
  });

  test('import en base : création, mise à jour, inventaire « Import Excel »', () async {
    final repo = PosRepository(await openPosDatabase(databaseFactoryFfi, inMemoryDatabasePath));
    final owner = await repo.login((await repo.users()).single.id, '0000');
    final r = await repo.importProducts(owner, [
      ProductRow(line: 2, name: 'brakina', price: 900, trackStock: true, stock: 30), // existe (casse différente)
      ProductRow(line: 3, name: 'Fanta', category: 'Sodas', price: 600),
    ]);
    expect(r.created, 1);
    expect(r.updated, 1);
    expect(r.stockAdjusted, 1);
    final all = {for (final p in await repo.products()) p.name: p};
    expect(all['brakina']!.price, 900);
    expect(all['brakina']!.category, 'Bières'); // catégorie conservée
    expect(all['brakina']!.stockQty, 30);
    expect(all['Fanta']!.category, 'Sodas');
    final moves = await repo.stockMovements(kind: StockKind.count);
    expect(moves.single.note, 'Import Excel');
    await expectLater(repo.importProducts(owner, [ProductRow(line: 2, name: 'Nouveau sans prix')]), throwsA(isA<BusinessError>()));
    final server = await repo.createUser(owner, name: 'Awa', role: Role.server, pin: '1357');
    await expectLater(repo.importProducts(await repo.login(server.id, '1357'), [ProductRow(line: 2, name: 'X', price: 1)]), throwsA(isA<PermissionDenied>()));
    await repo.db.close();
  });
}
