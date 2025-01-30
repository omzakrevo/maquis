/*
  # Create licenses table with updated schema

  1. New Tables
    - `licenses`
      - `id` (uuid, primary key)
      - `key` (text, unique)
      - `period` (text)
      - `status` (text)
      - `used_at` (timestamptz, nullable)
      - `expires_at` (timestamptz, nullable)
      - `created_at` (timestamptz)

  2. Security
    - Enable RLS on `licenses` table
    - Add policy for public read access
    - Add policy for authenticated users to update active licenses
    - Add policy for service role to manage all licenses

  3. Changes
    - Added service role policy for full access
    - Improved status constraints
    - Added index on key for faster lookups
*/

-- Drop existing table if it exists
DROP TABLE IF EXISTS licenses;

-- Create the licenses table
CREATE TABLE licenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  period text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'used', 'expired', 'revoked')),
  used_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Create index for faster key lookups
CREATE INDEX licenses_key_idx ON licenses(key);

-- Enable Row Level Security
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Anyone can read licenses"
  ON licenses
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Only authenticated users can update active licenses"
  ON licenses
  FOR UPDATE
  TO authenticated
  USING (status = 'active');

CREATE POLICY "Service role has full access"
  ON licenses
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);