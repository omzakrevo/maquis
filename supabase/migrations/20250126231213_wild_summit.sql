/*
  # Create licenses table

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
*/

CREATE TABLE IF NOT EXISTS licenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  period text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  used_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read licenses"
  ON licenses
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Only authenticated users can update licenses"
  ON licenses
  FOR UPDATE
  TO authenticated
  USING (status = 'active');