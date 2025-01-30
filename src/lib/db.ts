import Dexie from 'dexie';
import bcrypt from 'bcryptjs';

export interface User {
  id?: number;
  username: string;
  password: string;
  role: 'admin' | 'server';
  created_at: string;
}

export interface Product {
  id?: number;
  name: string;
  price: number;
  category: 'alcoholic' | 'non-alcoholic';
  stock: number;
  created_at: string;
}

export interface Order {
  id?: number;
  user_id: number;
  status: 'pending' | 'approved' | 'rejected' | 'completed';
  total: number;
  created_at: string;
}

export interface OrderItem {
  id?: number;
  order_id: number;
  product_id: number;
  quantity: number;
  price: number;
}

export interface Payment {
  id?: number;
  order_id: number;
  amount: number;
  method: 'cash' | 'card' | 'mobile';
  status: 'completed' | 'pending' | 'failed';
  created_at: string;
}

export interface Settings {
  id?: number;
  name: string;
  phone: string;
  updated_at: string;
}

export interface Voucher {
  id?: number;
  code: string;
  amount: number;
  order_id: number;
  status: 'active' | 'used' | 'refunded';
  used_at?: string;
  created_at: string;
}

class MaquisDB extends Dexie {
  users!: Dexie.Table<User, number>;
  products!: Dexie.Table<Product, number>;
  orders!: Dexie.Table<Order, number>;
  orderItems!: Dexie.Table<OrderItem, number>;
  payments!: Dexie.Table<Payment, number>;
  settings!: Dexie.Table<Settings, number>;
  vouchers!: Dexie.Table<Voucher, number>;

  constructor() {
    super('MaquisDB');
    
    this.version(50).stores({
      users: '++id, username, role, created_at',
      products: '++id, name, category, created_at',
      orders: '++id, user_id, status, created_at',
      orderItems: '++id, order_id, product_id',
      payments: '++id, order_id, status, created_at',
      settings: '++id, updated_at',
      vouchers: '++id, code, order_id, status, created_at'
    });
  }
}

const db = new MaquisDB();

// Liste des produits de test
const defaultProducts = [
  // Boissons alcoolisées
  {
    name: 'Bière locale',
    price: 2.50,
    category: 'alcoholic' as const,
    stock: 100
  },
  {
    name: 'Heineken',
    price: 3.00,
    category: 'alcoholic' as const,
    stock: 80
  },
  {
    name: 'Vin rouge (verre)',
    price: 4.50,
    category: 'alcoholic' as const,
    stock: 50
  },
  {
    name: 'Whisky',
    price: 6.00,
    category: 'alcoholic' as const,
    stock: 30
  },
  {
    name: 'Gin Tonic',
    price: 7.00,
    category: 'alcoholic' as const,
    stock: 40
  },
  
  // Boissons non alcoolisées
  {
    name: 'Coca Cola',
    price: 2.00,
    category: 'non-alcoholic' as const,
    stock: 150
  },
  {
    name: 'Fanta',
    price: 2.00,
    category: 'non-alcoholic' as const,
    stock: 120
  },
  {
    name: 'Eau minérale',
    price: 1.50,
    category: 'non-alcoholic' as const,
    stock: 200
  },
  {
    name: 'Jus d\'orange',
    price: 2.50,
    category: 'non-alcoholic' as const,
    stock: 80
  },
  {
    name: 'Café',
    price: 1.50,
    category: 'non-alcoholic' as const,
    stock: 500
  },
  {
    name: 'Thé',
    price: 1.50,
    category: 'non-alcoholic' as const,
    stock: 300
  },
  {
    name: 'Limonade',
    price: 2.00,
    category: 'non-alcoholic' as const,
    stock: 100
  }
];

let initialized = false;

export async function initializeDb() {
  if (initialized) return db;

  try {
    // Check if admin user exists
    const adminExists = await db.users
      .where('role')
      .equals('admin')
      .count();

    if (adminExists === 0) {
      // Create admin user
      const hashedPassword = await bcrypt.hash('admin123', 10);
      await db.users.add({
        username: 'admin',
        password: hashedPassword,
        role: 'admin',
        created_at: new Date().toISOString()
      });

      // Add test products
      for (const product of defaultProducts) {
        await db.products.add({
          ...product,
          created_at: new Date().toISOString()
        });
      }

      // Initialize settings
      await db.settings.add({
        name: 'Mon Maquis',
        phone: '+225 00 00 00 00',
        updated_at: new Date().toISOString()
      });
      
      console.log('Database initialized with admin user, test products, and default settings');
    }

    initialized = true;
    return db;
  } catch (error) {
    console.error('Error initializing database:', error);
    throw error;
  }
}

export default db;