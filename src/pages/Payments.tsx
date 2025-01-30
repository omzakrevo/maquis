import React from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Search, DollarSign, CreditCard, Smartphone, Printer, Ticket, FileDown, FileSpreadsheet } from 'lucide-react';
import toast from 'react-hot-toast';
import { createRoot } from 'react-dom/client';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import * as XLSX from 'xlsx';
import db from '../lib/db';
import type { Payment, Order, Voucher } from '../lib/db';
import OrderTicket from '../components/OrderTicket';

const formatPrice = (amount: number) => `${amount.toLocaleString('fr-FR')} FCFA`;

const paymentSchema = z.object({
  order_id: z.number().min(1, 'Commande requise'),
  amount: z.number().min(0.01, 'Montant invalide'),
  method: z.enum(['cash', 'card', 'mobile'], {
    errorMap: () => ({ message: 'Méthode de paiement invalide' })
  })
});

const voucherSchema = z.object({
  code: z.string().min(1, 'Code requis')
});

type PaymentFormData = z.infer<typeof paymentSchema>;
type VoucherFormData = z.infer<typeof voucherSchema>;

interface PaymentWithDetails extends Payment {
  order?: Order;
  server_name?: string;
}

interface OrderWithDetails extends Order {
  server_name?: string;
  items: any[];
}

function PaymentMethodIcon({ method }: { method: Payment['method'] }) {
  switch (method) {
    case 'cash':
      return <DollarSign className="h-5 w-5" />;
    case 'card':
      return <CreditCard className="h-5 w-5" />;
    case 'mobile':
      return <Smartphone className="h-5 w-5" />;
  }
}

function VoucherRefundForm({ onClose }: { onClose: () => void }) {
  const { register, handleSubmit, formState: { errors } } = useForm<VoucherFormData>({
    resolver: zodResolver(voucherSchema)
  });

  const onSubmit = async (data: VoucherFormData) => {
    try {
      // Rechercher l'avoir
      const voucher = await db.vouchers
        .where('code')
        .equalsIgnoreCase(data.code)
        .first();

      if (!voucher) {
        toast.error('Avoir non trouvé');
        return;
      }

      if (voucher.status !== 'active') {
        toast.error('Cet avoir a déjà été utilisé ou remboursé');
        return;
      }

      // Mettre à jour le statut de l'avoir
      await db.vouchers.update(voucher.id!, {
        status: 'refunded',
        used_at: new Date().toISOString()
      });

      toast.success(`Avoir de ${formatPrice(voucher.amount)} remboursé avec succès`);
      onClose();
    } catch (error) {
      console.error('Error refunding voucher:', error);
      toast.error('Erreur lors du remboursement de l\'avoir');
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 bg-white p-6 rounded-lg shadow">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-medium">Rembourser un avoir</h3>
        <button
          type="button"
          onClick={onClose}
          className="text-gray-400 hover:text-gray-500"
        >
          ×
        </button>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">
          Code de l'avoir
        </label>
        <input
          type="text"
          {...register('code')}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
          placeholder="Entrez le code de l'avoir"
        />
        {errors.code && (
          <p className="mt-1 text-sm text-red-600">{errors.code.message}</p>
        )}
      </div>

      <div className="flex justify-end space-x-3">
        <button
          type="button"
          onClick={onClose}
          className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
        >
          Annuler
        </button>
        <button
          type="submit"
          className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
        >
          Rembourser
        </button>
      </div>
    </form>
  );
}

function PaymentForm({ 
  onSubmit,
  onCancel,
  order
}: { 
  onSubmit: (data: PaymentFormData) => void;
  onCancel: () => void;
  order: Order;
}) {
  const { register, handleSubmit, formState: { errors }, watch } = useForm<PaymentFormData>({
    resolver: zodResolver(paymentSchema),
    defaultValues: {
      order_id: order.id,
      amount: order.total,
      method: 'cash'
    }
  });

  const amount = watch('amount');
  const excess = amount - order.total;

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 bg-white p-6 rounded-lg shadow">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-medium">Nouveau paiement</h3>
        <button
          type="button"
          onClick={onCancel}
          className="text-gray-400 hover:text-gray-500"
        >
          ×
        </button>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">
          Montant
        </label>
        <input
          type="number"
          step="0.01"
          {...register('amount', { valueAsNumber: true })}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
        />
        {errors.amount && (
          <p className="mt-1 text-sm text-red-600">{errors.amount.message}</p>
        )}
        {excess > 0 && (
          <p className="mt-1 text-sm text-blue-600">
            Un avoir de {formatPrice(excess)} sera créé
          </p>
        )}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">
          Méthode de paiement
        </label>
        <select
          {...register('method')}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
        >
          <option value="cash">Espèces</option>
          <option value="card">Carte bancaire</option>
          <option value="mobile">Paiement mobile</option>
        </select>
        {errors.method && (
          <p className="mt-1 text-sm text-red-600">{errors.method.message}</p>
        )}
      </div>

      <div className="flex justify-end space-x-3">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
        >
          Annuler
        </button>
        <button
          type="submit"
          className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
        >
          Valider le paiement
        </button>
      </div>
    </form>
  );
}

