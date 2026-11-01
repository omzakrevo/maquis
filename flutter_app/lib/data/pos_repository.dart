// Toutes les règles métier de la caisse. Chaque écriture :
//  1. vérifie la permission de l'utilisateur qui agit ;
//  2. s'exécute dans une transaction SQLite ;
//  3. écrit une ligne d'audit et un événement dans la file de synchronisation.
// N'importe pas Flutter : réutilisable par le futur service local.
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../core/permissions.dart';
import '../core/security.dart';
import 'database.dart';
import 'models.dart';
import 'product_io.dart';

const _uuid = Uuid();
const maxPinAttempts = 5;
const pinLockDuration = Duration(minutes: 2);

class PosRepository {
  PosRepository(this.db);
  final Database db;

  // ---------------------------------------------------------------- helpers
  void _require(AppUser actor, Permission p) {
    if (!actor.can(p)) {
      throw PermissionDenied("Action non autorisée pour le rôle ${actor.role.label}");
    }
  }

  Future<void> _audit(DatabaseExecutor tx, AppUser? actor, String action, String objectType, String? objectId, [Map<String, Object?>? details]) async {
    await tx.insert('audit_logs', {
      'user_id': actor?.id,
      'action': action,
      'object_type': objectType,
      'object_id': objectId,
      'details': details == null ? null : jsonEncode(details),
      'created_at': nowUtc(),
    });
  }

  Future<void> _outbox(DatabaseExecutor tx, String kind, Map<String, Object?> payload) async {
    final seq = await _nextCounter(tx, 'outbox');
    await tx.insert('sync_outbox', {'id': _uuid.v4(), 'seq': seq, 'kind': kind, 'payload_json': jsonEncode(payload), 'created_at': nowUtc()});
  }

  Future<int> _nextCounter(DatabaseExecutor tx, String key) async {
    // Pas d'« UPSERT » (ON CONFLICT … DO UPDATE) : il exige SQLite 3.24, absent des
    // Android anciens (terminaux POS sous Android 7 à 10).
    await tx.rawInsert('INSERT OR IGNORE INTO counters(key,value) VALUES(?,0)', [key]);
    await tx.rawUpdate('UPDATE counters SET value=value+1 WHERE key=?', [key]);
    final r = await tx.query('counters', columns: ['value'], where: 'key=?', whereArgs: [key]);
    return r.first['value'] as int;
  }

