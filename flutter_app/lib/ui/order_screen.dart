import 'dart:async';

import 'package:flutter/material.dart';

import '../core/hardware_scanner.dart';
import '../core/money.dart';
import '../core/permissions.dart';
import '../data/models.dart';
import '../data/pos_repository.dart' show normalizeBarcode;
import '../printing/ticket_builder.dart';
import 'common.dart';
import 'orders_screen.dart' show runPaymentFlow;
import 'scan_screen.dart';
import 'ticket_preview.dart';
import 'theme.dart';
import 'motion.dart';

/// Prise de commande. Sans [target] : nouvelle commande.
/// Avec [target] : ajout d'articles à une commande ouverte.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, this.target, this.onSent});
  final OrderSummary? target;
  final VoidCallback? onSent;
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List<Product> products = [];
  List<DiningTable> tables = [];
  List<AppUser> staff = [];
  String? serverId; // serveuse choisie par la caisse (null = soi-même)
  String? category;
  String search = '';
  String tableLabel = 'Comptoir';
  final note = TextEditingController();
  final Map<String, CartLine> cart = {};
  bool loading = true;
  bool sending = false;
  BusinessMode mode = BusinessMode.restaurant;
  bool get shop => mode.directSale && widget.target == null;
  // Une vendeuse (rôle serveur) n'encaisse pas : elle envoie la vente à la caisse.
  bool get canPay => AppScope.of(context).user.can(Permission.takePayments);
  final searchCtrl = TextEditingController();
  final searchFocus = FocusNode();
  // Retour du scan affiché sous la recherche (un toast masquerait le total et « Encaisser »).
  String? scanMessage;
  bool scanError = false;
  int _scanSeq = 0;

  void _feedback(String message, {bool error = false}) {
    final seq = ++_scanSeq;
    setState(() {
      scanMessage = message;
      scanError = error;
    });
    Future.delayed(Duration(seconds: error ? 5 : 3), () {
      if (mounted && seq == _scanSeq) setState(() => scanMessage = null);
    });
  }

  bool builtinScan = false;
  StreamSubscription<String>? _hwSub;

  @override
  void initState() {
    super.initState();
    // Bouton physique du lecteur intégré : le produit s'ajoute sans ouvrir d'écran de scan.
    _hwSub = HardwareScanner.results.listen((code) {
      if (!mounted || HardwareScanner.exclusive || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (_addByCode(code)) return;
      if (RegExp(r'^\d{6,}$').hasMatch(code)) _feedback('Code inconnu : $code — ajoutez-le à la fiche produit', error: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = await repo.products();
    final t = await repo.tables();
    final u = await repo.users();
    final m = await repo.businessMode();
    final hw = await useBuiltinScanner((await repo.settings())['scan_source']);
    if (!mounted) return;
    setState(() {
      mode = m;
      builtinScan = hw;
      products = p;
      tables = t;
      staff = u;
      if (serverId != null && !u.any((x) => x.id == serverId)) serverId = null;
      loading = false;
    });
  }

  List<String> get categories => products.map((p) => p.category).toSet().toList();
  List<Product> get visible => products.where((p) => category == null || p.category == category).where((p) => search.isEmpty || p.name.toLowerCase().contains(search.toLowerCase())).toList();
  int get total => cart.values.fold(0, (a, l) => a + l.total);
  int get count => cart.values.fold(0, (a, l) => a + l.quantity);

  void _add(Product p, [int delta = 1]) {
    setState(() {
      final line = cart.putIfAbsent(p.id, () => CartLine(p, 0));
      line.quantity += delta;
      if (line.quantity <= 0) cart.remove(p.id);
    });
  }

  String _serverName(AppUser me) {
    for (final u in staff) {
      if (u.id == serverId) return u.name;
    }
    return me.name;
  }

  /// Code lu par la douchette (saisie + Entrée) ou la caméra : ajoute le produit au panier.
  bool _addByCode(String raw) {
    var code = raw.trim();
    if (code.toUpperCase().startsWith('PRD:')) code = code.substring(4);
    final c = normalizeBarcode(code);
    if (c == null) return false;
    for (final p in products) {
      if (p.barcode == c) {
        _add(p);
        _feedback('+1  ${p.name} · ${fcfa(p.price)}');
        return true;
      }
    }
    return false;
  }

  void _onSearchSubmitted(String v) {
    final text = v.trim();
    if (text.isEmpty) return;
    if (_addByCode(text)) {
      searchCtrl.clear();
      setState(() => search = '');
    } else if (visible.length == 1) {
      _add(visible.first);
      searchCtrl.clear();
      setState(() => search = '');
    } else if (RegExp(r'^\d{6,}$').hasMatch(text)) {
      _feedback('Code inconnu : $text — ajoutez-le à la fiche produit', error: true);
      searchCtrl.clear();
      setState(() => search = '');
    }
    searchFocus.requestFocus();
  }

  Future<void> _scanWithCamera() async {
    if (builtinScan) {
      // Lecteur intégré : on l'allume, le code lu arrive par le flux ci-dessus.
      final r = await HardwareScanner.start();
      if (mounted) _feedback(r.triggered ? 'Lecteur allumé : présentez le code-barres' : 'Lecteur non allumé (${r.error ?? r.method}). Bouton de scan du terminal ou caméra.', error: !r.triggered);
      return;
    }
    final v = await scanCode(context, title: 'Scanner un produit');
    if (v == null || !mounted) return;
    if (!_addByCode(v)) _feedback('Code inconnu : $v — ajoutez-le à la fiche produit', error: true);
  }

  /// Vente directe : crée la commande et ouvre tout de suite l'encaissement.
  Future<void> _checkout() async {
    if (cart.isEmpty || sending) return;
    final scope = AppScope.read(context);
    if (await scope.repo.currentSession() == null) {
      if (mounted) toast(context, 'Ouvrez la caisse (onglet Caisse) avant d\'encaisser', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => sending = true);
    final lines = cart.values.toList();
    final label = shop ? 'Vente directe' : tableLabel;
    final noteText = shop ? null : note.text;
    final orderId = await guard(context, () => scope.repo.createOrder(scope.user, tableLabel: label, lines: lines, note: noteText, serverId: shop ? null : serverId));
    if (!mounted) return;
    setState(() => sending = false);
    if (orderId == null) return;
    setState(() {
      cart.clear();
      note.clear();
    });
    final detail = await scope.repo.orderDetail(orderId);
    if (!mounted) return;
    if (!shop) {
      final ps = await scope.repo.printerSettings();
      if (ps.afterOrder.preparation && ps.configured) {
        for (final e in splitByStation(lines).entries) {
          if (!mounted) return;
          await printOrPreview(
            context,
            preparationTicket(station: e.key, orderNumber: detail.summary.number, tableLabel: detail.summary.tableLabel, lines: e.value, note: noteText, serverName: _serverName(scope.user)),
          );
        }
      }
    }
    if (!mounted) return;
    final paid = await runPaymentFlow(context, detail.summary);
    if (!mounted) return;
    if (!paid) toast(context, 'Non encaissée : la vente N° ${detail.summary.number} attend dans « Commandes »');
    await _load();
    widget.onSent?.call();
    if (shop) searchFocus.requestFocus();
  }

  Future<void> _send() async {
    if (cart.isEmpty || sending) return;
    setState(() => sending = true);
    final scope = AppScope.read(context);
    final lines = cart.values.toList();
    final target = widget.target;
    final orderId = await guard(context, () async {
      if (target == null) {
        return scope.repo.createOrder(scope.user, tableLabel: this.shop ? 'Vente directe' : tableLabel, lines: lines, note: this.shop ? null : note.text, serverId: this.shop ? null : serverId);
      }
      await scope.repo.addItems(scope.user, target.id, lines);
      return target.id;
    });
    if (!mounted) return;
    setState(() => sending = false);
    if (orderId == null) return;
    final detail = await scope.repo.orderDetail(orderId);
    if (!mounted) return;
    await showSuccessCheck(context, target == null ? 'Commande envoyée' : 'Articles ajoutés', detail: 'N° ${detail.summary.number} · ${detail.summary.tableLabel}');
    if (!mounted) return;
    // Impression après validation (réglable dans Paramètres) :
    // ticket client avec prix + QR, et/ou bons de préparation bar/cuisine.
    final ps = await scope.repo.printerSettings();
    final shop = await scope.repo.shopInfo();
    if (!mounted) return;
    if (ps.afterOrder.clientTicket) {
      await printOrPreview(context, orderTicket(shop, detail));
    }
    if (ps.afterOrder.preparation && ps.configured) {
      for (final e in splitByStation(lines).entries) {
        final t = preparationTicket(
          station: e.key,
          orderNumber: detail.summary.number,
          tableLabel: detail.summary.tableLabel,
          lines: e.value,
          note: target == null ? note.text : null,
          serverName: _serverName(scope.user),
          addition: target != null,
        );
        if (!mounted) return;
        await printOrPreview(context, t);
      }
    }
    if (!mounted) return;
    setState(() {
      cart.clear();
      note.clear();
    });
    await _load();
    widget.onSent?.call();
    if (target != null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (products.isEmpty) return const EmptyState(Icons.inventory_2_outlined, 'Aucun produit actif. Ajoutez des produits dans Gestion > Produits.');
    final wide = isWide(context);
    final catalog = _catalog(context, wide);
    if (wide) {
      return Row(
        children: [
          Expanded(child: catalog),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 360,
            child: ColoredBox(color: Colors.white, child: _cartPanel(context)),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: catalog),
        Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$count article(s)', style: Theme.of(context).textTheme.bodySmall),
                        AnimatedAmount(total, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  if (shop && canPay) ...[
                    IconButton.outlined(tooltip: 'Panier', onPressed: cart.isEmpty ? null : () => _openCartSheet(context), icon: const Icon(Icons.shopping_basket)),
                    const SizedBox(width: 8),
                    FilledButton.icon(onPressed: cart.isEmpty || sending ? null : _checkout, icon: const Icon(Icons.point_of_sale), label: const Text('Encaisser')),
                  ] else
                    FilledButton.icon(onPressed: cart.isEmpty ? null : () => _openCartSheet(context), icon: const Icon(Icons.shopping_basket), label: const Text('Panier')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.8,
          child: _cartPanel(ctx, onChanged: () => refresh(() {}), closeAfterSend: true),
        ),
      ),
    );
  }

  Widget _categoryChip(String label, IconData icon, Color color, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? AppColors.ink : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? AppColors.ink : AppColors.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: selected ? Colors.white : AppColors.muted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _catalog(BuildContext context, bool wide) {
    final compact = isCompact(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 8 : 12, compact ? 8 : 12, compact ? 8 : 12, 4),
          child: TextField(
            controller: searchCtrl,
            focusNode: searchFocus,
            autofocus: shop,
            textInputAction: TextInputAction.done,
            onSubmitted: _onSearchSubmitted,
            decoration: InputDecoration(
              prefixIcon: Icon(shop ? Icons.qr_code_scanner : Icons.search, color: AppColors.muted),
              suffixIcon: cameraScanSupported || builtinScan
                  ? IconButton(
                      tooltip: builtinScan ? 'Allumer le lecteur' : 'Scanner avec la caméra',
                      onPressed: _scanWithCamera,
                      icon: Icon(builtinScan ? Icons.barcode_reader : Icons.photo_camera_outlined),
                    )
                  : null,
              hintText: mode == BusinessMode.pharmacy ? 'Scanner ou chercher un médicament' : (shop ? 'Scanner le code-barres ou chercher' : 'Rechercher ou scanner un produit'),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: AppColors.line),
              ),
            ),
            onChanged: (v) => setState(() => search = v.trim()),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: scanMessage == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: EdgeInsets.fromLTRB(compact ? 8 : 12, 0, compact ? 8 : 12, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: scanError ? AppColors.red.withValues(alpha: 0.10) : AppColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(scanError ? Icons.error_outline : Icons.check_circle, size: 18, color: scanError ? AppColors.red : AppColors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scanMessage!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: scanError ? AppColors.red : AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              _categoryChip('Tout', Icons.apps, AppColors.ink, category == null, () => setState(() => category = null)),
              for (final c in categories)
                Builder(
                  builder: (_) {
                    final st = CategoryStyle.of(c);
                    return _categoryChip(c, st.icon, st.color, category == c, () => setState(() => category = c));
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.all(compact ? 8 : 12),
            // Petit écran : 3 colonnes (9 à 12 produits visibles) au lieu de 2 grandes photos.
            gridDelegate: compact
                ? const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.74, crossAxisSpacing: 6, mainAxisSpacing: 6)
                : SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: wide ? 200 : 180, childAspectRatio: 0.82, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: visible.length,
            itemBuilder: (context, i) => FadeSlideIn(
              key: ValueKey('${category ?? '*'}|$search|${visible[i].id}'),
              index: i,
              child: _ProductTile(product: visible[i], compact: compact, quantity: cart[visible[i].id]?.quantity ?? 0, onTap: () => _add(visible[i]), onRemove: () => _add(visible[i], -1)),
            ),
          ),
        ),
      ],
    );
  }

  /// « Servi par » : la caisse choisit la serveuse ; une serveuse voit son nom.
  Widget _serverPicker(VoidCallback? onChanged) {
    final me = AppScope.of(context).user;
    if (!me.can(Permission.takePayments)) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Servi par', border: OutlineInputBorder(), isDense: true),
        child: Text(
          me.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    final servers = staff.where((u) => u.id != me.id).toList()..sort((a, b) => (a.role == Role.server ? 0 : 1).compareTo(b.role == Role.server ? 0 : 1));
    return DropdownButtonFormField<String?>(
      initialValue: serverId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Servi par', border: OutlineInputBorder(), isDense: true),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text('${me.name} (moi)', overflow: TextOverflow.ellipsis)),
        for (final u in servers)
          DropdownMenuItem<String?>(
            value: u.id,
            child: Text(u.role == Role.server ? u.name : '${u.name} · ${u.role.label}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() {
        serverId = v;
        onChanged?.call();
      }),
    );
  }

  Widget _cartPanel(BuildContext context, {VoidCallback? onChanged, bool closeAfterSend = false}) {
    final target = widget.target;
    final lines = cart.values.toList();
    void change(Product p, int d) {
      _add(p, d);
      onChanged?.call();
      if (cart.isEmpty && closeAfterSend) Navigator.pop(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: target != null
              ? Text('Ajout à N° ${target.number} · ${target.tableLabel}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))
              : shop
              ? Row(
                  children: [
                    Icon(Icons.storefront, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Vente directe · $count article(s)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: tableLabel,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Table', border: OutlineInputBorder(), isDense: true),
                        items: [
                          for (final l in ['Comptoir', 'À emporter', ...tables.map((t) => t.label)])
                            DropdownMenuItem(
                              value: l,
                              child: Text(l, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          tableLabel = v ?? 'Comptoir';
                          onChanged?.call();
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _serverPicker(onChanged)),
                  ],
                ),
        ),
        Expanded(
          child: lines.isEmpty
              ? EmptyState(
                  shop ? Icons.qr_code_scanner : Icons.touch_app_outlined,
                  shop ? 'Scannez un produit ou touchez-le pour l\'ajouter.' : 'Touchez un produit pour l\'ajouter.\nAppui long pour retirer.',
                )
              : ListView(
                  children: [
                    for (final l in lines)
                      FadeSlideIn(
                        key: ValueKey('cart-${l.product.id}'),
                        offset: 10,
                        child: ListTile(
                          dense: true,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: ProductImage(image: l.product.image, category: l.product.category, name: l.product.name),
                            ),
                          ),
                          title: Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(shop ? '${l.quantity} × ${fcfa(l.product.price)} = ${fcfa(l.total)}' : '${fcfa(l.product.price)} · ${l.product.station.label}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(onPressed: () => change(l.product, -1), icon: const Icon(Icons.remove_circle_outline)),
                              SizedBox(
                                width: 24,
                                child: Text(
                                  '${l.quantity}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              IconButton(onPressed: () => change(l.product, 1), icon: const Icon(Icons.add_circle_outline)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (target == null && !shop)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (cuisson, sans piment…)', isDense: true),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Total', style: TextStyle(fontSize: 18))),
                  AnimatedAmount(total, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              if (shop && canPay)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: cart.isEmpty || sending
                      ? null
                      : () async {
                          if (closeAfterSend) Navigator.pop(context);
                          await _checkout();
                        },
                  icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.point_of_sale),
                  label: Text('Encaisser ${fcfa(total)}'),
                )
              else ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: cart.isEmpty || sending
                      ? null
                      : () async {
                          if (closeAfterSend) Navigator.pop(context);
                          await _send();
                        },
                  icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                  label: Text(target != null ? 'Ajouter à la commande' : (shop ? 'Envoyer à la caisse' : 'Envoyer la commande')),
                ),
                if (target == null && !shop && canPay) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: cart.isEmpty || sending
                        ? null
                        : () async {
                            if (closeAfterSend) Navigator.pop(context);
                            await _checkout();
                          },
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('Encaisser maintenant'),
                  ),
                ],
              ],
              if (cart.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(cart.clear);
                    if (closeAfterSend) Navigator.pop(context);
                  },
                  child: const Text('Vider le panier'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    note.dispose();
    searchCtrl.dispose();
    _hwSub?.cancel();
    searchFocus.dispose();
    super.dispose();
  }
}

/// Plein écran pour ajouter des articles à une commande existante.
class AddItemsPage extends StatelessWidget {
  const AddItemsPage({super.key, required this.target});
  final OrderSummary target;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: gradientAppBar(context, title: Text('Ajouter · N° ${target.number}')),
    body: PatternBackground(child: OrderScreen(target: target)),
  );
}

/// Carte produit : photo plein cadre, nom et prix ; rebond au toucher, pastille animée.
class _ProductTile extends StatefulWidget {
  const _ProductTile({required this.product, required this.quantity, required this.onTap, required this.onRemove, this.compact = false});
  final bool compact;
  final Product product;
  final int quantity;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0.93).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween<double>(begin: 0.93, end: 1).chain(CurveTween(curve: Curves.elasticOut)), weight: 65),
  ]).animate(_bounce);

  void _tap() {
    _bounce.forward(from: 0);
    widget.onTap();
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final q = widget.quantity;
    return ScaleTransition(
      scale: _scale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: q > 0 ? AppColors.orange : AppColors.line, width: q > 0 ? 2.5 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: q > 0 ? 0.14 : 0.05),
              blurRadius: q > 0 ? 12 : 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: _tap,
              onLongPress: q > 0 ? widget.onRemove : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProductImage(image: p.image, category: p.category, name: p.name),
                        if (p.trackStock && p.lowStock)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                widget.compact ? 'Bas : ${p.stockQty}' : 'Stock bas : ${p.stockQty}',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.elasticOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                            child: q == 0
                                ? const SizedBox(key: ValueKey(0), width: 30, height: 30)
                                : Container(
                                    key: ValueKey(q),
                                    width: 30,
                                    height: 30,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.orange,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: Text(
                                      '$q',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: widget.compact ? const EdgeInsets.fromLTRB(6, 4, 6, 6) : const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: widget.compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: widget.compact ? 12.5 : 14, height: 1.15),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              fcfa(p.price),
                              style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800, fontSize: widget.compact ? 13 : 14),
                            ),
                            const SizedBox(width: 4),
                            if (p.trackStock && !p.lowStock && !widget.compact)
                              Expanded(
                                child: Text(
                                  '${p.stockQty} en stock',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
