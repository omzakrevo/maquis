// Ouverture de la base SQLite et migrations.
// Ce fichier n'importe que sqflite_common : il pourra être réutilisé tel quel
// par le futur service local Dart (sans Flutter).
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../core/security.dart';

const schemaVersion = 7;
const _uuid = Uuid();

typedef Migration = Future<void> Function(DatabaseExecutor d);

/// Migrations successives. On n'en modifie jamais une déjà publiée :
/// on en ajoute une nouvelle à la fin.
final List<Migration> migrations = [_v1, _v2, _v3, _v4, _v5, _v6, _v7];

Future<Database> openPosDatabase(DatabaseFactory factory, String path) {
  return factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (d, version) async {
        for (final m in migrations) {
          await m(d);
        }
      },
      onUpgrade: (d, oldVersion, newVersion) async {
        for (var v = oldVersion; v < newVersion; v++) {
          await migrations[v](d);
        }
      },
    ),
  );
}

String nowUtc() => DateTime.now().toUtc().toIso8601String();

/// V1 : schéma identique au prototype V0.1 (catalogue de démonstration inclus).
Future<void> _v1(DatabaseExecutor d) async {
  await d.execute('CREATE TABLE products(id TEXT PRIMARY KEY,name TEXT NOT NULL,category TEXT NOT NULL,price_xof INTEGER NOT NULL CHECK(price_xof>=0),active INTEGER NOT NULL DEFAULT 1)');
  await d.execute("CREATE TABLE orders(id TEXT PRIMARY KEY,number TEXT UNIQUE NOT NULL,table_label TEXT,status TEXT NOT NULL DEFAULT 'open',created_at TEXT NOT NULL)");
  await d.execute(
    'CREATE TABLE order_items(id INTEGER PRIMARY KEY AUTOINCREMENT,order_id TEXT NOT NULL REFERENCES orders(id),product_id TEXT NOT NULL REFERENCES products(id),name_snapshot TEXT NOT NULL,price_xof INTEGER NOT NULL,quantity INTEGER NOT NULL CHECK(quantity>0))',
  );
  await d.execute(
    'CREATE TABLE payments(id TEXT PRIMARY KEY,order_id TEXT NOT NULL REFERENCES orders(id),amount_xof INTEGER NOT NULL CHECK(amount_xof>0),method TEXT NOT NULL,idempotency_key TEXT UNIQUE NOT NULL,created_at TEXT NOT NULL)',
  );
  for (final row in <(String, String, int)>[
    ('Brakina', 'Bières', 800),
    ('Beaufort', 'Bières', 800),
    ('Sobbra', 'Bières', 800),
    ('Castel', 'Bières', 1000),
    ('Coca-Cola', 'Sodas', 500),
    ('Youki', 'Sodas', 500),
    ('Eau minérale', 'Eaux', 500),
    ('Bissap', 'Jus', 500),
    ('Riz gras', 'Plats', 1000),
    ('Poulet braisé', 'Plats', 3500),
    ('Poisson braisé', 'Plats', 3000),
    ('Attiéké', 'Plats', 1000),
  ]) {
    await d.insert('products', {'id': _uuid.v4(), 'name': row.$1, 'category': row.$2, 'price_xof': row.$3});
  }
}

