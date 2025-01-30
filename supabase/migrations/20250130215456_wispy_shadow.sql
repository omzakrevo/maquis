/*
  # Update RLS policies for initialization

  1. Changes
    - Allow public access to users table for initialization
    - Add service role policies for all tables
    - Fix user authentication policies

  2. Security
    - Maintain RLS but allow necessary access
    - Add specific policies for service role
*/

-- Update users table policies
DROP POLICY IF EXISTS "Users can read own data" ON users;
DROP POLICY IF EXISTS "Admins have full access to users" ON users;

CREATE POLICY "Public can read users"
  ON users
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Service role has full access to users"
  ON users
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Update products table policies
DROP POLICY IF EXISTS "Anyone can read products" ON products;
DROP POLICY IF EXISTS "Admins have full access to products" ON products;

CREATE POLICY "Public can read products"
  ON products
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Service role has full access to products"
  ON products
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Update settings table policies
DROP POLICY IF EXISTS "Anyone can read settings" ON settings;
DROP POLICY IF EXISTS "Admins can update settings" ON settings;

CREATE POLICY "Public can read settings"
  ON settings
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Service role has full access to settings"
  ON settings
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Add service role policies for other tables
CREATE POLICY "Service role has full access to orders"
  ON orders
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Service role has full access to order_items"
  ON order_items
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Service role has full access to payments"
  ON payments
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Service role has full access to vouchers"
  ON vouchers
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);