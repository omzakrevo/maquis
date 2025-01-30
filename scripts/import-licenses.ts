import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';
import { parse } from 'csv-parse/sync';

// Configuration Supabase
const supabaseUrl = process.env.VITE_SUPABASE_URL;
const supabaseKey = process.env.VITE_SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  throw new Error('Missing Supabase environment variables');
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function importLicenses() {
  try {
    // Lire le fichier CSV
    const csvContent = fs.readFileSync(path.join(__dirname, '../licenses.csv'), 'utf-8');
    
    // Parser le CSV
    const records = parse(csvContent, {
      columns: true,
      skip_empty_lines: true
    });

    // Préparer les données pour l'insertion
    const licenses = records.map((record: any) => ({
      key: record.licence,
      period: record.periode,
      status: record.etat
    }));

    // Insérer les licences dans Supabase
    const { error } = await supabase
      .from('licenses')
      .insert(licenses);

    if (error) {
      throw error;
    }

    console.log(`Successfully imported ${licenses.length} licenses`);
  } catch (error) {
    console.error('Error importing licenses:', error);
  }
}

importLicenses();