function Payments() {
  const [payments, setPayments] = React.useState<PaymentWithDetails[]>([]);
  const [pendingOrders, setPendingOrders] = React.useState<OrderWithDetails[]>([]);
  const [searchTerm, setSearchTerm] = React.useState('');
  const [selectedOrder, setSelectedOrder] = React.useState<OrderWithDetails | null>(null);
  const [showVoucherRefund, setShowVoucherRefund] = React.useState(false);

  const loadPayments = React.useCallback(async () => {
    try {
      // Charger les paiements
      const allPayments = await db.payments
        .orderBy('created_at')
        .reverse()
        .toArray();

      const paymentsWithDetails = await Promise.all(
        allPayments.map(async payment => {
          const order = await db.orders.get(payment.order_id);
          if (!order) return payment;

          const user = await db.users.get(order.user_id);
          
          return {
            ...payment,
            order,
            server_name: user?.username
          };
        })
      );

      const filtered = paymentsWithDetails.filter(payment =>
        payment.server_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        payment.order_id.toString().includes(searchTerm)
      );

      setPayments(filtered);

      // Charger les commandes approuvées sans paiement
      const approvedOrders = await db.orders
        .where('status')
        .equals('approved')
        .toArray();

      const ordersWithDetails = await Promise.all(
        approvedOrders.map(async order => {
          const user = await db.users.get(order.user_id);
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
            server_name: user?.username,
            items: itemsWithProducts
          };
        })
      );

      setPendingOrders(ordersWithDetails);
    } catch (error) {
      console.error('Error loading payments:', error);
      toast.error('Erreur lors du chargement des paiements');
    }
  }, [searchTerm]);

  React.useEffect(() => {
    loadPayments();
  }, [loadPayments]);

  const handleCreatePayment = async (data: PaymentFormData) => {
    try {
      // Calculer l'excédent
      const excess = data.amount - selectedOrder!.total;

      // Créer le paiement pour le montant de la commande
      await db.payments.add({
        order_id: data.order_id,
        amount: selectedOrder!.total,
        method: data.method,
        status: 'completed',
        created_at: new Date().toISOString()
      });

      // Mettre à jour le statut de la commande
      if (selectedOrder) {
        await db.orders.update(selectedOrder.id!, {
          status: 'completed'
        });

        let voucherData: Voucher | null = null;

        // Si il y a un excédent, créer un avoir
        if (excess > 0) {
          const code = Math.random().toString(36).substring(2, 8).toUpperCase();
          
          const voucherId = await db.vouchers.add({
            code,
            amount: excess,
            order_id: selectedOrder.id!,
            status: 'active',
            created_at: new Date().toISOString()
          });

          // Récupérer l'avoir créé
          voucherData = await db.vouchers.get(voucherId);
          
          toast.success(`Avoir de ${formatPrice(excess)} créé avec le code ${code}`);
        }

        // Imprimer le ticket
        const ticketContainer = document.createElement('div');
        ticketContainer.className = 'print-only';
        document.body.appendChild(ticketContainer);

        const root = createRoot(ticketContainer);
        root.render(
          <OrderTicket
            order={selectedOrder}
            items={selectedOrder.items}
            serverName={selectedOrder.server_name}
            voucher={voucherData}
          />
        );

        setTimeout(() => {
          window.print();
          root.unmount();
          document.body.removeChild(ticketContainer);
        }, 100);
      }

      toast.success('Paiement enregistré avec succès');
      setSelectedOrder(null);
      loadPayments();
    } catch (error) {
      console.error('Error creating payment:', error);
      toast.error('Erreur lors de l\'enregistrement du paiement');
    }
  };

  const methodLabels = {
    cash: 'Espèces',
    card: 'Carte bancaire',
    mobile: 'Paiement mobile'
  };

  const exportToPDF = async () => {
    try {
      const doc = new jsPDF();
      
      // Add title
      doc.setFontSize(16);
      doc.text('Historique des paiements', 14, 15);
      doc.setFontSize(12);

      // Prepare data for table
      const tableData = payments.map(payment => [
        new Date(payment.created_at).toLocaleString(),
        `#${payment.order_id}`,
        payment.server_name || '-',
        methodLabels[payment.method],
        formatPrice(payment.amount)
      ]);

      // Add table
      autoTable(doc, {
        head: [['Date', 'Commande', 'Serveur', 'Méthode', 'Montant']],
        body: tableData,
        startY: 25,
        styles: { fontSize: 10 },
        headStyles: { fillColor: [66, 139, 202] }
      });

      // Save PDF
      doc.save('paiements.pdf');
      toast.success('PDF exporté avec succès');
    } catch (error) {
      console.error('Error exporting to PDF:', error);
      toast.error('Erreur lors de l\'export PDF');
    }
  };

  const exportToExcel = async () => {
    try {
      // Prepare data
      const data = payments.map(payment => ({
        'Date': new Date(payment.created_at).toLocaleString(),
        'N° Commande': `#${payment.order_id}`,
        'Serveur': payment.server_name || '-',
        'Méthode': methodLabels[payment.method],
        'Montant': formatPrice(payment.amount)
      }));

      // Create worksheet
      const ws = XLSX.utils.json_to_sheet(data);
      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, 'Paiements');

      // Save file
      XLSX.writeFile(wb, 'paiements.xlsx');
      toast.success('Excel exporté avec succès');
    } catch (error) {
      console.error('Error exporting to Excel:', error);
      toast.error('Erreur lors de l\'export Excel');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold text-gray-900">Paiements</h1>
        <div className="flex space-x-2">
          <button
            onClick={exportToPDF}
            className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
          >
            <FileDown className="h-5 w-5 inline-block mr-2" />
            Exporter PDF
          </button>
          <button
            onClick={exportToExcel}
            className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
          >
            <FileSpreadsheet className="h-5 w-5 inline-block mr-2" />
            Exporter Excel
          </button>
          <button
            onClick={() => setShowVoucherRefund(true)}
            className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
          >
            <Ticket className="h-5 w-5 inline-block mr-2" />
            Rembourser un avoir
          </button>
        </div>
      </div>

      <div className="flex justify-between items-center bg-white p-4 rounded-lg shadow">
        <div className="relative flex-1 max-w-xs">
          <input
            type="text"
            placeholder="Rechercher par serveur ou numéro de commande..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
          />
          <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <Search className="h-5 w-5 text-gray-400" />
          </div>
        </div>
      </div>

      {/* Commandes en attente de paiement */}
      {pendingOrders.length > 0 && (
        <div className="bg-white shadow rounded-lg p-6">
          <h2 className="text-lg font-medium mb-4">Commandes en attente de paiement</h2>
          <div className="space-y-4">
            {pendingOrders.map(order => (
              <div key={order.id} className="flex items-center justify-between p-4 border rounded-lg">
                <div>
                  <p className="font-medium">Commande #{order.id}</p>
                  <p className="text-sm text-gray-500">Serveur: {order.server_name}</p>
                  <p className="text-sm text-gray-500">
                    Date: {new Date(order.created_at).toLocaleString()}
                  </p>
                  <p className="font-medium text-lg mt-1">{formatPrice(order.total)}</p>
                </div>
                <div className="flex items-center space-x-2">
                  <button
                    onClick={() => setSelectedOrder(order)}
                    className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
                  >
                    Encaisser
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {selectedOrder && (
        <PaymentForm
          onSubmit={handleCreatePayment}
          onCancel={() => setSelectedOrder(null)}
          order={selectedOrder}
        />
      )}

      {showVoucherRefund && (
        <VoucherRefundForm onClose={() => setShowVoucherRefund(false)} />
      )}

      <div className="bg-white shadow rounded-lg">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Date
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Commande
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Serveur
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Méthode
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Montant
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {payments.map((payment) => (
              <tr key={payment.id}>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {new Date(payment.created_at).toLocaleString()}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  #{payment.order_id}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {payment.server_name}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="flex items-center text-sm text-gray-500">
                    <PaymentMethodIcon method={payment.method} />
                    <span className="ml-2">{methodLabels[payment.method]}</span>
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right font-medium text-gray-900">
                  {formatPrice(payment.amount)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default Payments;