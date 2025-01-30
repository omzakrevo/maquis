import React from 'react';
import { Navigate } from 'react-router-dom';
import { useLicense } from '../lib/license';

export function LicenseCheck({ children }: { children: React.ReactNode }) {
  const { license, isValid } = useLicense();

  // Vérifier si la licence est expirée
  const isExpired = React.useMemo(() => {
    if (!license) return true;
    return new Date(license.expiresAt) < new Date();
  }, [license]);

  if (!isValid || isExpired) {
    return <Navigate to="/license" replace />;
  }

  return <>{children}</>;
}