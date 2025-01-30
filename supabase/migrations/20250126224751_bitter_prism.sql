/*
  # Création de la table des licences

  1. Nouvelle Table
    - `licenses`
      - `id` (uuid, clé primaire)
      - `key` (text, unique, la clé de licence)
      - `period` (text, la période de validité)
      - `status` (text, le statut de la licence)
      - `used_at` (timestamp, quand la licence a été utilisée)
      - `expires_at` (timestamp, quand la licence expire)
      - `created_at` (timestamp)

  2. Security
    - Enable RLS on `licenses` table
    - Add policy for authenticated users to read licenses
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