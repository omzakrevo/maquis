import { create } from 'zustand';
import bcrypt from 'bcryptjs';
import db, { initializeDb } from './db';

interface User {
  id: number;
  username: string;
  role: 'admin' | 'server';
}

interface AuthState {
  user: User | null;
  login: (username: string, password: string) => Promise<boolean>;
  logout: () => void;
}

export const useAuth = create<AuthState>((set) => ({
  user: null,
  login: async (username: string, password: string) => {
    try {
      // Ensure database is initialized before login
      await initializeDb();
      
      // Get user by username (case insensitive)
      const users = await db.users
        .where('username')
        .equalsIgnoreCase(username)
        .toArray();
      
      const user = users[0];
      
      if (!user) {
        console.error('User not found');
        return false;
      }
      
      const isValid = await bcrypt.compare(password, user.password);
      if (!isValid) {
        console.error('Invalid password');
        return false;
      }
      
      set({ 
        user: { 
          id: user.id!, 
          username: user.username, 
          role: user.role 
        } 
      });
      
      return true;
    } catch (error) {
      console.error('Login error:', error);
      return false;
    }
  },
  logout: () => set({ user: null }),
}));