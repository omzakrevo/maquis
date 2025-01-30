-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables if they exist
DROP TABLE IF EXISTS vouchers;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS settings;
DROP TABLE IF EXISTS users;

-- Users table
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  username text UNIQUE NOT NULL,
  password text NOT NULL,
  role text NOT NULL CHECK (role IN ('admin', 'server')),
  created_at timestamptz DEFAULT now()
);

-- Products table
CREATE TABLE products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  price decimal NOT NULL CHECK (price >= 0),
  category text NOT NULL CHECK (category IN ('alcoholic', 'non-alcoholic')),
  stock integer NOT NULL DEFAULT 0 CHECK (stock >= 0),
  created_at timestamptz DEFAULT now()
);

-- Orders table
CREATE TABLE orders (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
  total decimal NOT NULL CHECK (total >= 0),
  created_at timestamptz DEFAULT now()
);

-- Order items table
CREATE TABLE order_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid REFERENCES orders(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK (quantity > 0),
  price decimal NOT NULL CHECK (price >= 0),
  created_at timestamptz DEFAULT now()
);

-- Payments table
CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid REFERENCES orders(id) ON DELETE RESTRICT,
  amount decimal NOT NULL CHECK (amount > 0),
  method text NOT NULL CHECK (method IN ('cash', 'card', 'mobile')),
  status text NOT NULL CHECK (status IN ('completed', 'pending', 'failed')),
  created_at timestamptz DEFAULT now()
);

-- Settings table
CREATE TABLE settings (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  phone text NOT NULL,
  updated_at timestamptz DEFAULT now()
);

-- Vouchers table
CREATE TABLE vouchers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  code text UNIQUE NOT NULL,
  amount decimal NOT NULL CHECK (amount > 0),
  order_id uuid REFERENCES orders(id) ON DELETE RESTRICT,
  status text NOT NULL CHECK (status IN ('active', 'used', 'refunded')),
  used_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE vouchers ENABLE ROW LEVEL SECURITY;

-- Create policies for public access
CREATE POLICY "Public can read users" ON users
  FOR SELECT TO public USING (true);

CREATE POLICY "Public can read products" ON products
  FOR SELECT TO public USING (true);

CREATE POLICY "Public can read settings" ON settings
  FOR SELECT TO public USING (true);

-- Create policies for service role
CREATE POLICY "Service role has full access to users" ON users
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to products" ON products
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to orders" ON orders
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to order_items" ON order_items
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to payments" ON payments
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to settings" ON settings
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to vouchers" ON vouchers
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Create indexes for better performance
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_payments_order_id ON payments(order_id);
CREATE INDEX idx_vouchers_code ON vouchers(code);
CREATE INDEX idx_vouchers_order_id ON vouchers(order_id);