  Future<int> _scalar(DatabaseExecutor tx, String sql, [List<Object?> args = const []]) async {
    final r = await tx.rawQuery(sql, args);
    return (r.first.values.first as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------------------ utilisateurs
  Future<List<AppUser>> users({bool includeInactive = false}) async {
    final rows = await db.query('users', where: includeInactive ? null : 'active=1', orderBy: "CASE role WHEN 'owner' THEN 0 WHEN 'manager' THEN 1 WHEN 'cashier' THEN 2 ELSE 3 END, name");
    return rows.map(AppUser.fromMap).toList();
  }

  /// Vérifie le PIN. Verrouille le compte quelques minutes après
  /// [maxPinAttempts] échecs consécutifs.
  Future<AppUser> login(String userId, String pin) async {
    // Pas d'exception à l'intérieur de la transaction : sinon le compteur
    // d'échecs serait annulé avec elle.
    String? failure;
    final user = await db.transaction<AppUser?>((tx) async {
      final rows = await tx.query('users', where: 'id=? AND active=1', whereArgs: [userId]);
      if (rows.isEmpty) {
        failure = 'Utilisateur introuvable ou désactivé';
        return null;
      }
      final row = rows.first;
      final lockedUntil = row['locked_until'] as String?;
      if (lockedUntil != null && DateTime.parse(lockedUntil).isAfter(DateTime.now().toUtc())) {
        failure = 'Compte bloqué après trop d\'essais. Réessayez dans quelques minutes.';
        return null;
      }
      final ok = hashPin(pin, row['pin_salt'] as String) == row['pin_hash'];
      if (!ok) {
        final attempts = (row['failed_attempts'] as int) + 1;
        await tx.update(
          'users',
          {'failed_attempts': attempts >= maxPinAttempts ? 0 : attempts, 'locked_until': attempts >= maxPinAttempts ? DateTime.now().toUtc().add(pinLockDuration).toIso8601String() : null},
          where: 'id=?',
          whereArgs: [userId],
        );
        await tx.insert('audit_logs', {'user_id': userId, 'action': 'login_failed', 'object_type': 'user', 'object_id': userId, 'created_at': nowUtc()});
        failure = attempts >= maxPinAttempts ? 'PIN incorrect. Compte bloqué 2 minutes.' : 'PIN incorrect (${maxPinAttempts - attempts} essai(s) restant(s))';
        return null;
      }
      await tx.update('users', {'failed_attempts': 0, 'locked_until': null}, where: 'id=?', whereArgs: [userId]);
      final user = AppUser.fromMap(row);
      await _audit(tx, user, 'login', 'user', user.id);
      return user;
    });
    if (user == null) throw BusinessError(failure ?? 'Connexion impossible');
    return user;
  }

  Future<AppUser> createUser(AppUser actor, {required String name, required Role role, required String pin}) async {
    _require(actor, Permission.manageUsers);
    if (name.trim().isEmpty) throw BusinessError('Nom obligatoire');
    if (!isValidPin(pin)) throw BusinessError('Le PIN doit contenir 4 à 6 chiffres');
    if (role == Role.owner && actor.role != Role.owner) throw PermissionDenied('Seul un propriétaire peut créer un propriétaire');
    final id = _uuid.v4();
    final salt = randomSalt();
    await db.transaction((tx) async {
      await tx.insert('users', {'id': id, 'name': name.trim(), 'role': role.name, 'pin_hash': hashPin(pin, salt), 'pin_salt': salt, 'must_change_pin': 1, 'created_at': nowUtc()});
      await _audit(tx, actor, 'user_create', 'user', id, {'name': name.trim(), 'role': role.name});
    });
    return (await users(includeInactive: true)).firstWhere((u) => u.id == id);
  }

  Future<void> updateUser(AppUser actor, String userId, {String? name, Role? role, bool? active}) async {
    _require(actor, Permission.manageUsers);
    await db.transaction((tx) async {
      if (active == false || (role != null && role != Role.owner)) {
        final target = await tx.query('users', where: 'id=?', whereArgs: [userId]);
        if (target.isNotEmpty && target.first['role'] == 'owner') {
          final owners = await _scalar(tx, "SELECT COUNT(*) FROM users WHERE role='owner' AND active=1 AND id<>?", [userId]);
          if (owners == 0) throw BusinessError('Il doit rester au moins un propriétaire actif');
        }
      }
      await tx.update('users', {if (name != null) 'name': name.trim(), if (role != null) 'role': role.name, if (active != null) 'active': active ? 1 : 0}, where: 'id=?', whereArgs: [userId]);
      await _audit(tx, actor, 'user_update', 'user', userId, {'name': name, 'role': role?.name, 'active': active});
    });
  }

  /// Un utilisateur peut changer son propre PIN ; un gestionnaire des
  /// utilisateurs peut réinitialiser celui des autres (changement forcé ensuite).
  Future<void> setPin(AppUser actor, String userId, String newPin) async {
    if (actor.id != userId) _require(actor, Permission.manageUsers);
    if (!isValidPin(newPin)) throw BusinessError('Le PIN doit contenir 4 à 6 chiffres');
    if (newPin == '0000' || newPin == '1234') throw BusinessError('PIN trop simple, choisissez-en un autre');
    final salt = randomSalt();
    await db.transaction((tx) async {
      await tx.update(
        'users',
        {'pin_hash': hashPin(newPin, salt), 'pin_salt': salt, 'must_change_pin': actor.id == userId ? 0 : 1, 'failed_attempts': 0, 'locked_until': null},
        where: 'id=?',
        whereArgs: [userId],
      );
      await _audit(tx, actor, actor.id == userId ? 'pin_change' : 'pin_reset', 'user', userId);
    });
  }

  Future<AppUser> reloadUser(String id) async => AppUser.fromMap((await db.query('users', where: 'id=?', whereArgs: [id])).first);

  // --------------------------------------------------------------- catalogue
  Future<List<Product>> products({bool includeInactive = false}) async {
    final rows = await db.query('products', where: includeInactive ? null : 'active=1', orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE');
    return rows.map(Product.fromMap).toList();
  }

  /// Produit en vente correspondant à un code scanné (code-barres ou QR « PRD:<code> »).
  Future<Product?> productByBarcode(String scanned) async {
    var code = scanned.trim();
    if (code.toUpperCase().startsWith('PRD:')) code = code.substring(4);
    final c = normalizeBarcode(code);
    if (c == null) return null;
    final r = await db.query('products', where: 'barcode=? AND active=1', whereArgs: [c], limit: 1);
    return r.isEmpty ? null : Product.fromMap(r.first);
  }

  /// Marges et bénéfices sur [from, to[ (ventes non annulées), valeur du stock.
  Future<ProfitReport> profitReport(AppUser actor, DateTime from, DateTime to) async {
    _require(actor, Permission.viewReports);
    final rows = await db.rawQuery(
      '''SELECT i.product_id, i.name_snapshot AS name, SUM(i.quantity) AS qty, SUM(i.quantity*i.price_xof) AS revenue,
        SUM(CASE WHEN i.cost_xof IS NULL THEN 0 ELSE i.quantity*i.cost_xof END) AS cost,
        SUM(CASE WHEN i.cost_xof IS NULL THEN i.quantity ELSE 0 END) AS qty_no_cost
      FROM order_items i JOIN orders o ON o.id=i.order_id
      WHERE o.status<>'cancelled' AND o.created_at>=? AND o.created_at<?
      GROUP BY i.product_id, i.name_snapshot''',
      [from.toUtc().toIso8601String(), to.toUtc().toIso8601String()],
    );
    final products =
        rows
            .map(
              (r) => ProductProfit(
                productId: r['product_id'] as String,
                name: r['name'] as String,
                quantity: _int(r['qty']),
                revenue: _int(r['revenue']),
                cost: _int(r['cost']),
                quantityWithoutCost: _int(r['qty_no_cost']),
              ),
            )
            .toList()
          ..sort((a, b) => b.profit.compareTo(a.profit));
    final stock = await db.rawQuery('''SELECT COALESCE(SUM(CASE WHEN stock_qty>0 AND cost_xof IS NOT NULL THEN stock_qty*cost_xof ELSE 0 END),0) AS vc,
        COALESCE(SUM(CASE WHEN stock_qty>0 THEN stock_qty*price_xof ELSE 0 END),0) AS vs
      FROM products WHERE active=1 AND track_stock=1''');
    final missing = await _scalar(db, 'SELECT COUNT(*) FROM products WHERE active=1 AND cost_xof IS NULL');
    return ProfitReport(products: products, stockValueCost: _int(stock.first['vc']), stockValueSale: _int(stock.first['vs']), productsWithoutCost: missing);
  }

  /// Produits de démonstration encore en vente (boissons et plats livrés avec l'application).
  Future<int> demoProductsActive() => _scalar(db, "SELECT COUNT(*) FROM products WHERE active=1 AND image LIKE 'asset:assets/products/%'");

  /// Retire de la vente les produits de démonstration (sans les supprimer : historique conservé).
  Future<int> hideDemoProducts(AppUser actor) async {
    _require(actor, Permission.manageCatalog);
    return db.transaction((tx) async {
      final n = await tx.rawUpdate("UPDATE products SET active=0, updated_at=? WHERE active=1 AND image LIKE 'asset:assets/products/%'", [nowUtc()]);
      await _audit(tx, actor, 'demo_products_hidden', 'product', null, {'count': n});
      return n;
    });
  }

  Future<BusinessMode> businessMode() async => BusinessMode.parse((await settings())['business_mode']);

  Future<List<String>> categories() async {
    final rows = await db.rawQuery('SELECT DISTINCT category FROM products WHERE active=1 ORDER BY category COLLATE NOCASE');
    return rows.map((r) => r['category'] as String).toList();
  }

  /// Crée (id null) ou modifie un produit. Le stock ne se modifie pas ici :
  /// uniquement via [adjustStock] pour garder la traçabilité.
  Future<String> saveProduct(
    AppUser actor, {
    String? id,
    required String name,
    required String category,
    required int price,
    bool trackStock = false,
    int alertQty = 0,
    Station station = Station.bar,
    bool active = true,
    String? image,
    bool clearImage = false,
    String? barcode, // null = inchangé ; '' = retirer
    int? cost, // prix d'achat ; null = inchangé
    bool clearCost = false,
  }) async {
    _require(actor, Permission.manageCatalog);
    final code = normalizeBarcode(barcode);
    if (name.trim().isEmpty || category.trim().isEmpty) throw BusinessError('Nom et catégorie obligatoires');
    if (price < 0) throw BusinessError('Prix invalide');
    if (alertQty < 0) throw BusinessError('Seuil d\'alerte invalide');
    if (cost != null && cost < 0) throw BusinessError('Prix d\'achat invalide');
    final productId = id ?? _uuid.v4();
    final values = {
      'name': name.trim(),
      'category': category.trim(),
      'price_xof': price,
      'track_stock': trackStock ? 1 : 0,
      'alert_qty': alertQty,
      'station': station.name,
      'active': active ? 1 : 0,
      if (image != null || clearImage) 'image': clearImage ? null : image,
      if (barcode != null) 'barcode': code,
      if (cost != null || clearCost) 'cost_xof': clearCost ? null : cost,
      'updated_at': nowUtc(),
    };
    await db.transaction((tx) async {
      if (code != null) {
        final dup = await tx.query('products', columns: ['name'], where: 'barcode=? AND id<>?', whereArgs: [code, productId]);
        if (dup.isNotEmpty) throw BusinessError('Ce code-barres est déjà utilisé par « ${dup.first['name']} »');
      }
      if (id == null) {
        await tx.insert('products', {'id': productId, ...values});
      } else {
        final n = await tx.update('products', values, where: 'id=?', whereArgs: [id]);
        if (n == 0) throw BusinessError('Produit introuvable');
      }
      await _audit(tx, actor, id == null ? 'product_create' : 'product_update', 'product', productId, values);
      await _outbox(tx, 'product.upsert', {'id': productId, ...values});
    });
    return productId;
  }

  /// Import en masse (Excel/CSV) : crée ou met à jour par nom, en une seule
  /// transaction (tout ou rien). Le stock indiqué est traité comme un inventaire.
  Future<ImportResult> importProducts(AppUser actor, List<ProductRow> rows) async {
    _require(actor, Permission.manageCatalog);
    if (rows.isEmpty) throw BusinessError('Aucune ligne à importer');
    return db.transaction((tx) async {
      final existing = {for (final r in await tx.query('products')) (r['name'] as String).trim().toLowerCase(): Product.fromMap(r)};
      var created = 0, updated = 0, stockAdjusted = 0;
      for (final row in rows) {
        final current = existing[row.name.trim().toLowerCase()];
        if (current == null && row.price == null) {
          throw BusinessError('Ligne ${row.line} : prix obligatoire pour le nouveau produit « ${row.name} »');
        }
        final id = current?.id ?? _uuid.v4();
        final track = row.trackStock ?? current?.trackStock ?? false;
        final values = {
          'name': row.name.trim(),
          'category': (row.category ?? current?.category ?? 'Divers').trim(),
          'price_xof': row.price ?? current!.price,
          'track_stock': track ? 1 : 0,
          'alert_qty': row.alertQty ?? current?.alertQty ?? 0,
          'station': (row.station ?? current?.station ?? Station.bar).name,
          'active': (row.active ?? current?.active ?? true) ? 1 : 0,
          'barcode': row.barcode != null ? normalizeBarcode(row.barcode) : current?.barcode,
          'cost_xof': row.cost ?? current?.cost,
          'updated_at': nowUtc(),
        };
        if (current == null) {
          await tx.insert('products', {'id': id, ...values});
          created++;
        } else {
          await tx.update('products', values, where: 'id=?', whereArgs: [id]);
          updated++;
        }
        await _outbox(tx, 'product.upsert', {'id': id, ...values});
        if (track && row.stock != null) {
          final delta = row.stock! - (current?.stockQty ?? 0);
          if (delta != 0) {
            await _moveStock(tx, actor, id, delta, 'Inventaire', null, note: 'Import Excel');
            stockAdjusted++;
          }
        }
      }
      await _audit(tx, actor, 'products_import', 'product', null, {'created': created, 'updated': updated, 'stock_adjusted': stockAdjusted});
      return ImportResult(created: created, updated: updated, stockAdjusted: stockAdjusted);
    });
  }

  // ------------------------------------------------------------------ stocks
  /// Mouvement manuel (livraison, casse, inventaire…). [note] : fournisseur, n° de bon, etc.
  /// [unitCost] (entrées) : prix d'achat unitaire de la livraison ; il devient le prix d'achat du produit.
  Future<void> adjustStock(AppUser actor, String productId, int delta, String reason, {String? note, int? unitCost}) async {
    _require(actor, Permission.manageStock);
    if (delta == 0) throw BusinessError('Quantité nulle');
    if (reason.trim().isEmpty) throw BusinessError('Motif obligatoire');
    if (unitCost != null && (unitCost < 0 || delta < 0)) throw BusinessError('Prix d\'achat invalide');
    final n = note?.trim().isEmpty ?? true ? null : note!.trim();
    await db.transaction((tx) async {
      await _moveStock(tx, actor, productId, delta, reason.trim(), null, note: n, unitCost: unitCost);
      if (unitCost != null) {
        await tx.update('products', {'cost_xof': unitCost, 'updated_at': nowUtc()}, where: 'id=?', whereArgs: [productId]);
      }
      await _audit(tx, actor, 'stock_adjust', 'product', productId, {'delta': delta, 'reason': reason.trim(), 'note': n, 'unit_cost': unitCost});
    });
  }

  Future<void> _moveStock(DatabaseExecutor tx, AppUser actor, String productId, int delta, String reason, String? orderId, {String? note, int? unitCost}) async {
    await tx.rawUpdate('UPDATE products SET stock_qty=stock_qty+? WHERE id=?', [delta, productId]);
    final id = _uuid.v4();
    final at = nowUtc();
    await tx.insert('stock_movements', {
      'id': id,
      'product_id': productId,
      'quantity_delta': delta,
      'reason': reason,
      'order_id': orderId,
      'user_id': actor.id,
      'created_at': at,
      'note': note,
      'unit_cost_xof': unitCost,
    });
    await _outbox(tx, 'stock.move', {'id': id, 'product_id': productId, 'delta': delta, 'reason': reason, 'order_id': orderId, 'note': note, 'at': at});
  }

  /// Historique des mouvements : qui, quand, quoi. Filtres facultatifs.
  Future<List<StockMovement>> stockMovements({String? productId, StockKind? kind, DateTime? from, int limit = 500}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (productId != null) {
      where.add('m.product_id=?');
      args.add(productId);
    }
    if (from != null) {
      where.add('m.created_at>=?');
      args.add(from.toUtc().toIso8601String());
    }
    switch (kind) {
      case StockKind.sale:
        where.add("m.reason='Vente'");
      case StockKind.cancel:
        where.add("m.reason='Annulation commande'");
      case StockKind.count:
        where.add("m.reason='Inventaire'");
      case StockKind.entry:
        where.add("m.quantity_delta>0 AND m.reason NOT IN ('Vente','Annulation commande','Inventaire')");
      case StockKind.exit:
        where.add("m.quantity_delta<0 AND m.reason NOT IN ('Vente','Annulation commande','Inventaire')");
      case null:
        break;
    }
    final rows = await db.rawQuery('''SELECT m.*, p.name AS product_name, p.image AS product_image, u.name AS user_name, o.number AS order_number
      FROM stock_movements m JOIN products p ON p.id=m.product_id LEFT JOIN users u ON u.id=m.user_id LEFT JOIN orders o ON o.id=m.order_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY m.created_at DESC, m.rowid DESC LIMIT $limit''', args);
    return rows.map(StockMovement.fromMap).toList();
  }

  // ------------------------------------------------------------------ tables
  Future<List<DiningTable>> tables({bool includeInactive = false}) async {
    final rows = await db.query('dining_tables', where: includeInactive ? null : 'active=1', orderBy: 'sort, label');
    return rows.map(DiningTable.fromMap).toList();
  }

  Future<void> saveTable(AppUser actor, {String? id, required String label, bool active = true}) async {
    _require(actor, Permission.manageTables);
    if (label.trim().isEmpty) throw BusinessError('Nom de table obligatoire');
    await db.transaction((tx) async {
      final dup = await _scalar(tx, 'SELECT COUNT(*) FROM dining_tables WHERE label=? COLLATE NOCASE AND id<>?', [label.trim(), id ?? '']);
      if (dup > 0) throw BusinessError('Une table porte déjà ce nom');
      if (id == null) {
        final sort = await _scalar(tx, 'SELECT COALESCE(MAX(sort),0)+1 FROM dining_tables');
        await tx.insert('dining_tables', {'id': _uuid.v4(), 'label': label.trim(), 'sort': sort, 'active': active ? 1 : 0});
      } else {
        await tx.update('dining_tables', {'label': label.trim(), 'active': active ? 1 : 0}, where: 'id=?', whereArgs: [id]);
      }
      await _audit(tx, actor, id == null ? 'table_create' : 'table_update', 'table', id, {'label': label.trim(), 'active': active});
    });
  }

  // --------------------------------------------------------------- commandes
  Future<String> _orderNumber(DatabaseExecutor tx) async {
    final now = DateTime.now();
    final day = '${now.year % 100}'.padLeft(2, '0') + '${now.month}'.padLeft(2, '0') + '${now.day}'.padLeft(2, '0');
    final seq = await _nextCounter(tx, 'order:$day');
    return '$day-${'$seq'.padLeft(3, '0')}';
  }

  Future<void> _insertLines(DatabaseExecutor tx, AppUser actor, String orderId, List<CartLine> lines) async {
    final at = nowUtc();
    for (final line in lines) {
      if (line.quantity <= 0) throw BusinessError('Quantité invalide pour ${line.product.name}');
      // Prix et nom relus en base : le panier côté écran peut être périmé.
      final rows = await tx.query('products', where: 'id=? AND active=1', whereArgs: [line.product.id]);
      if (rows.isEmpty) throw BusinessError('${line.product.name} n\'est plus disponible');
      final product = Product.fromMap(rows.first);
      await tx.insert('order_items', {
        'order_id': orderId,
        'product_id': product.id,
        'name_snapshot': product.name,
        'price_xof': product.price,
        'cost_xof': product.cost, // coût figé à la vente
        'quantity': line.quantity,
        'station': product.station.name,
        'added_by': actor.id,
        'added_at': at,
      });
      if (product.trackStock) {
        await _moveStock(tx, actor, product.id, -line.quantity, 'Vente', orderId);
      }
    }
  }

  /// [serverId] : serveuse à qui la commande est attribuée (ventes, primes).
  /// Un serveur ne peut attribuer qu'à lui-même ; la caisse peut choisir.
  Future<String> createOrder(AppUser actor, {required String tableLabel, required List<CartLine> lines, String? note, String? serverId}) async {
    _require(actor, Permission.takeOrders);
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw BusinessError('Commande vide');
    final assigned = serverId ?? actor.id;
    if (assigned != actor.id && !actor.can(Permission.takePayments)) {
      throw PermissionDenied('Un serveur ne peut enregistrer une commande qu\'à son propre nom');
    }
    final id = _uuid.v4();
    return db.transaction((tx) async {
      if (assigned != actor.id) {
        final u = await tx.query('users', columns: ['id'], where: 'id=? AND active=1', whereArgs: [assigned]);
        if (u.isEmpty) throw BusinessError('Serveuse introuvable ou désactivée');
      }
      final number = await _orderNumber(tx);
      await tx.insert('orders', {
        'id': id,
        'number': number,
        'table_label': tableLabel.trim().isEmpty ? 'Comptoir' : tableLabel.trim(),
        'status': 'open',
        'created_at': nowUtc(),
        'server_id': assigned,
        'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      });
      await _insertLines(tx, actor, id, valid);
      await _audit(tx, actor, 'order_create', 'order', id, {'number': number, 'lines': valid.length, if (assigned != actor.id) 'server_id': assigned});
      await _outbox(tx, 'order.create', {
        'id': id,
        'number': number,
        'table': tableLabel,
        'lines': valid.map((l) => {'product_id': l.product.id, 'qty': l.quantity}).toList(),
      });
      return id;
    });
  }

  Future<void> addItems(AppUser actor, String orderId, List<CartLine> lines) async {
    _require(actor, Permission.takeOrders);
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw BusinessError('Aucun article à ajouter');
    await db.transaction((tx) async {
      final o = await tx.query('orders', where: "id=? AND status='open'", whereArgs: [orderId]);
      if (o.isEmpty) throw BusinessError('Commande fermée ou introuvable');
      await _insertLines(tx, actor, orderId, valid);
      await _audit(tx, actor, 'order_add_items', 'order', orderId, {'lines': valid.length});
      await _outbox(tx, 'order.add_items', {
        'id': orderId,
        'lines': valid.map((l) => {'product_id': l.product.id, 'qty': l.quantity}).toList(),
      });
    });
  }

  static const _summarySql = '''SELECT o.id,o.number,o.table_label,o.status,o.created_at,o.note,u.name AS server_name,
    COALESCE((SELECT SUM(i.price_xof*i.quantity) FROM order_items i WHERE i.order_id=o.id),0) AS total,
    COALESCE((SELECT SUM(p.amount_xof) FROM payments p WHERE p.order_id=o.id),0) AS paid
    FROM orders o LEFT JOIN users u ON u.id=o.server_id''';

  Future<List<OrderSummary>> openOrders() async {
    final rows = await db.rawQuery("$_summarySql WHERE o.status='open' ORDER BY o.created_at DESC");
    return rows.map(OrderSummary.fromMap).toList();
  }

  Future<List<OrderSummary>> recentOrders({int limit = 100}) async {
    final rows = await db.rawQuery('$_summarySql ORDER BY o.created_at DESC LIMIT $limit');
    return rows.map(OrderSummary.fromMap).toList();
  }

  Future<OrderDetail> orderDetail(String orderId) async {
    final s = await db.rawQuery('$_summarySql WHERE o.id=?', [orderId]);
    if (s.isEmpty) throw BusinessError('Commande introuvable');
    final items = await db.rawQuery(
      '''SELECT name_snapshot, price_xof, station, SUM(quantity) AS quantity FROM order_items
      WHERE order_id=? GROUP BY product_id, name_snapshot, price_xof, station ORDER BY MIN(id)''',
      [orderId],
    );
    final pays = await db.query('payments', where: 'order_id=?', whereArgs: [orderId], orderBy: 'created_at');
    return OrderDetail(OrderSummary.fromMap(s.first), items.map(OrderItem.fromMap).toList(), pays.map(PaymentRecord.fromMap).toList());
  }

  /// Retrouve une commande à partir d'un QR (`CMD:<id>`), de son identifiant ou de son numéro.
  Future<OrderSummary?> findOrder(String scanned) async {
    var key = scanned.trim();
    if (key.toUpperCase().startsWith('CMD:')) key = key.substring(4).trim();
    if (key.isEmpty) return null;
    final rows = await db.rawQuery('$_summarySql WHERE o.id=? OR o.number=? ORDER BY o.created_at DESC LIMIT 1', [key, key]);
    return rows.isEmpty ? null : OrderSummary.fromMap(rows.first);
  }

  /// Annulation (gérant/propriétaire). Interdite si un paiement existe déjà :
  /// dans ce cas, il faut rembourser par avoir, ce qui garde la caisse juste.
  Future<void> cancelOrder(AppUser actor, String orderId, String reason) async {
    _require(actor, Permission.cancelOrders);
    if (reason.trim().length < 3) throw BusinessError('Indiquez un motif d\'annulation');
    await db.transaction((tx) async {
      final o = await tx.query('orders', where: "id=? AND status='open'", whereArgs: [orderId]);
      if (o.isEmpty) throw BusinessError('Commande fermée ou introuvable');
      final paid = await _scalar(tx, 'SELECT COALESCE(SUM(amount_xof),0) FROM payments WHERE order_id=?', [orderId]);
      if (paid > 0) throw BusinessError('Commande déjà partiellement payée ($paid F) : émettez un avoir au client au lieu d\'annuler.');
      final items = await tx.rawQuery(
        '''SELECT i.product_id, SUM(i.quantity) AS q, p.track_stock FROM order_items i
        JOIN products p ON p.id=i.product_id WHERE i.order_id=? GROUP BY i.product_id''',
        [orderId],
      );
      for (final it in items) {
        if (it['track_stock'] == 1) {
          await _moveStock(tx, actor, it['product_id'] as String, (it['q'] as num).toInt(), 'Annulation commande', orderId);
        }
      }
      await tx.update('orders', {'status': 'cancelled', 'cancelled_at': nowUtc(), 'cancelled_by': actor.id, 'cancel_reason': reason.trim()}, where: 'id=?', whereArgs: [orderId]);
      await _audit(tx, actor, 'order_cancel', 'order', orderId, {'reason': reason.trim()});
      await _outbox(tx, 'order.cancel', {'id': orderId, 'reason': reason.trim()});
    });
  }

  // ------------------------------------------------- ventes par serveuse
  /// Ventes attribuées à chaque serveuse sur la période [from, to[ (heure locale).
  /// Les commandes annulées sont exclues. « Boissons » = articles du poste Bar.
  Future<List<ServerSales>> serverSales(DateTime from, DateTime to) async {
    final f = from.toUtc().toIso8601String();
    final t = to.toUtc().toIso8601String();
    final rows = await db.rawQuery(
      """SELECT u.id, u.name, u.role,
        COUNT(DISTINCT o.id) AS orders,
        COALESCE(SUM(i.quantity),0) AS items,
        COALESCE(SUM(CASE WHEN i.station='bar' THEN i.quantity ELSE 0 END),0) AS drinks,
        COALESCE(SUM(i.quantity*i.price_xof),0) AS revenue
      FROM orders o JOIN users u ON u.id=o.server_id JOIN order_items i ON i.order_id=o.id
      WHERE o.status<>'cancelled' AND o.created_at>=? AND o.created_at<?
      GROUP BY u.id, u.name, u.role ORDER BY revenue DESC""",
      [f, t],
    );
    final paid = await db.rawQuery(
      """SELECT o.server_id AS id, COALESCE(SUM(p.amount_xof),0) AS paid
      FROM orders o JOIN payments p ON p.order_id=o.id
      WHERE o.status<>'cancelled' AND o.created_at>=? AND o.created_at<? GROUP BY o.server_id""",
      [f, t],
    );
    final paidBy = {for (final r in paid) r['id'] as String?: (r['paid'] as num).toInt()};
    return rows
        .map(
          (r) => ServerSales(
            userId: r['id'] as String,
            name: r['name'] as String,
            role: Role.parse(r['role'] as String),
            orders: (r['orders'] as num).toInt(),
            items: (r['items'] as num).toInt(),
            drinks: (r['drinks'] as num).toInt(),
            revenue: (r['revenue'] as num).toInt(),
            collected: paidBy[r['id']] ?? 0,
          ),
        )
        .toList();
  }

  /// Détail des articles vendus par une serveuse sur la période.
  Future<List<ProductSale>> serverProducts(String userId, DateTime from, DateTime to) async {
    final rows = await db.rawQuery(
      """SELECT i.name_snapshot AS name, SUM(i.quantity) AS q, SUM(i.quantity*i.price_xof) AS t
      FROM order_items i JOIN orders o ON o.id=i.order_id
      WHERE o.server_id=? AND o.status<>'cancelled' AND o.created_at>=? AND o.created_at<?
      GROUP BY i.name_snapshot ORDER BY q DESC""",
      [userId, from.toUtc().toIso8601String(), to.toUtc().toIso8601String()],
    );
    return rows.map((r) => ProductSale(r['name'] as String, (r['q'] as num).toInt(), (r['t'] as num).toInt())).toList();
  }

  Future<BonusRules> bonusRules() async {
    final s = await settings();
    return BonusRules(perDrink: int.tryParse(s['bonus_per_drink'] ?? '') ?? 0, percent: double.tryParse((s['bonus_percent'] ?? '').replaceAll(',', '.')) ?? 0);
  }

  Future<void> saveBonusRules(AppUser actor, BonusRules r) async {
    if (r.perDrink < 0 || r.percent < 0 || r.percent > 100) throw BusinessError('Règle de prime invalide');
    await saveSettings(actor, {'bonus_per_drink': '${r.perDrink}', 'bonus_percent': '${r.percent}'});
  }

  // -------------------------------------------------------- sessions caisse
  Future<CashSession?> currentSession() async {
    final r = await db.rawQuery('''SELECT s.*, u.name AS opened_by_name, c.name AS closed_by_name FROM cash_sessions s
      LEFT JOIN users u ON u.id=s.opened_by LEFT JOIN users c ON c.id=s.closed_by WHERE s.status='open' LIMIT 1''');
    return r.isEmpty ? null : CashSession.fromMap(r.first);
  }

  Future<List<CashSession>> sessions({int limit = 60}) async {
    final r = await db.rawQuery('''SELECT s.*, u.name AS opened_by_name, c.name AS closed_by_name FROM cash_sessions s
      LEFT JOIN users u ON u.id=s.opened_by LEFT JOIN users c ON c.id=s.closed_by ORDER BY s.opened_at DESC LIMIT $limit''');
    return r.map(CashSession.fromMap).toList();
  }

  Future<CashSession> openSession(AppUser actor, int openingFloat) async {
    _require(actor, Permission.manageCashSession);
    if (openingFloat < 0) throw BusinessError('Fond de caisse invalide');
    await db.transaction((tx) async {
      final open = await _scalar(tx, "SELECT COUNT(*) FROM cash_sessions WHERE status='open'");
      if (open > 0) throw BusinessError('Une caisse est déjà ouverte');
      final id = _uuid.v4();
      final at = nowUtc();
      await tx.insert('cash_sessions', {'id': id, 'opened_at': at, 'opened_by': actor.id, 'opening_float_xof': openingFloat, 'status': 'open'});
      await _audit(tx, actor, 'cash_open', 'cash_session', id, {'float': openingFloat});
      await _outbox(tx, 'cash.open', {'id': id, 'float': openingFloat, 'at': at});
    });
    return (await currentSession())!;
  }

  Future<ZReport> _buildReport(DatabaseExecutor tx, String sessionId, {int? counted, String? closedBy, String? closedAt}) async {
    final sRows = await tx.rawQuery('SELECT s.*, u.name AS opened_by_name FROM cash_sessions s LEFT JOIN users u ON u.id=s.opened_by WHERE s.id=?', [sessionId]);
    if (sRows.isEmpty) throw BusinessError('Session introuvable');
    final s = sRows.first;
    final from = s['opened_at'] as String;
    final to = closedAt ?? (s['closed_at'] as String?) ?? nowUtc();
    final methods = await tx.rawQuery('SELECT method, SUM(amount_xof) AS t, COUNT(*) AS n FROM payments WHERE cash_session_id=? GROUP BY method', [sessionId]);
    final byMethod = {for (final m in methods) m['method'] as String: (m['t'] as num).toInt()};
    final paymentsCount = methods.fold<int>(0, (a, m) => a + (m['n'] as num).toInt());
    final ordersClosed = await _scalar(tx, "SELECT COUNT(*) FROM orders WHERE status='closed' AND closed_at>=? AND closed_at<=?", [from, to]);
    final cancelled = await tx.rawQuery(
      '''SELECT COUNT(*) AS n, COALESCE(SUM((SELECT SUM(price_xof*quantity) FROM order_items i WHERE i.order_id=o.id)),0) AS t
      FROM orders o WHERE status='cancelled' AND cancelled_at>=? AND cancelled_at<=?''',
      [from, to],
    );
    final open = await tx.rawQuery('''SELECT COUNT(*) AS n, COALESCE(SUM(
        COALESCE((SELECT SUM(price_xof*quantity) FROM order_items i WHERE i.order_id=o.id),0)
      - COALESCE((SELECT SUM(amount_xof) FROM payments p WHERE p.order_id=o.id),0)),0) AS t FROM orders o WHERE status='open' ''');
    final issuedChange = await _scalar(tx, "SELECT COALESCE(SUM(initial_xof),0) FROM credits WHERE cash_session_id=? AND source='cash_change'", [sessionId]);
    final issuedManual = await _scalar(tx, "SELECT COALESCE(SUM(initial_xof),0) FROM credits WHERE source='manual' AND created_at>=? AND created_at<=?", [from, to]);
    final redeemed = byMethod['credit'] ?? 0;
    final top = await tx.rawQuery(
      '''SELECT i.name_snapshot AS name, SUM(i.quantity) AS q, SUM(i.quantity*i.price_xof) AS t
      FROM order_items i JOIN orders o ON o.id=i.order_id
      WHERE o.status<>'cancelled' AND i.added_at>=? AND i.added_at<=? GROUP BY i.name_snapshot ORDER BY t DESC LIMIT 15''',
      [from, to],
    );
    final float = (s['opening_float_xof'] as num).toInt();
    // Espèces attendues = fond + encaissements espèces + monnaie laissée en avoir
    // (le client a donné plus d'espèces, la différence est devenue un avoir).
    final expected = float + (byMethod['cash'] ?? 0) + issuedChange;
    String? closedByName;
    if (closedBy != null) {
      final u = await tx.query('users', columns: ['name'], where: 'id=?', whereArgs: [closedBy]);
      closedByName = u.isEmpty ? null : u.first['name'] as String;
    }
    return ZReport(
      sessionId: sessionId,
      openedAt: DateTime.parse(from).toLocal(),
      closedAt: closedAt == null ? null : DateTime.parse(closedAt).toLocal(),
      openedBy: (s['opened_by_name'] as String?) ?? '?',
      closedBy: closedByName,
      openingFloat: float,
      byMethod: byMethod,
      paymentsCount: paymentsCount,
      ordersClosed: ordersClosed,
      ordersCancelled: (cancelled.first['n'] as num).toInt(),
      cancelledTotal: (cancelled.first['t'] as num).toInt(),
      openOrdersCount: (open.first['n'] as num).toInt(),
      openOrdersBalance: (open.first['t'] as num).toInt(),
      creditsIssuedFromChange: issuedChange,
      creditsIssuedManual: issuedManual,
      creditsRedeemed: redeemed,
      expectedCash: expected,
      countedCash: counted,
      topProducts: top.map((r) => ProductSale(r['name'] as String, (r['q'] as num).toInt(), (r['t'] as num).toInt())).toList(),
    );
  }

  /// Rapport X : situation de la session en cours, sans la fermer.
  Future<ZReport> currentReport() async {
    final s = await currentSession();
    if (s == null) throw BusinessError('Aucune caisse ouverte');
    return db.transaction((tx) => _buildReport(tx, s.id));
  }

  /// Rapport Z : ferme la session, fige le rapport.
  Future<ZReport> closeSession(AppUser actor, int countedCash) async {
    _require(actor, Permission.manageCashSession);
    if (countedCash < 0) throw BusinessError('Montant compté invalide');
    return db.transaction((tx) async {
      final s = await tx.query('cash_sessions', where: "status='open'");
      if (s.isEmpty) throw BusinessError('Aucune caisse ouverte');
      final id = s.first['id'] as String;
      final at = nowUtc();
      final report = await _buildReport(tx, id, counted: countedCash, closedBy: actor.id, closedAt: at);
      await tx.update(
        'cash_sessions',
        {'status': 'closed', 'closed_at': at, 'closed_by': actor.id, 'expected_cash_xof': report.expectedCash, 'counted_cash_xof': countedCash, 'report_json': jsonEncode(report.toJson())},
        where: 'id=?',
        whereArgs: [id],
      );
      await _audit(tx, actor, 'cash_close', 'cash_session', id, {'expected': report.expectedCash, 'counted': countedCash, 'difference': report.difference});
      await _outbox(tx, 'cash.close', report.toJson());
      return report;
    });
  }

  ZReport? storedReport(CashSession s) => s.reportJson == null ? null : ZReport.fromJson(jsonDecode(s.reportJson!) as Map<String, dynamic>);

  // -------------------------------------------------------------- paiements
  Future<PaymentResult> pay(AppUser actor, PaymentRequest req) async {
    _require(actor, Permission.takePayments);
    if (req.amount <= 0) throw BusinessError('Montant invalide');
    if (!paymentMethodLabels.containsKey(req.method)) throw BusinessError('Mode de paiement inconnu');
    return db.transaction((tx) async {
      // Idempotence : un double appui sur « Valider » ne crée pas deux paiements.
      final dup = await tx.query('payments', where: 'idempotency_key=?', whereArgs: [req.idempotencyKey]);
      if (dup.isNotEmpty) {
        final status = await tx.query('orders', columns: ['status'], where: 'id=?', whereArgs: [req.orderId]);
        return PaymentResult(orderClosed: status.first['status'] == 'closed', change: (dup.first['change_xof'] as int?) ?? 0, duplicate: true);
      }
      final session = await tx.query('cash_sessions', where: "status='open'");
      if (session.isEmpty) throw BusinessError('Ouvrez la caisse avant d\'encaisser');
      final sessionId = session.first['id'] as String;
      final o = await tx.query('orders', where: "id=? AND status='open'", whereArgs: [req.orderId]);
      if (o.isEmpty) throw BusinessError('Commande fermée ou introuvable');
      final total = await _scalar(tx, 'SELECT COALESCE(SUM(price_xof*quantity),0) FROM order_items WHERE order_id=?', [req.orderId]);
      final paid = await _scalar(tx, 'SELECT COALESCE(SUM(amount_xof),0) FROM payments WHERE order_id=?', [req.orderId]);
      final balance = total - paid;
      if (req.amount > balance) throw BusinessError('Montant supérieur au reste à payer ($balance F)');

      int change = 0;
      String? creditId;
      String? issuedCode;
      int issuedAmount = 0;
      String? reference = req.reference?.trim().isEmpty ?? true ? null : req.reference!.trim();

      switch (req.method) {
        case 'cash':
          final received = req.receivedCash ?? req.amount;
          if (received < req.amount) throw BusinessError('Montant reçu inférieur au montant à encaisser');
          change = received - req.amount;
          break;
        case 'mobile_money':
          if (reference == null) throw BusinessError('Saisissez la référence de la transaction Mobile Money');
          break;
        case 'credit':
          if (req.creditCode == null) throw BusinessError('Code d\'avoir manquant');
          final c = await tx.query('credits', where: 'code_hash=?', whereArgs: [hashCreditCode(req.creditCode!)]);
          if (c.isEmpty) throw BusinessError('Code d\'avoir inconnu');
          final credit = Credit.fromMap(c.first);
          if (credit.status != 'active' || credit.balance <= 0) throw BusinessError('Avoir épuisé ou annulé');
          if (req.amount > credit.balance) throw BusinessError('Solde de l\'avoir insuffisant (${credit.balance} F)');
          creditId = credit.id;
          reference = 'Avoir …${credit.codeHint}';
          final newBalance = credit.balance - req.amount;
          // Mise à jour conditionnelle : protège contre une double utilisation.
          final n = await tx.rawUpdate("UPDATE credits SET balance_xof=?, status=? WHERE id=? AND balance_xof=? AND status='active'", [
            newBalance,
            newBalance == 0 ? 'exhausted' : 'active',
            credit.id,
            credit.balance,
          ]);
          if (n != 1) throw BusinessError('Avoir modifié entre-temps, réessayez');
          await tx.insert('credit_movements', {
            'id': _uuid.v4(),
            'credit_id': credit.id,
            'kind': 'redeem',
            'amount_xof': req.amount,
            'order_id': req.orderId,
            'cash_session_id': sessionId,
            'user_id': actor.id,
            'idempotency_key': 'redeem:${req.idempotencyKey}',
            'created_at': nowUtc(),
          });
          break;
      }

      final paymentId = _uuid.v4();
      final at = nowUtc();
      await tx.insert('payments', {
        'id': paymentId,
        'order_id': req.orderId,
        'amount_xof': req.amount,
        'method': req.method,
        'idempotency_key': req.idempotencyKey,
        'created_at': at,
        'reference': reference,
        'received_xof': req.method == 'cash' ? (req.receivedCash ?? req.amount) : null,
        'change_xof': req.method == 'cash' ? (req.changeAsCredit ? 0 : change) : null, // monnaie réellement rendue en espèces
        'user_id': actor.id,
        'cash_session_id': sessionId,
        'credit_id': creditId,
      });

      if (req.method == 'cash' && change > 0 && req.changeAsCredit) {
        final issued = await _issueCredit(
          tx,
          actor,
          amount: change,
          source: 'cash_change',
          sourceOrderId: req.orderId,
          sessionId: sessionId,
          reason: 'Monnaie non rendue',
          idempotencyKey: 'change:${req.idempotencyKey}',
        );
        issuedCode = issued.code;
        issuedAmount = change;
        change = 0;
      }

      final closed = req.amount == balance;
      if (closed) {
        await tx.update('orders', {'status': 'closed', 'closed_at': at}, where: 'id=?', whereArgs: [req.orderId]);
      }
      await _audit(tx, actor, 'payment', 'order', req.orderId, {'amount': req.amount, 'method': req.method, 'change': change, 'credit_issued': issuedAmount});
      await _outbox(tx, 'payment.create', {'id': paymentId, 'order_id': req.orderId, 'amount': req.amount, 'method': req.method, 'session_id': sessionId, 'at': at});
      return PaymentResult(orderClosed: closed, change: change, issuedCreditCode: issuedCode, issuedCreditAmount: issuedAmount);
    });
  }

  // ------------------------------------------------------------------ avoirs
  Future<IssuedCredit> _issueCredit(
    DatabaseExecutor tx,
    AppUser actor, {
    required int amount,
    required String source,
    String? sourceOrderId,
    String? sessionId,
    String? customerName,
    String? reason,
    required String idempotencyKey,
  }) async {
    if (amount <= 0) throw BusinessError('Montant d\'avoir invalide');
    String code;
    String hash;
    // Collision quasi impossible (31^8), mais on vérifie quand même.
    do {
      code = generateCreditCode();
      hash = hashCreditCode(code);
    } while ((await tx.query('credits', columns: ['id'], where: 'code_hash=?', whereArgs: [hash])).isNotEmpty);
    final id = _uuid.v4();
    final at = nowUtc();
    final hint = normalizeCreditCode(code).substring(6);
    await tx.insert('credits', {
      'id': id,
      'code_hash': hash,
      'code_hint': hint,
      'initial_xof': amount,
      'balance_xof': amount,
      'status': 'active',
      'source': source,
      'customer_name': customerName?.trim().isEmpty ?? true ? null : customerName!.trim(),
      'reason': reason,
      'source_order_id': sourceOrderId,
      'cash_session_id': sessionId,
      'created_by': actor.id,
      'created_at': at,
    });
    await tx.insert('credit_movements', {
      'id': _uuid.v4(),
      'credit_id': id,
      'kind': 'issue',
      'amount_xof': amount,
      'order_id': sourceOrderId,
      'cash_session_id': sessionId,
      'user_id': actor.id,
      'idempotency_key': idempotencyKey,
      'created_at': at,
    });
    await _audit(tx, actor, 'credit_issue', 'credit', id, {'amount': amount, 'source': source, 'hint': hint});
    await _outbox(tx, 'credit.issue', {'id': id, 'amount': amount, 'source': source, 'at': at});
    final row = (await tx.query('credits', where: 'id=?', whereArgs: [id])).first;
    return IssuedCredit(Credit.fromMap(row), code);
  }

  /// Avoir émis manuellement (geste commercial, plat indisponible déjà payé…).
  Future<IssuedCredit> issueCredit(AppUser actor, {required int amount, String? customerName, required String reason, String? idempotencyKey}) async {
    _require(actor, Permission.issueCredits);
    if (reason.trim().length < 3) throw BusinessError('Indiquez le motif de l\'avoir');
    return db.transaction((tx) => _issueCredit(tx, actor, amount: amount, source: 'manual', customerName: customerName, reason: reason.trim(), idempotencyKey: idempotencyKey ?? _uuid.v4()));
  }

  Future<Credit?> creditByCode(String code) async {
    final r = await db.query('credits', where: 'code_hash=?', whereArgs: [hashCreditCode(code)]);
    return r.isEmpty ? null : Credit.fromMap(r.first);
  }

  Future<List<Credit>> credits({bool activeOnly = false}) async {
    final r = await db.query('credits', where: activeOnly ? "status='active'" : null, orderBy: 'created_at DESC', limit: 200);
    return r.map(Credit.fromMap).toList();
  }

  Future<void> cancelCredit(AppUser actor, String creditId, String reason) async {
    _require(actor, Permission.issueCredits);
    if (reason.trim().length < 3) throw BusinessError('Indiquez un motif');
    await db.transaction((tx) async {
      final c = await tx.query('credits', where: "id=? AND status='active'", whereArgs: [creditId]);
      if (c.isEmpty) throw BusinessError('Avoir déjà épuisé ou annulé');
      final balance = c.first['balance_xof'] as int;
      await tx.update('credits', {'status': 'cancelled', 'balance_xof': 0}, where: 'id=?', whereArgs: [creditId]);
      await tx.insert('credit_movements', {
        'id': _uuid.v4(),
        'credit_id': creditId,
        'kind': 'cancel',
        'amount_xof': balance,
        'user_id': actor.id,
        'idempotency_key': 'cancel:$creditId',
        'created_at': nowUtc(),
      });
      await _audit(tx, actor, 'credit_cancel', 'credit', creditId, {'balance': balance, 'reason': reason.trim()});
      await _outbox(tx, 'credit.cancel', {'id': creditId});
    });
  }

  // ------------------------------------------------------------ audit/divers
  Future<List<AuditEntry>> auditLog({int limit = 300}) async {
    final r = await db.rawQuery('SELECT a.*, u.name AS user_name FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id ORDER BY a.id DESC LIMIT $limit');
    return r.map(AuditEntry.fromMap).toList();
  }

  Future<int> pendingSyncEvents() => _scalar(db, 'SELECT COUNT(*) FROM sync_outbox WHERE delivered_at IS NULL');

  Future<Map<String, String>> settings() async {
    final r = await db.query('settings');
    return {for (final e in r) e['key'] as String: e['value'] as String};
  }

  Future<void> saveSettings(AppUser actor, Map<String, String> values) async {
    _require(actor, Permission.manageSettings);
    await db.transaction((tx) async {
      for (final e in values.entries) {
        await tx.rawInsert('INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)', [e.key, e.value]);
      }
      await _audit(tx, actor, 'settings_update', 'settings', null, values);
    });
  }

  Future<ShopInfo> shopInfo() async {
    final s = await settings();
    return ShopInfo(name: s['shop_name'] ?? 'Mon établissement', address: s['shop_address'] ?? '', phone: s['shop_phone'] ?? '', footer: s['ticket_footer'] ?? '');
  }

  Future<PrinterSettings> printerSettings() async {
    final s = await settings();
    return PrinterSettings(
      type: PrinterType.values.firstWhere((t) => t.name == s['printer_type'], orElse: () => (s['printer_host'] ?? '').isEmpty ? PrinterType.none : PrinterType.network),
      btAddress: s['bt_address'] ?? '',
      btName: s['bt_name'] ?? '',
      host: s['printer_host'] ?? '',
      port: int.tryParse(s['printer_port'] ?? '') ?? 9100,
      paperWidth: int.tryParse(s['paper_width'] ?? '') ?? 58,
      stripAccents: (s['strip_accents'] ?? '1') == '1',
      codePage: int.tryParse(s['code_page'] ?? '') ?? 19,
      qrAsImage: (s['qr_image'] ?? '1') == '1',
      afterOrder: AfterOrderPrint.values.firstWhere((v) => v.name == s['print_after_order'], orElse: () => AfterOrderPrint.client),
    );
  }
}

/// Nettoie un code-barres saisi ou scanné (espaces, retour chariot de la douchette).
String? normalizeBarcode(String? v) {
  if (v == null) return null;
  final c = v.replaceAll(RegExp(r'[\s\u0000-\u001f]'), '');
  return c.isEmpty ? null : c;
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
