-- MAQUIS & RESTO PRO — schéma SQLite local, version 3 (V0.3)
-- Référence générée depuis lib/data/database.dart (la source de vérité ce sont les migrations).
PRAGMA foreign_keys=ON;

CREATE TABLE products(id TEXT PRIMARY KEY,name TEXT NOT NULL,category TEXT NOT NULL,price_xof INTEGER NOT NULL CHECK(price_xof>=0),active INTEGER NOT NULL DEFAULT 1, track_stock INTEGER NOT NULL DEFAULT 0, stock_qty INTEGER NOT NULL DEFAULT 0, alert_qty INTEGER NOT NULL DEFAULT 0, station TEXT NOT NULL DEFAULT 'bar', updated_at TEXT, image TEXT);

CREATE TABLE orders(id TEXT PRIMARY KEY,number TEXT UNIQUE NOT NULL,table_label TEXT,status TEXT NOT NULL DEFAULT 'open',created_at TEXT NOT NULL, server_id TEXT REFERENCES users(id), note TEXT, closed_at TEXT, cancelled_at TEXT, cancelled_by TEXT REFERENCES users(id), cancel_reason TEXT);

CREATE TABLE order_items(id INTEGER PRIMARY KEY AUTOINCREMENT,order_id TEXT NOT NULL REFERENCES orders(id),product_id TEXT NOT NULL REFERENCES products(id),name_snapshot TEXT NOT NULL,price_xof INTEGER NOT NULL,quantity INTEGER NOT NULL CHECK(quantity>0), station TEXT NOT NULL DEFAULT 'bar', added_by TEXT REFERENCES users(id), added_at TEXT);

CREATE TABLE payments(id TEXT PRIMARY KEY,order_id TEXT NOT NULL REFERENCES orders(id),amount_xof INTEGER NOT NULL CHECK(amount_xof>0),method TEXT NOT NULL,idempotency_key TEXT UNIQUE NOT NULL,created_at TEXT NOT NULL, reference TEXT, received_xof INTEGER, change_xof INTEGER, user_id TEXT REFERENCES users(id), cash_session_id TEXT REFERENCES cash_sessions(id), credit_id TEXT);

CREATE TABLE users(
    id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('owner','manager','cashier','server')),
    pin_hash TEXT NOT NULL, pin_salt TEXT NOT NULL, must_change_pin INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1, failed_attempts INTEGER NOT NULL DEFAULT 0, locked_until TEXT,
    created_at TEXT NOT NULL);

CREATE TABLE dining_tables(id TEXT PRIMARY KEY, label TEXT NOT NULL UNIQUE, active INTEGER NOT NULL DEFAULT 1, sort INTEGER NOT NULL DEFAULT 0);

CREATE TABLE cash_sessions(
    id TEXT PRIMARY KEY, opened_at TEXT NOT NULL, opened_by TEXT NOT NULL REFERENCES users(id),
    opening_float_xof INTEGER NOT NULL CHECK(opening_float_xof>=0),
    closed_at TEXT, closed_by TEXT REFERENCES users(id), expected_cash_xof INTEGER, counted_cash_xof INTEGER,
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','closed')), report_json TEXT);

CREATE TABLE credits(
    id TEXT PRIMARY KEY, code_hash TEXT NOT NULL UNIQUE, code_hint TEXT NOT NULL,
    initial_xof INTEGER NOT NULL CHECK(initial_xof>0),
    balance_xof INTEGER NOT NULL CHECK(balance_xof>=0 AND balance_xof<=initial_xof),
    status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','exhausted','cancelled')),
    source TEXT NOT NULL CHECK(source IN ('cash_change','manual')),
    customer_name TEXT, reason TEXT, source_order_id TEXT REFERENCES orders(id),
    cash_session_id TEXT REFERENCES cash_sessions(id),
    created_by TEXT REFERENCES users(id), created_at TEXT NOT NULL);

CREATE TABLE credit_movements(
    id TEXT PRIMARY KEY, credit_id TEXT NOT NULL REFERENCES credits(id),
    kind TEXT NOT NULL CHECK(kind IN ('issue','redeem','cancel')), amount_xof INTEGER NOT NULL CHECK(amount_xof>0),
    order_id TEXT REFERENCES orders(id), cash_session_id TEXT REFERENCES cash_sessions(id),
    user_id TEXT REFERENCES users(id), idempotency_key TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL);

CREATE TABLE stock_movements(
    id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES products(id),
    quantity_delta INTEGER NOT NULL CHECK(quantity_delta<>0), reason TEXT NOT NULL,
    order_id TEXT REFERENCES orders(id), user_id TEXT REFERENCES users(id), created_at TEXT NOT NULL, note TEXT);

CREATE TABLE audit_logs(
    id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT REFERENCES users(id), action TEXT NOT NULL,
    object_type TEXT NOT NULL, object_id TEXT, details TEXT, created_at TEXT NOT NULL);

CREATE TABLE sync_outbox(
    id TEXT PRIMARY KEY, seq INTEGER NOT NULL UNIQUE, kind TEXT NOT NULL, payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL, delivered_at TEXT);

CREATE TABLE counters(key TEXT PRIMARY KEY, value INTEGER NOT NULL);

CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE UNIQUE INDEX idx_one_open_session ON cash_sessions(status) WHERE status='open';

CREATE INDEX idx_orders_status ON orders(status, created_at);

CREATE INDEX idx_payments_order ON payments(order_id);

CREATE INDEX idx_payments_session ON payments(cash_session_id);

CREATE INDEX idx_items_order ON order_items(order_id);

CREATE INDEX idx_stock_product ON stock_movements(product_id, created_at);

CREATE INDEX idx_audit_date ON audit_logs(created_at);

CREATE INDEX idx_stock_date ON stock_movements(created_at);
