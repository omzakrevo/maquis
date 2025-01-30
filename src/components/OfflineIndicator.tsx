import React from 'react';
import { Wifi, WifiOff } from 'lucide-react';
import { useOfflineStore } from '../lib/offline';

export function OfflineIndicator() {
  const isOnline = useOfflineStore((state) => state.isOnline);
  const pendingChanges = useOfflineStore((state) => state.pendingChanges);

  return (
    <div className={`fixed bottom-4 right-4 p-3 rounded-lg shadow-lg flex items-center space-x-2 ${
      isOnline ? 'bg-green-100' : 'bg-yellow-100'
    }`}>
      {isOnline ? (
        <>
          <Wifi className="h-5 w-5 text-green-600" />
          <span className="text-sm text-green-600">En ligne</span>
        </>
      ) : (
        <>
          <WifiOff className="h-5 w-5 text-yellow-600" />
          <span className="text-sm text-yellow-600">
            Hors ligne
            {pendingChanges.length > 0 && ` (${pendingChanges.length} en attente)`}
          </span>
        </>
      )}
    </div>
  );
}