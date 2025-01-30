import React from 'react';
import { 
  TrendingUp, 
  Package, 
  AlertTriangle, 
  DollarSign,
  Beer,
  Coffee,
  Clock,
  CheckCircle2
} from 'lucide-react';
import db from '../lib/db';
import { useAuth } from '../lib/auth';

interface DashboardStats {
  totalRevenue: number;
  totalProducts: number;
  lowStockCount: number;
  pendingOrders: number;
  alcoholicCount: number;
  nonAlcoholicCount: number;
  todayOrders: number;
  completedOrders: number;
}

const formatPrice = (amount: number) => `${amount.toLocaleString('fr-FR')} FCFA`;

function StatCard({ 
  title, 
  value, 
  icon: Icon, 
  trend,
  color = 'blue',
  isCurrency = false
}: { 
  title: string; 
  value: string | number; 
  icon: React.ElementType;
  trend?: string;
  color?: 'blue' | 'green' | 'yellow' | 'red';
  isCurrency?: boolean;
}) {
  const colorClasses = {
    blue: 'bg-blue-50 text-blue-600',
    green: 'bg-green-50 text-green-600',
    yellow: 'bg-yellow-50 text-yellow-600',
    red: 'bg-red-50 text-red-600'
  };

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between mb-4">
        <div className={`p-3 rounded-full ${colorClasses[color]}`}>
          <Icon className="h-6 w-6" />
        </div>
        {trend && (
          <span className={`text-sm ${trend.startsWith('+') ? 'text-green-600' : 'text-red-600'}`}>
            {trend}
          </span>
        )}
      </div>
      <h3 className="text-gray-600 text-sm font-medium">{title}</h3>
      <p className="text-2xl font-semibold text-gray-900 mt-2">
        {isCurrency ? formatPrice(value as number) : value}
      </p>
    </div>
  );
}

function useDashboardStats() {
  const [stats, setStats] = React.useState<DashboardStats>({
    totalRevenue: 0,
    totalProducts: 0,
    lowStockCount: 0,
    pendingOrders: 0,
    alcoholicCount: 0,
    nonAlcoholicCount: 0,
    todayOrders: 0,
    completedOrders: 0
  });

  React.useEffect(() => {
    async function loadStats() {
      try {
        // Get completed orders for revenue
        const completedOrders = await db.orders
          .where('status')
          .equals('completed')
          .toArray();
        
        const totalRevenue = completedOrders.reduce((sum, order) => sum + order.total, 0);

        // Get product counts
        const products = await db.products.toArray();
        const productStats = products.reduce((acc, product) => ({
          total: acc.total + 1,
          lowStock: acc.lowStock + (product.stock < 10 ? 1 : 0),
          alcoholic: acc.alcoholic + (product.category === 'alcoholic' ? 1 : 0),
          nonAlcoholic: acc.nonAlcoholic + (product.category === 'non-alcoholic' ? 1 : 0)
        }), { total: 0, lowStock: 0, alcoholic: 0, nonAlcoholic: 0 });

        // Get order counts
        const allOrders = await db.orders.toArray();
        const today = new Date().toDateString();
        
        const orderStats = allOrders.reduce((acc, order) => ({
          pending: acc.pending + (order.status === 'pending' ? 1 : 0),
          completed: acc.completed + (order.status === 'completed' ? 1 : 0),
          today: acc.today + (
            order.status === 'completed' && 
            new Date(order.created_at).toDateString() === today ? 1 : 0
          )
        }), { pending: 0, completed: 0, today: 0 });

        setStats({
          totalRevenue,
          totalProducts: productStats.total,
          lowStockCount: productStats.lowStock,
          pendingOrders: orderStats.pending,
          alcoholicCount: productStats.alcoholic,
          nonAlcoholicCount: productStats.nonAlcoholic,
          todayOrders: orderStats.today,
          completedOrders: orderStats.completed
        });
      } catch (error) {
        console.error('Error loading dashboard stats:', error);
      }
    }

    loadStats();
  }, []);

  return stats;
}

function RecentOrders() {
  const [orders, setOrders] = React.useState<any[]>([]);

  React.useEffect(() => {
    async function loadOrders() {
      try {
        // Get 5 most recent orders with user info
        const recentOrders = await db.orders
          .orderBy('created_at')
          .reverse()
          .limit(5)
          .toArray();

        // Get user info for each order
        const ordersWithUserInfo = await Promise.all(
          recentOrders.map(async (order) => {
            const user = await db.users.get(order.user_id);
            const items = await db.orderItems
              .where('order_id')
              .equals(order.id!)
              .toArray();

            const itemsWithProducts = await Promise.all(
              items.map(async (item) => {
                const product = await db.products.get(item.product_id);
                return {
                  ...item,
                  product_name: product?.name
                };
              })
            );

            return {
              ...order,
              server: user?.username,
              items: itemsWithProducts
            };
          })
        );

        setOrders(ordersWithUserInfo);
      } catch (error) {
        console.error('Error loading recent orders:', error);
      }
    }

    loadOrders();
  }, []);

  const statusColors = {
    pending: 'bg-yellow-100 text-yellow-800',
    approved: 'bg-blue-100 text-blue-800',
    completed: 'bg-green-100 text-green-800',
    rejected: 'bg-red-100 text-red-800'
  };

  return (
    <div className="bg-white rounded-lg shadow">
      <div className="p-6">
        <h2 className="text-lg font-medium text-gray-900">Commandes récentes</h2>
        <div className="mt-4">
          <table className="min-w-full divide-y divide-gray-200">
            <thead>
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  ID
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Serveur
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Total
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Date
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {orders.map((order) => (
                <tr key={order.id}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    #{order.id}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {order.server}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-right font-medium">
                    {formatPrice(order.total)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${statusColors[order.status]}`}>
                      {order.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {new Date(order.created_at).toLocaleString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function Dashboard() {
  const stats = useDashboardStats();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">Tableau de bord</h1>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard
          title="Chiffre d'affaires"
          value={stats.totalRevenue}
          icon={TrendingUp}
          trend="+12.5%"
          color="blue"
          isCurrency
        />
        <StatCard
          title="Produits en stock"
          value={stats.totalProducts}
          icon={Package}
          color="green"
        />
        <StatCard
          title="Stock faible"
          value={stats.lowStockCount}
          icon={AlertTriangle}
          color="red"
        />
        <StatCard
          title="Commandes en attente"
          value={stats.pendingOrders}
          icon={Clock}
          color="yellow"
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard
          title="Boissons alcoolisées"
          value={stats.alcoholicCount}
          icon={Beer}
          color="blue"
        />
        <StatCard
          title="Boissons non-alcoolisées"
          value={stats.nonAlcoholicCount}
          icon={Coffee}
          color="green"
        />
        <StatCard
          title="Commandes du jour"
          value={stats.todayOrders}
          icon={DollarSign}
          color="yellow"
        />
        <StatCard
          title="Commandes complétées"
          value={stats.completedOrders}
          icon={CheckCircle2}
          color="green"
        />
      </div>

      <RecentOrders />
    </div>
  );
}

export default Dashboard;