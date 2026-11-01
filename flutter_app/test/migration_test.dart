import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maquis_resto_pro/data/database.dart';
import 'package:maquis_resto_pro/data/models.dart';
import 'package:maquis_resto_pro/data/pos_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('une base V0.1 existante est migrée sans perte et reste utilisable', () async {
    final dir = await Directory.systemTemp.createTemp('maquis_mig');
    final path = p.join(dir.path, 'maquis_resto_v1.db');

    // 1. Base créée par la V0.1 (schéma v1) avec une commande partiellement payée.
    final v1 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (d, _) => migrations[0](d)));
    final productId = (await v1.query('products', where: "name='Castel'")).first['id'] as String;
    await v1.insert('orders', {'id': 'o1', 'number': 'CMD-123', 'table_label': 'Table 4', 'status': 'open', 'created_at': DateTime.now().toUtc().toIso8601String()});
    await v1.insert('order_items', {'order_id': 'o1', 'product_id': productId, 'name_snapshot': 'Castel', 'price_xof': 1000, 'quantity': 3});
    await v1.insert('payments', {'id': 'p1', 'order_id': 'o1', 'amount_xof': 1000, 'method': 'cash', 'idempotency_key': 'k1', 'created_at': DateTime.now().toUtc().toIso8601String()});
    await v1.close();

    // 2. Ouverture par la V0.2.
    final db = await openPosDatabase(databaseFactoryFfi, path);
    expect(await db.getVersion(), schemaVersion);
    final repo = PosRepository(db);
    final open = await repo.openOrders();
    expect(open.single.number, 'CMD-123');
    expect(open.single.balance, 2000);
    expect((await repo.products()).firstWhere((x) => x.name == 'Poulet braisé').station, Station.kitchen);
    expect((await repo.products()).firstWhere((x) => x.name == 'Castel').image, 'asset:assets/products/castel.jpg');

    // 3. On peut solder l'ancienne commande avec le nouveau flux.
    final owner = await repo.login((await repo.users()).single.id, '0000');
    await repo.openSession(owner, 0);
    final r = await repo.pay(owner, PaymentRequest(orderId: 'o1', amount: 2000, method: 'cash', idempotencyKey: 'k2'));
    expect(r.orderClosed, isTrue);
    await db.close();
    await dir.delete(recursive: true);
  });
}