/// V2 : utilisateurs/rôles, tables, stocks, avoirs, sessions de caisse,
/// journal d'audit, file de synchronisation, paramètres.
Future<void> _v2(DatabaseExecutor d) async {
  // Produits : stock + poste de préparation.
  await d.execute('ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 0');
  await d.execute('ALTER TABLE products ADD COLUMN stock_qty INTEGER NOT NULL DEFAULT 0');
  await d.execute('ALTER TABLE products ADD COLUMN alert_qty INTEGER NOT NULL DEFAULT 0');
  await d.execute("ALTER TABLE products ADD COLUMN station TEXT NOT NULL DEFAULT 'bar'");
  await d.execute('ALTER TABLE products ADD COLUMN updated_at TEXT');
  await d.execute("UPDATE products SET station='kitchen' WHERE category='Plats'");

  await d.execute('''CREATE TABLE users(
    id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('owner','manager','cashier','server')),
    pin_hash TEXT NOT NULL, pin_salt TEXT NOT NULL, must_change_pin INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1, failed_attempts INTEGER NOT NULL DEFAULT 0, locked_until TEXT,
    created_at TEXT NOT NULL)''');

  await d.execute('CREATE TABLE dining_tables(id TEXT PRIMARY KEY, label TEXT NOT NULL UNIQUE, active INTEGER NOT NULL DEFAULT 1, sort INTEGER NOT NULL DEFAULT 0)');

  // Commandes : traçabilité.
  await d.execute('ALTER TABLE orders ADD COLUMN server_id TEXT REFERENCES users(id)');
  await d.execute('ALTER TABLE orders ADD COLUMN note TEXT');
  await d.execute('ALTER TABLE orders ADD COLUMN closed_at TEXT');
  await d.execute('ALTER TABLE orders ADD COLUMN cancelled_at TEXT');
  await d.execute('ALTER TABLE orders ADD COLUMN cancelled_by TEXT REFERENCES users(id)');
  await d.execute('ALTER TABLE orders ADD COLUMN cancel_reason TEXT');
  await d.execute("ALTER TABLE order_items ADD COLUMN station TEXT NOT NULL DEFAULT 'bar'");
  await d.execute('ALTER TABLE order_items ADD COLUMN added_by TEXT REFERENCES users(id)');
  await d.execute('ALTER TABLE order_items ADD COLUMN added_at TEXT');

  await d.execute('''CREATE TABLE cash_sessions(
    id TEXT PRIMARY KEY, opened_at TEXT NOT NULL, opened_by TEXT NOT NULL REFERENCES users(id),
    opening_float_xof INTEGER NOT NULL CHECK(opening_float_xof>=0),
    closed_at TEXT, closed_by TEXT REFERENCES users(id), expected_cash_xof INTEGER, counted_cash_xof INTEGER,
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','closed')), report_json TEXT)''');
  // Une seule session ouverte à la fois sur ce poste.
  await d.execute("CREATE UNIQUE INDEX idx_one_open_session ON cash_sessions(status) WHERE status='open'");

  // Paiements : détails espèces/mobile money, session, auteur, avoir utilisé.
  await d.execute('ALTER TABLE payments ADD COLUMN reference TEXT');
  await d.execute('ALTER TABLE payments ADD COLUMN received_xof INTEGER');
  await d.execute('ALTER TABLE payments ADD COLUMN change_xof INTEGER');
  await d.execute('ALTER TABLE payments ADD COLUMN user_id TEXT REFERENCES users(id)');
  await d.execute('ALTER TABLE payments ADD COLUMN cash_session_id TEXT REFERENCES cash_sessions(id)');
  await d.execute('ALTER TABLE payments ADD COLUMN credit_id TEXT');

  await d.execute('''CREATE TABLE credits(
    id TEXT PRIMARY KEY, code_hash TEXT NOT NULL UNIQUE, code_hint TEXT NOT NULL,
    initial_xof INTEGER NOT NULL CHECK(initial_xof>0),
    balance_xof INTEGER NOT NULL CHECK(balance_xof>=0 AND balance_xof<=initial_xof),
    status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','exhausted','cancelled')),
    source TEXT NOT NULL CHECK(source IN ('cash_change','manual')),
    customer_name TEXT, reason TEXT, source_order_id TEXT REFERENCES orders(id),
    cash_session_id TEXT REFERENCES cash_sessions(id),
    created_by TEXT REFERENCES users(id), created_at TEXT NOT NULL)''');
  await d.execute('''CREATE TABLE credit_movements(
    id TEXT PRIMARY KEY, credit_id TEXT NOT NULL REFERENCES credits(id),
    kind TEXT NOT NULL CHECK(kind IN ('issue','redeem','cancel')), amount_xof INTEGER NOT NULL CHECK(amount_xof>0),
    order_id TEXT REFERENCES orders(id), cash_session_id TEXT REFERENCES cash_sessions(id),
    user_id TEXT REFERENCES users(id), idempotency_key TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)''');

  await d.execute('''CREATE TABLE stock_movements(
    id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES products(id),
    quantity_delta INTEGER NOT NULL CHECK(quantity_delta<>0), reason TEXT NOT NULL,
    order_id TEXT REFERENCES orders(id), user_id TEXT REFERENCES users(id), created_at TEXT NOT NULL)''');

  await d.execute('''CREATE TABLE audit_logs(
    id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT REFERENCES users(id), action TEXT NOT NULL,
    object_type TEXT NOT NULL, object_id TEXT, details TEXT, created_at TEXT NOT NULL)''');

  await d.execute('''CREATE TABLE sync_outbox(
    id TEXT PRIMARY KEY, seq INTEGER NOT NULL UNIQUE, kind TEXT NOT NULL, payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL, delivered_at TEXT)''');

  await d.execute('CREATE TABLE counters(key TEXT PRIMARY KEY, value INTEGER NOT NULL)');
  await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');

  await d.execute('CREATE INDEX idx_orders_status ON orders(status, created_at)');
  await d.execute('CREATE INDEX idx_payments_order ON payments(order_id)');
  await d.execute('CREATE INDEX idx_payments_session ON payments(cash_session_id)');
  await d.execute('CREATE INDEX idx_items_order ON order_items(order_id)');
  await d.execute('CREATE INDEX idx_stock_product ON stock_movements(product_id, created_at)');
  await d.execute('CREATE INDEX idx_audit_date ON audit_logs(created_at)');

  // Données initiales : compte propriétaire (PIN 0000 à changer), tables, paramètres.
  final salt = randomSalt();
  await d.insert('users', {'id': _uuid.v4(), 'name': 'Propriétaire', 'role': 'owner', 'pin_hash': hashPin('0000', salt), 'pin_salt': salt, 'must_change_pin': 1, 'created_at': nowUtc()});
  for (var i = 1; i <= 8; i++) {
    await d.insert('dining_tables', {'id': _uuid.v4(), 'label': 'Table $i', 'sort': i});
  }
  for (final e in {
    'shop_name': 'Mon établissement',
    'shop_address': '',
    'shop_phone': '',
    'ticket_footer': 'Merci de votre visite !',
    'printer_host': '',
    'printer_port': '9100',
    'paper_width': '58',
    'strip_accents': '1',
    'code_page': '19',
  }.entries) {
    await d.insert('settings', {'key': e.key, 'value': e.value});
  }
}

