import React from 'react';
import { useTheme } from '../lib/theme';

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const { theme, primaryColor } = useTheme();

  React.useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    document.documentElement.style.setProperty('--primary', primaryColor);
  }, [theme, primaryColor]);

  return <>{children}</>;
}