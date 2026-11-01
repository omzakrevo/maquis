import 'package:flutter/material.dart';

import '../core/permissions.dart';
import '../data/models.dart';
import 'cash_screen.dart';
import 'common.dart';
import 'credits_screen.dart';
import 'login_screen.dart';
import 'manage/about_screen.dart';
import 'manage/history_screens.dart';
import 'manage/products_screen.dart';
import 'manage/profit_screen.dart';
import 'manage/server_sales_screen.dart';
import 'manage/settings_screen.dart';
import 'manage/stock_history_screen.dart';
import 'manage/stock_screen.dart';
import 'manage/tables_screen.dart';
import 'manage/users_screen.dart';
import 'order_screen.dart';
import 'orders_screen.dart';
import 'scan_screen.dart';
import 'theme.dart';
import 'motion.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  int version = 0; // force le rechargement des listes après un scan ou un envoi
  BusinessMode mode = BusinessMode.restaurant;
  bool _modeLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_modeLoaded) {
      _modeLoaded = true;
      _loadMode();
    }
  }

  Future<void> _loadMode() async {
    final m = await AppScope.read(context).repo.businessMode();
    if (mounted && m != mode) setState(() => mode = m);
  }

  void _select(int i) {
    setState(() => index = i);
    _loadMode(); // le type d'établissement a pu changer dans Paramètres
  }

  List<_Dest> _destinations(AppUser u) => [
    if (u.can(Permission.takeOrders))
      mode.directSale
          ? _Dest(
              'Vente',
              Brand.pharmacy ? Icons.local_pharmacy_outlined : Icons.storefront_outlined,
              Brand.pharmacy ? Icons.local_pharmacy : Icons.storefront,
              () => OrderScreen(key: const ValueKey('shop'), onSent: () => setState(() => version++)),
            )
          : _Dest('Commande', Icons.restaurant_menu_outlined, Icons.restaurant_menu, () => OrderScreen(key: const ValueKey('resto'), onSent: () => setState(() => version++))),
    if (u.can(Permission.takeOrders)) _Dest(mode.directSale ? 'En attente' : 'En cours', Icons.receipt_long_outlined, Icons.receipt_long, () => OpenOrdersScreen(key: ValueKey('orders$version'))),
    if (u.can(Permission.manageCashSession) || u.can(Permission.viewReports)) _Dest('Caisse', Icons.point_of_sale_outlined, Icons.point_of_sale, () => CashScreen(key: ValueKey('cash$version'))),
    if (u.can(Permission.takePayments)) _Dest('Avoirs', Icons.confirmation_number_outlined, Icons.confirmation_number, () => const CreditsScreen()),
    if (_canManage(u)) _Dest('Gestion', Icons.settings_outlined, Icons.settings, () => const ManageScreen()),
  ];

  bool _canManage(AppUser u) => [Permission.manageCatalog, Permission.manageStock, Permission.manageTables, Permission.manageUsers, Permission.manageSettings, Permission.viewAudit].any(u.can);

  Future<void> _scan() async {
    await scanAndOpen(
      context,
      onChanged: () {
        if (mounted) setState(() => version++);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final u = scope.user;
    final dests = _destinations(u);
    if (index >= dests.length) index = 0;
    final wide = isWide(context);
    final body = PatternBackground(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey('tab$index-${u.id}'), child: dests[index].builder()),
      ),
    );
    return Scaffold(
      appBar: gradientAppBar(
        context,
        title: Text(dests[index].label),
        actions: [
          if (u.can(Permission.takeOrders))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: isCompact(context)
                  ? IconButton.filled(tooltip: 'Scanner un ticket', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner))
                  : FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: Text(wide ? 'Scanner un ticket' : 'Scanner')),
            ),
          if (wide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '${u.name} · ${u.role.label}',
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.gold,
              child: Text(
                u.name.isEmpty ? '?' : u.name[0].toUpperCase(),
                style: TextStyle(color: AppColors.brick, fontWeight: FontWeight.w900),
              ),
            ),
            onSelected: (v) {
              if (v == 'pin') Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePinScreen(forced: false)));
              if (v == 'lock') scope.session.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${u.name} · ${u.role.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const PopupMenuItem(
                value: 'pin',
                child: ListTile(leading: Icon(Icons.password), title: Text('Changer mon PIN')),
              ),
              const PopupMenuItem(
                value: 'lock',
                child: ListTile(leading: Icon(Icons.lock), title: Text('Verrouiller / changer d\'utilisateur')),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: _select,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(Brand.logo, width: 44, height: 44)),
                  ),
                  destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label))],
                ),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide || dests.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: _select,
              destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)],
            ),
    );
  }
}

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppScope.of(context).user;
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final direct = AppColors.mode.directSale;
    final tiles = <(Permission?, IconData, Color, String, String, Widget Function())>[
      Brand.pharmacy
          ? (Permission.manageCatalog, Icons.medication, const Color(0xFFD9480F), 'Médicaments et prix', 'Prix de vente et d\'achat, code-barres', () => const ProductsScreen())
          : (
              Permission.manageCatalog,
              Icons.local_offer,
              const Color(0xFFD9480F),
              'Produits et prix',
              direct ? 'Prix, code-barres, photos' : 'Photos, catégories, bar/cuisine',
              () => const ProductsScreen(),
            ),
      (Permission.manageStock, Icons.inventory_2, const Color(0xFF2F9E44), 'Stocks', 'Entrées, sorties, inventaire, alertes', () => const StockScreen()),
      (Permission.manageStock, Icons.history_edu, const Color(0xFF0B7285), 'Historique des stocks', 'Qui a fait quelle entrée, quand', () => const StockHistoryScreen()),
      if (!direct) (Permission.manageTables, Icons.table_restaurant, const Color(0xFF862E9C), 'Tables', 'Salle, terrasse, VIP', () => const TablesScreen()),
      (Permission.manageUsers, Icons.groups, const Color(0xFF364FC7), 'Employés', 'Comptes, rôles, PIN', () => const UsersScreen()),
      direct
          ? (Permission.viewReports, Icons.groups_2, const Color(0xFFE67700), 'Ventes par vendeur', 'Ventes et chiffre d\'affaires par employé', () => const ServerSalesScreen())
          : (Permission.viewReports, Icons.groups_2, const Color(0xFFE67700), 'Ventes par serveuse', 'Bouteilles, chiffre d\'affaires, primes du mois', () => const ServerSalesScreen()),
      (Permission.viewReports, Icons.trending_up, const Color(0xFF2F9E44), 'Marges et bénéfices', 'Prix d\'achat, bénéfice, valeur du stock', () => const ProfitScreen()),
      (Permission.viewReports, Icons.receipt_long, const Color(0xFFE67700), 'Historique des commandes', 'Réimpression des reçus', () => const OrdersHistoryScreen()),
      (Permission.manageSettings, Icons.print, const Color(0xFF7A1A0C), 'Paramètres et imprimante', 'Établissement, réseau ou Bluetooth', () => const SettingsScreen()),
      (Permission.viewAudit, Icons.manage_search, const Color(0xFF495057), 'Journal d\'activité', 'Qui a fait quoi, quand', () => const AuditScreen()),
      (null, Icons.info, const Color(0xFFF59F00), 'À propos', 'Version, crédits des photos', () => const AboutScreen()),
    ];
    final visible = tiles.where((t) => t.$1 == null || u.can(t.$1!)).toList();
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 620 ? 2 : 1);
        return GridView.builder(
          padding: EdgeInsets.all(c.maxWidth < 420 ? 10 : 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: c.maxWidth < 420 ? 80 : 92, crossAxisSpacing: 12, mainAxisSpacing: c.maxWidth < 420 ? 8 : 12),
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final t = visible[i];
            return FadeSlideIn(
              index: i,
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => open(t.$6()),
                  child: Padding(
                    padding: EdgeInsets.all(c.maxWidth < 420 ? 10 : 14),
                    child: Row(
                      children: [
                        Container(
                          width: c.maxWidth < 420 ? 44 : 56,
                          height: c.maxWidth < 420 ? 44 : 56,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: AppColors.orange.withValues(alpha: 0.10)),
                          child: Icon(t.$2, color: AppColors.orange, size: 26),
                        ),
                        SizedBox(width: c.maxWidth < 420 ? 10 : 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.$4,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              Text(
                                t.$5,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, height: 1.2),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