/// Photos des produits embarquées (licences dans assets/products/CREDITS.md).
const defaultProductImages = {
  'Brakina': 'asset:assets/products/brakina.jpg',
  'Beaufort': 'asset:assets/products/beaufort.jpg',
  'Sobbra': 'asset:assets/products/sobbra.jpg',
  'Castel': 'asset:assets/products/castel.jpg',
  'Coca-Cola': 'asset:assets/products/coca_cola.jpg',
  'Youki': 'asset:assets/products/youki.jpg',
  'Eau minérale': 'asset:assets/products/eau_minerale.jpg',
  'Bissap': 'asset:assets/products/bissap.jpg',
  'Riz gras': 'asset:assets/products/riz_gras.jpg',
  'Poulet braisé': 'asset:assets/products/poulet_braise.jpg',
  'Poisson braisé': 'asset:assets/products/poisson_braise.jpg',
  'Attiéké': 'asset:assets/products/attieke.jpg',
};

/// V3 : photo des produits, imprimante Bluetooth, note sur les mouvements de stock.
Future<void> _v3(DatabaseExecutor d) async {
  await d.execute('ALTER TABLE products ADD COLUMN image TEXT');
  for (final e in defaultProductImages.entries) {
    await d.update('products', {'image': e.value}, where: 'name=? AND image IS NULL', whereArgs: [e.key]);
  }
  await d.execute('ALTER TABLE stock_movements ADD COLUMN note TEXT');
  await d.execute('CREATE INDEX IF NOT EXISTS idx_stock_date ON stock_movements(created_at)');
  // Type d'imprimante : none / network / bluetooth. Une IP déjà saisie reste en réseau.
  final host = await d.query('settings', where: "key='printer_host' AND value<>''");
  for (final e in {'printer_type': host.isEmpty ? 'none' : 'network', 'bt_address': '', 'bt_name': ''}.entries) {
    await d.rawInsert('INSERT OR IGNORE INTO settings(key,value) VALUES(?,?)', [e.key, e.value]);
  }
}

