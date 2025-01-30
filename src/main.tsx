import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.tsx';
import { ThemeProvider } from './components/ThemeProvider';
import './index.css';
import { initializeDb } from './lib/db';
import { initializeOfflineSupport } from './lib/offline';
import { initializeApi } from './lib/api';

// Initialize the database, offline support, and API before rendering
Promise.all([
  initializeDb(),
  initializeOfflineSupport(),
  initializeApi()
]).then(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <ThemeProvider>
        <App />
      </ThemeProvider>
    </StrictMode>
  );
}).catch(error => {
  console.error('Failed to initialize application:', error);
  
  // Show error message to user
  const root = document.getElementById('root');
  if (root) {
    root.innerHTML = `
      <div style="
        height: 100vh;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        text-align: center;
        padding: 20px;
        font-family: system-ui, -apple-system, sans-serif;
      ">
        <h1 style="color: #EF4444; margin-bottom: 16px;">
          Erreur de démarrage
        </h1>
        <p style="color: #374151; max-width: 500px; margin-bottom: 24px;">
          Impossible de démarrer l'application. Veuillez vérifier que :
          <br>- Votre connexion internet fonctionne
          <br>- Les variables d'environnement sont correctement configurées
          <br>- Le serveur API est accessible
        </p>
        <button onclick="window.location.reload()" style="
          background: #3B82F6;
          color: white;
          border: none;
          padding: 8px 16px;
          border-radius: 6px;
          cursor: pointer;
        ">
          Réessayer
        </button>
      </div>
    `;
  }
});