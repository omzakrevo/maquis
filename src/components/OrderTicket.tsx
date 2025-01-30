import React from 'react';
import type { Order, OrderItem, Voucher } from '../lib/db';
import { useEffect, useState } from 'react';
import db from '../lib/db';

interface OrderTicketProps {
  order: Order;
  items: (OrderItem & { product_name?: string })[];
  serverName?: string;
  voucher?: Voucher | null;
}

const formatPrice = (amount: number | undefined) => {
  if (typeof amount !== 'number') return '0 FCFA';
  return `${amount.toLocaleString('fr-FR')} FCFA`;
};

const OrderTicket = React.forwardRef<HTMLDivElement, OrderTicketProps>(
  ({ order, items, serverName, voucher }, ref) => {
    const [settings, setSettings] = useState({ name: '', phone: '' });

    useEffect(() => {
      async function loadSettings() {
        const allSettings = await db.settings.toArray();
        const currentSettings = allSettings[0];
        if (currentSettings) {
          setSettings({
            name: currentSettings.name,
            phone: currentSettings.phone
          });
        }
      }
      loadSettings();
    }, []);

    return (
      <div ref={ref} className="bg-white p-8 max-w-sm mx-auto">
        <div className="text-center mb-6">
          <h1 className="text-2xl font-bold">{settings.name}</h1>
          <p className="text-sm text-gray-600">{settings.phone}</p>
          <p className="text-sm text-gray-600 mt-2">Ticket de commande</p>
        </div>

        <div className="mb-4">
          <p className="text-sm">Commande #{order.id}</p>
          <p className="text-sm">Date: {new Date(order.created_at).toLocaleString()}</p>
          <p className="text-sm">Serveur: {serverName}</p>
        </div>

        <div className="border-t border-b border-gray-200 py-4 mb-4">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b">
                <th className="text-left py-2">Article</th>
                <th className="text-center py-2">Qté</th>
                <th className="text-right py-2">Prix</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item) => (
                <tr key={item.id}>
                  <td className="py-1">{item.product_name}</td>
                  <td className="text-center">{item.quantity}</td>
                  <td className="text-right">{formatPrice(item.price * item.quantity)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="text-right mb-6">
          <p className="text-lg font-bold">Total: {formatPrice(order.total)}</p>
          {voucher && voucher.amount > 0 && (
            <div className="mt-4 p-3 bg-blue-50 rounded-lg">
              <h3 className="text-sm font-semibold text-blue-800 mb-1">Avoir créé</h3>
              <p className="text-lg font-bold text-blue-900">{formatPrice(voucher.amount)}</p>
              <p className="text-sm font-medium text-blue-800 mt-1">Code: {voucher.code}</p>
            </div>
          )}
        </div>

        <div className="text-center text-sm text-gray-600">
          <p>Merci de votre visite!</p>
          <p className="mt-1">{settings.name}</p>
        </div>
      </div>
    );
  }
);

OrderTicket.displayName = 'OrderTicket';

export default OrderTicket;