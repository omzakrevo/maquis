import React from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { BarChart3, Calendar, FileDown, FileSpreadsheet, TrendingUp } from 'lucide-react';
import toast from 'react-hot-toast';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import * as XLSX from 'xlsx';
import db from '../lib/db';
import type { Order, OrderItem, Product } from '../lib/db';

const formatPrice = (amount: number) => `${amount.toLocaleString('fr-FR')} FCFA`;

const periodSchema = z.object({
  type: z.enum(['daily', 'monthly', 'yearly']),
  date: z.string()
});

type PeriodFormData = z.infer<typeof periodSchema>;

interface SalesReport {
  totalRevenue: number;
  totalOrders: number;
  averageOrderValue: number;
  topProducts: {
    id: number;
    name: string;
    quantity: number;
    revenue: number;
  }[];
  paymentMethods: {
    method: string;
    count: number;
    amount: number;
  }[];
}

function Reports() {
  const [report, setReport] = React.useState<SalesReport | null>(null);
  const [period, setPeriod] = React.useState<'daily' | 'monthly' | 'yearly'>('daily');
  const [selectedDate, setSelectedDate] = React.useState(new Date().toISOString().split('T')[0]);

  const generateReport = async () => {
    try {
      let startDate: Date;
      let endDate: Date;
      const selectedDateTime = new Date(selectedDate);

      switch (period) {
        case 'daily':
          startDate = new Date(selectedDateTime.setHours(0, 0, 0, 0));
          endDate = new Date(selectedDateTime.setHours(23, 59, 59, 999));
          break;
        case 'monthly':
          startDate = new Date(selectedDateTime.getFullYear(), selectedDateTime.getMonth(), 1);
          endDate = new Date(selectedDateTime.getFullYear(), selectedDateTime.getMonth() + 1, 0, 23, 59, 59, 999);
          break;
        case 'yearly':
          startDate = new Date(selectedDateTime.getFullYear(), 0, 1);
          endDate = new Date(selectedDateTime.getFullYear(), 11, 31, 23, 59, 59, 999);
          break;
      }

      // Récupérer les commandes de la période
      const orders = await db.orders
        .where('created_at')
        .between(startDate.toISOString(), endDate.toISOString())
        .filter(order => order.status === 'completed')
        .toArray();

      // Récupérer tous les items des commandes
      const orderItems: (OrderItem & { product?: Product })[] = [];
      for (const order of orders) {
        const items = await db.orderItems
          .where('order_id')
          .equals(order.id!)
          .toArray();
        
        // Ajouter les informations du produit
        for (const item of items) {
          const product = await db.products.get(item.product_id);
          orderItems.push({ ...item, product });
        }
      }

      // Récupérer les paiements de la période
      const payments = await db.payments
        .where('created_at')
        .between(startDate.toISOString(), endDate.toISOString())
        .toArray();

      // Calculer les statistiques
      const totalRevenue = orders.reduce((sum, order) => sum + order.total, 0);
      const averageOrderValue = totalRevenue / orders.length || 0;

      // Calculer les produits les plus vendus
      const productStats = orderItems.reduce((acc, item) => {
        const key = item.product_id;
        if (!acc[key]) {
          acc[key] = {
            id: item.product_id,
            name: item.product?.name || 'Produit inconnu',
            quantity: 0,
            revenue: 0
          };
        }
        acc[key].quantity += item.quantity;
        acc[key].revenue += item.price * item.quantity;
        return acc;
      }, {} as Record<number, { id: number; name: string; quantity: number; revenue: number }>);

      const topProducts = Object.values(productStats)
        .sort((a, b) => b.revenue - a.revenue)
        .slice(0, 10);

      // Calculer les statistiques par méthode de paiement
      const paymentMethods = payments.reduce((acc, payment) => {
        const key = payment.method;
        if (!acc[key]) {
          acc[key] = { method: key, count: 0, amount: 0 };
        }
        acc[key].count++;
        acc[key].amount += payment.amount;
        return acc;
      }, {} as Record<string, { method: string; count: number; amount: number }>);

      setReport({
        totalRevenue,
        totalOrders: orders.length,
        averageOrderValue,
        topProducts,
        paymentMethods: Object.values(paymentMethods)
      });
    } catch (error) {
      console.error('Error generating report:', error);
      toast.error('Erreur lors de la génération du rapport');
    }
  };

  React.useEffect(() => {
    generateReport();
  }, [period, selectedDate]);

  const exportToPDF = () => {
    if (!report) return;

    try {
      const doc = new jsPDF();
      
      // Titre
      doc.setFontSize(16);
      doc.text(`Rapport ${period === 'daily' ? 'journalier' : period === 'monthly' ? 'mensuel' : 'annuel'}`, 14, 15);
      doc.setFontSize(12);
      doc.text(`Période: ${new Date(selectedDate).toLocaleDateString()}`, 14, 25);

      // Statistiques générales
      doc.text('Statistiques générales', 14, 35);
      autoTable(doc, {
        body: [
          ['Chiffre d\'affaires', formatPrice(report.totalRevenue)],
          ['Nombre de commandes', report.totalOrders.toString()],
          ['Panier moyen', formatPrice(report.averageOrderValue)]
        ],
        startY: 40,
        theme: 'grid'
      });

      // Produits les plus vendus
      doc.text('Top 10 des produits', 14, doc.lastAutoTable.finalY + 10);
      autoTable(doc, {
        head: [['Produit', 'Quantité', 'Chiffre d\'affaires']],
        body: report.topProducts.map(product => [
          product.name,
          product.quantity.toString(),
          formatPrice(product.revenue)
        ]),
        startY: doc.lastAutoTable.finalY + 15,
        theme: 'striped'
      });

      // Méthodes de paiement
      doc.text('Méthodes de paiement', 14, doc.lastAutoTable.finalY + 10);
      autoTable(doc, {
        head: [['Méthode', 'Nombre', 'Montant']],
        body: report.paymentMethods.map(method => [
          method.method === 'cash' ? 'Espèces' : method.method === 'card' ? 'Carte' : 'Mobile',
          method.count.toString(),
          formatPrice(method.amount)
        ]),
        startY: doc.lastAutoTable.finalY + 15,
        theme: 'striped'
      });

      doc.save(`rapport-${period}-${selectedDate}.pdf`);
      toast.success('PDF exporté avec succès');
    } catch (error) {
      console.error('Error exporting to PDF:', error);
      toast.error('Erreur lors de l\'export PDF');
    }
  };

  const exportToExcel = () => {
    if (!report) return;

    try {
      const wb = XLSX.utils.book_new();

      // Statistiques générales
      const statsData = [
        ['Statistiques générales'],
        ['Chiffre d\'affaires', formatPrice(report.totalRevenue)],
        ['Nombre de commandes', report.totalOrders],
        ['Panier moyen', formatPrice(report.averageOrderValue)]
      ];
      const statsWs = XLSX.utils.aoa_to_sheet(statsData);
      XLSX.utils.book_append_sheet(wb, statsWs, 'Statistiques');

      // Produits les plus vendus
      const productsData = [
        ['Produit', 'Quantité', 'Chiffre d\'affaires'],
        ...report.topProducts.map(product => [
          product.name,
          product.quantity,
          formatPrice(product.revenue)
        ])
      ];
      const productsWs = XLSX.utils.aoa_to_sheet(productsData);
      XLSX.utils.book_append_sheet(wb, productsWs, 'Top Produits');

      // Méthodes de paiement
      const paymentsData = [
        ['Méthode', 'Nombre', 'Montant'],
        ...report.paymentMethods.map(method => [
          method.method === 'cash' ? 'Espèces' : method.method === 'card' ? 'Carte' : 'Mobile',
          method.count,
          formatPrice(method.amount)
        ])
      ];
      const paymentsWs = XLSX.utils.aoa_to_sheet(paymentsData);
      XLSX.utils.book_append_sheet(wb, paymentsWs, 'Paiements');

      XLSX.writeFile(wb, `rapport-${period}-${selectedDate}.xlsx`);
      toast.success('Excel exporté avec succès');
    } catch (error) {
      console.error('Error exporting to Excel:', error);
      toast.error('Erreur lors de l\'export Excel');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold text-gray-900">Rapports</h1>
        <div className="flex space-x-2">
          <button
            onClick={exportToPDF}
            disabled={!report}
            className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50"
          >
            <FileDown className="h-5 w-5 inline-block mr-2" />
            Exporter PDF
          </button>
          <button
            onClick={exportToExcel}
            disabled={!report}
            className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50"
          >
            <FileSpreadsheet className="h-5 w-5 inline-block mr-2" />
            Exporter Excel
          </button>
        </div>
      </div>

      <div className="bg-white shadow rounded-lg p-6">
        <div className="flex space-x-4 mb-6">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Période
            </label>
            <select
              value={period}
              onChange={(e) => setPeriod(e.target.value as 'daily' | 'monthly' | 'yearly')}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
            >
              <option value="daily">Journalier</option>
              <option value="monthly">Mensuel</option>
              <option value="yearly">Annuel</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Date
            </label>
            <input
              type={period === 'yearly' ? 'number' : 'date'}
              value={period === 'yearly' ? selectedDate.split('-')[0] : selectedDate}
              onChange={(e) => {
                if (period === 'yearly') {
                  setSelectedDate(`${e.target.value}-01-01`);
                } else {
                  setSelectedDate(e.target.value);
                }
              }}
              min={period === 'yearly' ? '2000' : undefined}
              max={period === 'yearly' ? '2100' : undefined}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
            />
          </div>
        </div>

        {report && (
          <div className="space-y-6">
            {/* Statistiques générales */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="bg-blue-50 p-4 rounded-lg">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-medium text-blue-900">Chiffre d'affaires</h3>
                  <TrendingUp className="h-5 w-5 text-blue-500" />
                </div>
                <p className="mt-2 text-2xl font-semibold text-blue-900">
                  {formatPrice(report.totalRevenue)}
                </p>
              </div>
              <div className="bg-green-50 p-4 rounded-lg">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-medium text-green-900">Commandes</h3>
                  <BarChart3 className="h-5 w-5 text-green-500" />
                </div>
                <p className="mt-2 text-2xl font-semibold text-green-900">
                  {report.totalOrders}
                </p>
              </div>
              <div className="bg-purple-50 p-4 rounded-lg">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-medium text-purple-900">Panier moyen</h3>
                  <Calendar className="h-5 w-5 text-purple-500" />
                </div>
                <p className="mt-2 text-2xl font-semibold text-purple-900">
                  {formatPrice(report.averageOrderValue)}
                </p>
              </div>
            </div>

            {/* Top produits */}
            <div>
              <h2 className="text-lg font-medium text-gray-900 mb-4">Top 10 des produits</h2>
              <div className="bg-white border rounded-lg overflow-hidden">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Produit
                      </th>
                      <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Quantité
                      </th>
                      <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Chiffre d'affaires
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {report.topProducts.map((product) => (
                      <tr key={product.id}>
                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                          {product.name}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-500">
                          {product.quantity}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-right font-medium text-gray-900">
                          {formatPrice(product.revenue)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Méthodes de paiement */}
            <div>
              <h2 className="text-lg font-medium text-gray-900 mb-4">Méthodes de paiement</h2>
              <div className="bg-white border rounded-lg overflow-hidden">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Méthode
                      </th>
                      <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Nombre
                      </th>
                      <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Montant
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {report.paymentMethods.map((method) => (
                      <tr key={method.method}>
                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                          {method.method === 'cash' ? 'Espèces' : method.method === 'card' ? 'Carte' : 'Mobile'}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-500">
                          {method.count}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-right font-medium text-gray-900">
                          {formatPrice(method.amount)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default Reports;