import React from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Plus, X, Search, Clock, CheckCircle, XCircle, ShoppingCart, Printer, FileSpreadsheet, FileDown } from 'lucide-react';
import toast from 'react-hot-toast';
import { createRoot } from 'react-dom/client';
import { useNavigate } from 'react-router-dom';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import * as XLSX from 'xlsx';
import db from '../lib/db';
import { useAuth } from '../lib/auth';
import type { Product, Order, OrderItem } from '../lib/db';
import OrderTicket from '../components/OrderTicket';

const formatPrice = (amount: number) => `${amount.toLocaleString('fr-FR')} FCFA`;

const orderItemSchema = z.object({
  product_id: z.number().min(1, 'Produit requis'),
  quantity: z.number().min(1, 'Quantité minimale de 1'),
});

const orderSchema = z.object({
  items: z.array(orderItemSchema).min(1, 'Au moins un produit est requis'),
});

type OrderFormData = z.infer<typeof orderSchema>;

interface OrderWithDetails extends Order {
  server_name?: string;
  items: (OrderItem & { product_name?: string })[];
}

function OrderForm({ onSubmit, onCancel }: { onSubmit: (data: OrderFormData) => void; onCancel: () => void }) {
  const [products, setProducts] = React.useState<Product[]>([]);
  const [selectedProducts, setSelectedProducts] = React.useState<Map<number, { quantity: number; name: string; price: number }>>(new Map());
  const [productSearch, setProductSearch] = React.useState('');

  React.useEffect(() => {
    async function loadFilteredProducts() {
      try {
        const results = await db.products
          .filter(product => 
            product.name.toLowerCase().includes(productSearch.toLowerCase()) && 
            product.stock > 0
          )
          .toArray();
        setProducts(results);
      } catch (error) {
        console.error('Error loading products:', error);
        toast.error('Erreur lors du chargement des produits');
      }
    }
    loadFilteredProducts();
  }, [productSearch]);

  const handleAddProduct = (product: Product) => {
    if (!product.id) return;
    setSelectedProducts(prev => {
      const next = new Map(prev);
      const current = next.get(product.id!);
      if (current) {
        next.set(product.id!, { ...current, quantity: current.quantity + 1 });
      } else {
        next.set(product.id!, { quantity: 1, name: product.name, price: product.price });
      }
      return next;
    });
  };

  const handleRemoveProduct = (productId: number) => {
    setSelectedProducts(prev => {
      const next = new Map(prev);
      next.delete(productId);
      return next;
    });
  };

  const handleQuantityChange = (productId: number, quantity: number) => {
    if (quantity < 1) return;
    setSelectedProducts(prev => {
      const next = new Map(prev);
      const current = next.get(productId);
      if (current) {
        next.set(productId, { ...current, quantity });
      }
      return next;
    });
  };

  const handleFormSubmit = () => {
    const items = Array.from(selectedProducts.entries()).map(([product_id, { quantity }]) => ({
      product_id,
      quantity,
    }));
    onSubmit({ items });
  };

  const total = Array.from(selectedProducts.entries()).reduce(
    (sum, [_, { quantity, price }]) => sum + quantity * price,
    0
  );

  return (
    <div className="space-y-6 bg-white p-6 rounded-lg shadow">
      <div className="flex justify-between items-center">
        <h3 className="text-lg font-medium">Nouvelle commande</h3>
        <button
          type="button"
          onClick={onCancel}
          className="p-2 text-gray-400 hover:text-gray-500"
        >
          <X className="h-5 w-5" />
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <div className="mb-4">
            <div className="relative">
              <input
                type="text"
                placeholder="Rechercher un produit..."
                value={productSearch}
                onChange={(e) => setProductSearch(e.target.value)}
                className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
              />
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <Search className="h-5 w-5 text-gray-400" />
              </div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            {products.map((product) => (
              <button
                key={product.id}
                onClick={() => handleAddProduct(product)}
                className="p-4 border rounded-lg hover:bg-gray-50 text-left"
              >
                <div className="font-medium">{product.name}</div>
                <div className="text-sm text-gray-500">{formatPrice(product.price)}</div>
                <div className="text-xs text-gray-400">Stock: {product.stock}</div>
              </button>
            ))}
          </div>
        </div>

        <div>
          <h4 className="font-medium mb-4">Panier</h4>
          {selectedProducts.size === 0 ? (
            <div className="text-center py-8 text-gray-500">
              <ShoppingCart className="h-12 w-12 mx-auto mb-4 text-gray-400" />
              <p>Le panier est vide</p>
            </div>
          ) : (
            <div className="space-y-4">
              {Array.from(selectedProducts.entries()).map(([productId, { quantity, name, price }]) => (
                <div key={productId} className="flex items-center justify-between p-4 border rounded-lg">
                  <div>
                    <div className="font-medium">{name}</div>
                    <div className="text-sm text-gray-500">{formatPrice(price)}</div>
                  </div>
                  <div className="flex items-center space-x-4">
                    <div className="flex items-center space-x-2">
                      <button
                        type="button"
                        onClick={() => handleQuantityChange(productId, quantity - 1)}
                        className="p-1 rounded-full hover:bg-gray-100"
                      >
                        -
                      </button>
                      <span className="w-8 text-center">{quantity}</span>
                      <button
                        type="button"
                        onClick={() => handleQuantityChange(productId, quantity + 1)}
                        className="p-1 rounded-full hover:bg-gray-100"
                      >
                        +
                      </button>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleRemoveProduct(productId)}
                      className="text-red-600 hover:text-red-800"
                    >
                      <X className="h-5 w-5" />
                    </button>
                  </div>
                </div>
              ))}

              <div className="border-t pt-4 mt-4">
                <div className="flex justify-between items-center font-medium">
                  <span>Total</span>
                  <span>{formatPrice(total)}</span>
                </div>
              </div>

              <div className="flex justify-end space-x-3">
                <button
                  type="button"
                  onClick={onCancel}
                  className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  Annuler
                </button>
                <button
                  type="button"
                  onClick={handleFormSubmit}
                  disabled={selectedProducts.size === 0}
                  className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
                >
                  Commander
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Orders() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [orders, setOrders] = React.useState<OrderWithDetails[]>([]);
  const [showForm, setShowForm] = React.useState(false);
  const [searchTerm, setSearchTerm] = React.useState('');

  const loadOrders = React.useCallback(async () => {
    try {
      // Get all orders
      const allOrders = await db.orders
        .orderBy('created_at')
        .reverse()
        .toArray();

      // Get matching users for search
      const users = await db.users
        .filter(u => u.username.toLowerCase().includes(searchTerm.toLowerCase()))
        .toArray();
      const userIds = new Set(users.map(u => u.id));

      // Filter orders by matching users and current user if not admin
      const filteredOrders = allOrders.filter(order => {
        if (user?.role === 'admin') {
          return userIds.size === 0 || userIds.has(order.user_id);
        }
        return order.user_id === user?.id;
      });

      // Get items and user info for each order
      const ordersWithDetails = await Promise.all(
        filteredOrders.map(async order => {
          const orderUser = await db.users.get(order.user_id);
          const items = await db.orderItems
            .where('order_id')
            .equals(order.id!)
            .toArray();

          const itemsWithProducts = await Promise.all(
            items.map(async item => {
              const product = await db.products.get(item.product_id);
              return {
                ...item,
                product_name: product?.name
              };
            })
          );

          return {
            ...order,
            server_name: orderUser?.username,
            items: itemsWithProducts
          };
        })
      );

      setOrders(ordersWithDetails);
    } catch (error) {
      console.error('Error loading orders:', error);
      toast.error('Erreur lors du chargement des commandes');
    }
  }, [searchTerm, user]);

  React.useEffect(() => {
    loadOrders();
  }, [loadOrders]);

  const handleCreateOrder = async (data: OrderFormData) => {
    try {
      let total = 0;
      const items = [];

      // Calculate total and prepare items
      for (const item of data.items) {
        const product = await db.products.get(item.product_id);
        if (!product) throw new Error('Product not found');
        
        total += product.price * item.quantity;
        items.push({
          product_id: item.product_id,
          quantity: item.quantity,
          price: product.price
        });

        // Update stock
        await db.products.update(item.product_id, {
          stock: product.stock - item.quantity
        });
      }

      // Create order
      const orderId = await db.orders.add({
        user_id: user!.id,
        status: 'pending',
        total,
        created_at: new Date().toISOString()
      });

      // Add order items
      for (const item of items) {
        await db.orderItems.add({
          order_id: orderId,
          product_id: item.product_id,
          quantity: item.quantity,
          price: item.price
        });
      }

      toast.success('Commande créée avec succès');
      setShowForm(false);
      loadOrders();
    } catch (error) {
      console.error('Error creating order:', error);
      toast.error('Erreur lors de la création de la commande');
    }
  };

  const handleUpdateStatus = async (orderId: number, newStatus: Order['status']) => {
    try {
      await db.orders.update(orderId, { status: newStatus });

      // Imprimer le ticket après l'approbation
      if (newStatus === 'approved') {
        const order = orders.find(o => o.id === orderId);
        if (order) {
          // Créer un élément caché pour le ticket
          const ticketContainer = document.createElement('div');
          ticketContainer.className = 'print-only';
          document.body.appendChild(ticketContainer);

          // Rendre le ticket dans le conteneur caché
          const root = createRoot(ticketContainer);
          root.render(
            <OrderTicket
              order={order}
              items={order.items}
              serverName={order.server_name}
            />
          );

          // Attendre que le rendu soit terminé
          setTimeout(() => {
            // Imprimer le ticket
            window.print();

            // Nettoyer
            root.unmount();
            document.body.removeChild(ticketContainer);

            // Rediriger vers la page des paiements si admin
            if (user?.role === 'admin') {
              navigate('/payments');
            }
          }, 100);
        }
      }

      // Si la commande est complétée, imprimer le ticket
      if (newStatus === 'completed') {
        const order = orders.find(o => o.id === orderId);
        if (order) {
          // Créer un élément caché pour le ticket
          const ticketContainer = document.createElement('div');
          ticketContainer.className = 'print-only';
          document.body.appendChild(ticketContainer);

          // Rendre le ticket dans le conteneur caché
          const root = createRoot(ticketContainer);
          root.render(
            <OrderTicket
              order={order}
              items={order.items}
              serverName={order.server_name}
            />
          );

          // Attendre que le rendu soit terminé
          setTimeout(() => {
            // Imprimer le ticket
            window.print();

            // Nettoyer
            root.unmount();
            document.body.removeChild(ticketContainer);
          }, 100);
        }
      }

      // Si rejetée, restaurer le stock
      if (newStatus === 'rejected') {
        const items = await db.orderItems
          .where('order_id')
          .equals(orderId)
          .toArray();

        for (const item of items) {
          const product = await db.products.get(item.product_id);
          if (product) {
            await db.products.update(item.product_id, {
              stock: product.stock + item.quantity
            });
          }
        }
      }

      toast.success('Statut mis à jour avec succès');
      loadOrders();
    } catch (error) {
      console.error('Error updating order status:', error);
      toast.error('Erreur lors de la mise à jour du statut');
    }
  };

  const handlePrintOrder = async (order: OrderWithDetails) => {
    try {
      // Créer un élément caché pour le ticket
      const ticketContainer = document.createElement('div');
      ticketContainer.className = 'print-only';
      document.body.appendChild(ticketContainer);

      // Rendre le ticket dans le conteneur caché
      const root = createRoot(ticketContainer);
      root.render(
        <OrderTicket
          order={order}
          items={order.items}
          serverName={order.server_name}
        />
      );

      // Attendre que le rendu soit terminé
      setTimeout(() => {
        // Imprimer le ticket
        window.print();

        // Nettoyer
        root.unmount();
        document.body.removeChild(ticketContainer);
      }, 100);
    } catch (error) {
      console.error('Error printing order:', error);
      toast.error('Erreur lors de l\'impression du ticket');
    }
  };

  const exportToPDF = () => {
    try {
      const doc = new jsPDF();
      
      // Add title
      doc.setFontSize(16);
      doc.text('Liste des commandes', 14, 15);
      doc.setFontSize(12);

      // Prepare data for table
      const tableData = orders.map(order => [
        `#${order.id}`,
        order.server_name,
        new Date(order.created_at).toLocaleString(),
        order.status,
        formatPrice(order.total)
      ]);

      // Add table
      autoTable(doc, {
        head: [['N°', 'Serveur', 'Date', 'Statut', 'Total']],
        body: tableData,
        startY: 25,
        styles: { fontSize: 10 },
        headStyles: { fillColor: [66, 139, 202] }
      });

      // Save PDF
      doc.save('commandes.pdf');
      toast.success('PDF exporté avec succès');
    } catch (error) {
      console.error('Error exporting to PDF:', error);
      toast.error('Erreur lors de l\'export PDF');
    }
  };

  const exportToExcel = () => {
    try {
      // Prepare data
      const data = orders.map(order => ({
        'N° Commande': `#${order.id}`,
        'Serveur': order.server_name,
        'Date': new Date(order.created_at).toLocaleString(),
        'Statut': order.status,
        'Total': formatPrice(order.total),
        'Détails': order.items.map(item => 
          `${item.product_name} (${item.quantity}x)`
        ).join(', ')
      }));

      // Create worksheet
      const ws = XLSX.utils.json_to_sheet(data);
      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, 'Commandes');

      // Save file
      XLSX.writeFile(wb, 'commandes.xlsx');
      toast.success('Excel exporté avec succès');
    } catch (error) {
      console.error('Error exporting to Excel:', error);
      toast.error('Erreur lors de l\'export Excel');
    }
  };

  const statusColors = {
    pending: 'bg-yellow-100 text-yellow-800',
    approved: 'bg-blue-100 text-blue-800',
    completed: 'bg-green-100 text-green-800',
    rejected: 'bg-red-100 text-red-800'
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold text-gray-900">Commandes</h1>
        <div className="flex space-x-2">
          {user?.role === 'server' && (
            <button
              onClick={() => setShowForm(true)}
              className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              <Plus className="h-5 w-5 inline-block mr-2" />
              Nouvelle commande
            </button>
          )}
          <button
            onClick={exportToPDF}
            className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            <FileDown className="h-5 w-5 inline-block mr-2" />
            Exporter PDF
          </button>
          <button
            onClick={exportToExcel}
            className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            <FileSpreadsheet className="h-5 w-5 inline-block mr-2" />
            Exporter Excel
          </button>
        </div>
      </div>

      <div className="flex justify-between items-center bg-white p-4 rounded-lg shadow">
        <div className="relative flex-1 max-w-xs">
          <input
            type="text"
            placeholder="Rechercher par serveur..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
          />
          <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <Search className="h-5 w-5 text-gray-400" />
          </div>
        </div>
      </div>

      {showForm && (
        <OrderForm
          onSubmit={handleCreateOrder}
          onCancel={() => setShowForm(false)}
        />
      )}

      <div className="bg-white shadow rounded-lg">
        <div className="px-4 py-5 sm:p-6">
          {orders.map((order) => (
            <div key={order.id} className="mb-8 last:mb-0">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h3 className="text-lg font-medium">
                    Commande #{order.id}
                  </h3>
                  <p className="text-sm text-gray-500">
                    Par {order.server_name} le {new Date(order.created_at).toLocaleString()}
                  </p>
                </div>
                <div className="flex items-center space-x-4">
                  <span className={`px-2 py-1 text-xs font-semibold rounded-full ${statusColors[order.status]}`}>
                    {order.status}
                  </span>
                  <button
                    onClick={() => handlePrintOrder(order)}
                    className="p-1 text-gray-600 hover:text-gray-800"
                    title="Imprimer le ticket"
                  >
                    <Printer className="h-5 w-5" />
                  </button>
                  {user?.role === 'admin' && order.status === 'pending' && (
                    <div className="flex space-x-2">
                      <button
                        onClick={() => handleUpdateStatus(order.id!, 'approved')}
                        className="p-1 text-green-600 hover:text-green-800"
                      >
                        <CheckCircle className="h-5 w-5" />
                      </button>
                      <button
                        onClick={() => handleUpdateStatus(order.id!, 'rejected')}
                        className="p-1 text-red-600 hover:text-red-800"
                      >
                        <XCircle className="h-5 w-5" />
                      </button>
                    </div>
                  )}
                  {user?.role === 'server' && order.status === 'approved' && (
                    <button
                      onClick={() => handleUpdateStatus(order.id!, 'completed')}
                      className="p-1 text-green-600 hover:text-green-800"
                    >
                      <CheckCircle className="h-5 w-5" />
                    </button>
                  )}
                </div>
              </div>

              <div className="bg-gray-50 rounded-lg p-4">
                <table className="min-w-full">
                  <thead>
                    <tr>
                      <th className="text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Produit
                      </th>
                      <th className="text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Quantité
                      </th>
                      <th className="text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Prix unitaire
                      </th>
                      <th className="text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Total
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {order.items.map((item) => (
                      <tr key={item.id}>
                        <td className="py-2 text-sm">{item.product_name}</td>
                        <td className="py-2 text-sm text-right">{item.quantity}</td>
                        <td className="py-2 text-sm text-right">{formatPrice(item.price)}</td>
                        <td className="py-2 text-sm text-right">{formatPrice(item.quantity * item.price)}</td>
                      </tr>
                    ))}
                    <tr className="border-t">
                      <td colSpan={3} className="py-2 text-right font-medium">Total</td>
                      <td className="py-2 text-right font-medium">{formatPrice(order.total)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default Orders;