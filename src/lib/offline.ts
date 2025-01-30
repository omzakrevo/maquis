import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface OfflineState {
  isOnline: boolean;
  lastSync: string | null;
  pendingChanges: any[];
  setOnlineStatus: (status: boolean) => void;
  addPendingChange: (change: any) => void;
  clearPendingChanges: () => void;
}

export const useOfflineStore = create<OfflineState>()(
  persist(
    (set) => ({
      isOnline: navigator.onLine,
      lastSync: null,
      pendingChanges: [],
      setOnlineStatus: (status) => set({ isOnline: status }),
      addPendingChange: (change) => 
        set((state) => ({ 
          pendingChanges: [...state.pendingChanges, change] 
        })),
      clearPendingChanges: () => set({ pendingChanges: [], lastSync: new Date().toISOString() })
    }),
    {
      name: 'offline-storage'
    }
  )
);

export function initializeOfflineSupport() {
  const { setOnlineStatus } = useOfflineStore.getState();

  window.addEventListener('online', () => {
    setOnlineStatus(true);
    syncPendingChanges();
  });

  window.addEventListener('offline', () => {
    setOnlineStatus(false);
  });
}

async function syncPendingChanges() {
  const { pendingChanges, clearPendingChanges } = useOfflineStore.getState();
  
  if (pendingChanges.length === 0) return;

  try {
    // Implement your sync logic here
    // For example, sending pending orders to the server
    clearPendingChanges();
  } catch (error) {
    console.error('Error syncing pending changes:', error);
  }
}