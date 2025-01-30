import toast from 'react-hot-toast';

const API_URL = import.meta.env.VITE_API_URL;

if (!API_URL) {
  throw new Error('VITE_API_URL is not defined in environment variables');
}

interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
}

let isInitialized = false;
let initializationPromise: Promise<boolean> | null = null;

async function checkApiConnection(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    const response = await fetch(`${API_URL}/health-check.php`, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Origin': window.location.origin
      },
      signal: controller.signal
    });
    
    clearTimeout(timeoutId);
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    const data = await response.json();
    return data.status === 'ok';
  } catch (error) {
    if (error instanceof Error) {
      console.error('API Connection Error:', error.message);
      if (error.name === 'AbortError') {
        toast.error('Le serveur met trop de temps à répondre');
      }
    }
    return false;
  }
}

async function handleResponse<T>(response: Response): Promise<T> {
  const contentType = response.headers.get('content-type');
  
  if (!response.ok) {
    let errorMessage = `Erreur HTTP! statut: ${response.status}`;
    
    if (contentType?.includes('application/json')) {
      const errorData = await response.json().catch(() => null);
      if (errorData?.error) {
        errorMessage = errorData.error;
      }
    }
    
    throw new Error(errorMessage);
  }
  
  if (!contentType?.includes('application/json')) {
    throw new Error('Réponse invalide du serveur');
  }
  
  const data: ApiResponse<T> = await response.json();
  
  if (!data.success) {
    throw new Error(data.error || 'Une erreur est survenue');
  }
  
  return data.data as T;
}

export async function initializeApi(): Promise<boolean> {
  if (isInitialized) return true;

  if (initializationPromise) {
    return initializationPromise;
  }

  initializationPromise = (async () => {
    let retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      const isConnected = await checkApiConnection();
      
      if (isConnected) {
        isInitialized = true;
        return true;
      }

      retryCount++;
      if (retryCount < maxRetries) {
        await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, retryCount - 1)));
        toast.loading(
          `Tentative de connexion ${retryCount + 1}/${maxRetries}...`,
          { duration: 1000 }
        );
      }
    }

    toast.error(
      'Impossible de se connecter au serveur. ' +
      'Vérifiez que le serveur est démarré et accessible.'
    );
    return false;
  })();

  return initializationPromise;
}

export async function apiRequest<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  if (!isInitialized) {
    const initialized = await initializeApi();
    if (!initialized) {
      throw new Error('Impossible de se connecter à l\'API');
    }
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30000); // 30s timeout

  try {
    const response = await fetch(`${API_URL}${endpoint}.php`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Origin': window.location.origin,
        ...options.headers,
      },
      signal: controller.signal
    });

    clearTimeout(timeoutId);
    return handleResponse<T>(response);
  } catch (error) {
    console.error('API Error:', error);
    if (error instanceof Error) {
      if (error.name === 'AbortError') {
        toast.error('La requête a pris trop de temps');
      } else {
        toast.error(`Erreur: ${error.message}`);
      }
    } else {
      toast.error('Erreur de connexion au serveur');
    }
    throw error;
  }
}

export const api = {
  // Authentification
  login: (username: string, password: string) =>
    apiRequest('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    }),

  // Utilisateurs
  getUsers: () => apiRequest('/users'),
  createUser: (data: any) =>
    apiRequest('/users', {
      method: 'POST',
      body: JSON.stringify(data),
    }),
  updateUser: (id: string, data: any) =>
    apiRequest(`/users/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),
  deleteUser: (id: string) =>
    apiRequest(`/users/${id}`, {
      method: 'DELETE',
    }),

  // Produits
  getProducts: () => apiRequest('/products'),
  createProduct: (data: any) =>
    apiRequest('/products', {
      method: 'POST',
      body: JSON.stringify(data),
    }),
  updateProduct: (id: string, data: any) =>
    apiRequest(`/products/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),
  deleteProduct: (id: string) =>
    apiRequest(`/products/${id}`, {
      method: 'DELETE',
    }),

  // Commandes
  getOrders: () => apiRequest('/orders'),
  createOrder: (data: any) =>
    apiRequest('/orders', {
      method: 'POST',
      body: JSON.stringify(data),
    }),
  updateOrder: (id: string, data: any) =>
    apiRequest(`/orders/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  // Paiements
  getPayments: () => apiRequest('/payments'),
  createPayment: (data: any) =>
    apiRequest('/payments', {
      method: 'POST',
      body: JSON.stringify(data),
    }),

  // Paramètres
  getSettings: () => apiRequest('/settings'),
  updateSettings: (data: any) =>
    apiRequest('/settings', {
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  // Avoirs
  getVouchers: () => apiRequest('/vouchers'),
  createVoucher: (data: any) =>
    apiRequest('/vouchers', {
      method: 'POST',
      body: JSON.stringify(data),
    }),
  updateVoucher: (id: string, data: any) =>
    apiRequest(`/vouchers/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),
};