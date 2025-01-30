import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export type Theme = 'light' | 'dark' | 'blue' | 'green';

interface ThemeState {
  theme: Theme;
  primaryColor: string;
  setTheme: (theme: Theme) => void;
  setPrimaryColor: (color: string) => void;
}

export const useTheme = create<ThemeState>()(
  persist(
    (set) => ({
      theme: 'light',
      primaryColor: '#3B82F6', // Couleur bleue par défaut
      setTheme: (theme) => set({ theme }),
      setPrimaryColor: (color) => {
        document.documentElement.style.setProperty('--primary', color);
        set({ primaryColor: color });
      },
    }),
    {
      name: 'theme-storage',
    }
  )
);