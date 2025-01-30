import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { supabase } from './supabase';

export interface License {
  key: string;
  expiresAt: string;
  status: 'active' | 'expired' | 'revoked';
  period: string;
}

interface LicenseState {
  license: License | null;
  isValid: boolean;
  setLicense: (license: License) => void;
  clearLicense: () => void;
  validateLicense: (key: string) => Promise<boolean>;
}

// Fonction pour calculer la date d'expiration
const calculateExpirationDate = (period: string): Date => {
  const expiresAt = new Date();
  if (period.toLowerCase() === 'à vie') {
    expiresAt.setFullYear(expiresAt.getFullYear() + 100); // 100 ans pour "à vie"
  } else {
    const [amount, unit] = period.split(' ');
    switch (unit.toLowerCase()) {
      case 'mois':
        expiresAt.setMonth(expiresAt.getMonth() + parseInt(amount));
        break;
      case 'ans':
      case 'année':
      case 'annee':
        expiresAt.setFullYear(expiresAt.getFullYear() + parseInt(amount));
        break;
      default:
        throw new Error('Période invalide');
    }
  }
  return expiresAt;
};

// Fonction pour valider une clé de licence
const validateLicenseKey = async (key: string): Promise<License | null> => {
  try {
    // Vérifier si la licence existe et est active
    const { data: license, error } = await supabase
      .from('licenses')
      .select('*')
      .eq('key', key)
      .eq('status', 'active')
      .single();

    if (error || !license) {
      console.error('License not found or inactive:', error);
      return null;
    }

    // Si la licence n'a pas encore été utilisée, calculer la date d'expiration
    if (!license.used_at) {
      const expiresAt = calculateExpirationDate(license.period);

      // Mettre à jour la licence comme utilisée
      const { error: updateError } = await supabase
        .from('licenses')
        .update({
          used_at: new Date().toISOString(),
          expires_at: expiresAt.toISOString(),
          status: 'used'
        })
        .eq('id', license.id);

      if (updateError) {
        console.error('Error updating license:', updateError);
        return null;
      }

      return {
        key: license.key,
        expiresAt: expiresAt.toISOString(),
        status: 'active',
        period: license.period
      };
    }

    // Si la licence a déjà été utilisée, vérifier si elle n'est pas expirée
    if (license.expires_at && new Date(license.expires_at) < new Date()) {
      return null;
    }

    return {
      key: license.key,
      expiresAt: license.expires_at!,
      status: 'active',
      period: license.period
    };
  } catch (error) {
    console.error('Error validating license:', error);
    return null;
  }
};

export const useLicense = create<LicenseState>()(
  persist(
    (set) => ({
      license: null,
      isValid: false,
      setLicense: (license) => set({ license, isValid: true }),
      clearLicense: () => set({ license: null, isValid: false }),
      validateLicense: async (key) => {
        const license = await validateLicenseKey(key);
        if (license) {
          set({ license, isValid: true });
          return true;
        }
        set({ license: null, isValid: false });
        return false;
      }
    }),
    {
      name: 'license-storage'
    }
  )
);