/// V4 : code-barres des produits (mode boutique) et type d'établissement.
Future<void> _v4(DatabaseExecutor d) async {
  await d.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
  // Index partiel (SQLite ≥ 3.8, donc tous les Android ≥ 5) : un code-barres ne peut servir qu'à un produit.
  await d.execute("CREATE UNIQUE INDEX idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL AND barcode<>''");
  await d.rawInsert('INSERT OR IGNORE INTO settings(key,value) VALUES(?,?)', ['business_mode', 'restaurant']);
}

/// V5 : prix d'achat (pharmacies, boutiques) pour calculer marges et bénéfices.
/// Le coût est figé sur chaque ligne vendue et sur chaque entrée de stock.
Future<void> _v5(DatabaseExecutor d) async {
  await d.execute('ALTER TABLE products ADD COLUMN cost_xof INTEGER CHECK(cost_xof IS NULL OR cost_xof>=0)');
  await d.execute('ALTER TABLE order_items ADD COLUMN cost_xof INTEGER');
  await d.execute('ALTER TABLE stock_movements ADD COLUMN unit_cost_xof INTEGER');
}

/// V6 : l'application devient « CAISSE PRO » ; l'ancien nom par défaut de
/// l'établissement n'apparaît plus sur les tickets.
Future<void> _v6(DatabaseExecutor d) async {
  await d.rawUpdate("UPDATE settings SET value='Mon établissement' WHERE key='shop_name' AND value='MAQUIS & RESTO PRO'");
}

/// V7 : catalogue, stock et ventes séparés par type d'établissement
/// (restaurant, shop, pharmacy) ; marquage des produits de démonstration.
Future<void> _v7(DatabaseExecutor d) async {
  final mode = (await d.rawQuery("SELECT value FROM settings WHERE key='business_mode'")).firstOrNull?['value'] as String? ?? 'restaurant';
  await d.execute("ALTER TABLE products ADD COLUMN business TEXT NOT NULL DEFAULT 'restaurant'");
  await d.execute('ALTER TABLE products ADD COLUMN demo INTEGER NOT NULL DEFAULT 0');
  await d.execute("ALTER TABLE orders ADD COLUMN business TEXT NOT NULL DEFAULT 'restaurant'");
  // Les produits livrés avec l'application (photos de boissons et plats) sont des exemples de maquis ;
  // le reste appartient au type d'établissement en cours.
  await d.rawUpdate("UPDATE products SET demo=1, business='restaurant' WHERE image LIKE 'asset:assets/products/%'");
  await d.rawUpdate("UPDATE products SET business=? WHERE demo=0", [mode]);
  await d.rawUpdate("UPDATE orders SET business=?", [mode]);
  await d.execute('CREATE INDEX idx_products_business ON products(business, active)');
  await d.execute('CREATE INDEX idx_orders_business ON orders(business, created_at)');
  // Un même code-barres peut exister dans deux établissements différents.
  await d.execute('DROP INDEX IF EXISTS idx_products_barcode');
  await d.execute("CREATE UNIQUE INDEX idx_products_barcode ON products(business, barcode) WHERE barcode IS NOT NULL AND barcode<>''");
}
