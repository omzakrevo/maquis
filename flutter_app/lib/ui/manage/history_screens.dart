import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../printing/ticket_builder.dart';
import '../common.dart';
import '../ticket_preview.dart';
import '../theme.dart';

const _actionLabels = {
  'login': 'Connexion',
  'login_failed': 'PIN erroné',
  'pin_change': 'PIN changé',
  'pin_reset': 'PIN réinitialisé',
  'user_create': 'Employé créé',
  'user_update': 'Employé modifié',
  'product_create': 'Produit créé',
  'product_update': 'Produit modifié',
  'stock_adjust': 'Ajustement de stock',
  'table_create': 'Table créée',
  'table_update': 'Table modifiée',
  'order_create': 'Commande créée',
  'order_add_items': 'Articles ajoutés',
  'order_cancel': 'Commande annulée',
  'cash_open': 'Ouverture de caisse',
  'cash_close': 'Clôture de caisse',
  'payment': 'Encaissement',
  'credit_issue': 'Avoir émis',
  'credit_cancel': 'Avoir annulé',
  'settings_update': 'Paramètres modifiés',
  'products_import': 'Import Excel des produits',
};

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  List<AuditEntry> entries = [];
  int pending = 0;
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final e = await repo.auditLog();
    final p = await repo.pendingSyncEvents();
    if (!mounted) return;
    setState(() {
      entries = e;
      pending = p;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: gradientAppBar(context, title: const Text('Journal d\'activité')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: Text('$pending événement(s) en attente de synchronisation'),
                    subtitle: const Text('La synchronisation cloud arrivera avec le serveur local.'),
                  ),
                ),
                for (final e in entries)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      e.action.contains('cancel') || e.action == 'login_failed' ? Icons.warning_amber : Icons.history,
                      color: e.action.contains('cancel') || e.action == 'login_failed' ? cs.error : cs.outline,
                    ),
                    title: Text('${_actionLabels[e.action] ?? e.action}${e.userName != null ? ' · ${e.userName}' : ''}'),
                    subtitle: Text('${dateTimeOf(e.createdAt)}${e.details != null ? ' · ${e.details}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
    );
  }
}

class OrdersHistoryScreen extends StatefulWidget {
  const OrdersHistoryScreen({super.key});
  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  List<OrderSummary> orders = [];
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final o = await AppScope.read(context).repo.recentOrders(limit: 200);
    if (!mounted) return;
    setState(() {
      orders = o;
      loading = false;
    });
  }

  Future<void> _receipt(OrderSummary o) async {
    final repo = AppScope.read(context).repo;
    final d = await repo.orderDetail(o.id);
    final shop = await repo.shopInfo();
    if (mounted) await showTicket(context, customerReceipt(shop, d));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String label(String s) => switch (s) {
      'open' => 'En cours',
      'closed' => 'Soldée',
      _ => 'Annulée',
    };
    return Scaffold(
      appBar: gradientAppBar(context, title: const Text('Historique des commandes')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (orders.isEmpty) const EmptyState(Icons.receipt_long, 'Aucune commande.'),
                for (final o in orders)
                  Card(
                    child: ListTile(
                      title: Text('N° ${o.number} · ${o.tableLabel}'),
                      subtitle: Text('${dateTimeOf(o.createdAt)} · ${label(o.status)}${o.serverName != null ? ' · ${o.serverName}' : ''}'),
                      trailing: Text(
                        fcfa(o.total),
                        style: TextStyle(fontWeight: FontWeight.w800, decoration: o.status == 'cancelled' ? TextDecoration.lineThrough : null, color: o.status == 'cancelled' ? cs.outline : null),
                      ),
                      onTap: () => _receipt(o),
                    ),
                  ),
              ],
            ),
    );
  }
}
