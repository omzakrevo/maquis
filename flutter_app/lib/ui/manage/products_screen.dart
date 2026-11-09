import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../common.dart';
import '../photo_picker.dart';
import '../scan_screen.dart';
import 'bulk_add_screen.dart';
import 'product_io_ui.dart';
import '../theme.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  BusinessMode mode = BusinessMode.restaurant;
  List<Product> products = [];
  bool showInactive = false;
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = await repo.products(includeInactive: true);
    final m = await repo.businessMode();
    if (!mounted) return;
    setState(() {
      mode = m;
      products = p;
      loading = false;
    });
  }

  /// Scanner le code d'un article : s'il existe on l'ouvre, sinon fiche nouvelle pré-remplie.
  Future<void> _scanAdd() async {
    final v = await scanCode(context, title: 'Scanner le code-barres ou le QR de l\'article');
    if (v == null || !mounted) return;
    var code = v.trim();
    if (code.toUpperCase().startsWith('PRD:')) code = code.substring(4);
    code = code.replaceAll(RegExp(r'[\s\u0000-\u001f]'), '');
    if (code.isEmpty) return;
    final known = products.where((p) => p.barcode == code).firstOrNull;
    if (known != null) {
      toast(context, 'Déjà enregistré : ${known.name}');
      await _edit(known);
    } else {
      await _edit(null, code);
    }
  }

  Future<void> _bulkAdd() async {
    final n = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => BulkAddScreen(existing: products)));
    if (n != null) await _load();
  }

  Future<void> _edit([Product? p, String? scannedCode]) async {
    final scope = AppScope.read(context);
    final cats = products.map((x) => x.category).toSet().toList()..sort();
    final name = TextEditingController(text: p?.name);
    final category = TextEditingController(text: p?.category ?? (cats.isEmpty ? '' : cats.first));
    final price = TextEditingController(text: p == null ? '' : '${p.price}');
    final alert = TextEditingController(text: '${p?.alertQty ?? 0}');
    final barcode = TextEditingController(text: p?.barcode ?? scannedCode ?? '');
    final cost = TextEditingController(text: p?.cost == null ? '' : '${p!.cost}');
    var track = p?.trackStock ?? mode.directSale;
    var station = p?.station ?? Station.bar;
    var active = p?.active ?? true;
    String? image = p?.image;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(p == null ? 'Nouveau produit' : 'Modifier ${p.name}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: isCompact(ctx) ? 76 : 110,
                          height: isCompact(ctx) ? 76 : 110,
                          child: ProductImage(image: image, category: category.text, name: name.text),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                final f = await guard(ctx, () => pickProductPhoto());
                                if (f != null) set(() => image = f);
                              },
                              icon: const Icon(Icons.photo_library),
                              label: Text(Platform.isWindows ? 'Image…' : 'Galerie', maxLines: 1, softWrap: false),
                            ),
                            if (cameraPhotoSupported)
                              FilledButton.tonalIcon(
                                onPressed: () async {
                                  final f = await guard(ctx, () => pickProductPhoto(camera: true));
                                  if (f != null) set(() => image = f);
                                },
                                icon: const Icon(Icons.photo_camera),
                                label: const Text('Photo', maxLines: 1, softWrap: false),
                              ),
                            if (image != null)
                              TextButton.icon(onPressed: () => set(() => image = null), icon: const Icon(Icons.hide_image_outlined), label: const Text('Retirer', maxLines: 1, softWrap: false)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nom'),
                  ),
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: category.text),
                    optionsBuilder: (v) => cats.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (v) => category.text = v,
                    fieldViewBuilder: (ctx, ctrl, focus, submit) {
                      ctrl.addListener(() => category.text = ctrl.text);
                      return TextField(
                        controller: ctrl,
                        focusNode: focus,
                        decoration: InputDecoration(
                          labelText: switch (mode) {
                            BusinessMode.pharmacy => 'Catégorie (Antalgiques, Sirops…)',
                            BusinessMode.shop => 'Catégorie (Boissons, Épicerie…)',
                            BusinessMode.restaurant => 'Catégorie (Bières, Plats…)',
                          },
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Prix de vente', suffixText: 'F'),
                          onChanged: (_) => set(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Prix d\'achat', suffixText: 'F', helperText: 'Facultatif'),
                          onChanged: (_) => set(() {}),
                        ),
                      ),
                    ],
                  ),
                  Builder(
                    builder: (_) {
                      final pv = parseFcfa(price.text), pa = parseFcfa(cost.text);
                      if (pv == null || pa == null || pv == 0) return const SizedBox.shrink();
                      final m = pv - pa;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            m < 0 ? 'Attention : vendu à perte (${fcfa(m)})' : 'Marge : ${fcfa(m)} par unité · ${(m * 100 / pv).toStringAsFixed(0)} % du prix de vente',
                            style: TextStyle(fontWeight: FontWeight.w700, color: m < 0 ? AppColors.red : AppColors.green),
                          ),
                        ),
                      );
                    },
                  ),
                  TextField(
                    controller: barcode,
                    decoration: InputDecoration(
                      labelText: 'Code-barres (facultatif)',
                      helperText: 'Douchette ou caméra',
                      suffixIcon: IconButton(
                        tooltip: 'Scanner',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () async {
                          final v = await scanCode(ctx, title: 'Scanner le code-barres du produit');
                          if (v != null) set(() => barcode.text = v.trim());
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Poste bar/cuisine : sans objet en vente directe (boutique, pharmacie).
                  if (!mode.directSale)
                    SegmentedButton<Station>(
                      segments: const [
                        ButtonSegment(value: Station.bar, icon: Icon(Icons.local_bar), label: Text('Bar')),
                        ButtonSegment(value: Station.kitchen, icon: Icon(Icons.soup_kitchen), label: Text('Cuisine')),
                      ],
                      selected: {station},
                      onSelectionChanged: (s) => set(() => station = s.first),
                    ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: track, onChanged: (v) => set(() => track = v), title: const Text('Suivre le stock')),
                  if (track)
                    TextField(
                      controller: alert,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Alerte si stock ≤'),
                    ),
                  if (p != null) SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => set(() => active = v), title: const Text('En vente')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final priceValue = parseFcfa(price.text);
    if (priceValue == null) {
      toast(context, 'Prix invalide', error: true);
      return;
    }
    await guard(
      context,
      () => scope.repo.saveProduct(
        scope.user,
        id: p?.id,
        name: name.text,
        category: category.text,
        price: priceValue,
        trackStock: track,
        alertQty: parseFcfa(alert.text) ?? 0,
        station: station,
        active: active,
        image: image,
        clearImage: image == null,
        barcode: barcode.text,
        cost: parseFcfa(cost.text),
        clearCost: cost.text.trim().isEmpty,
      ),
      success: 'Produit enregistré',
    );
    await _load();
  }

  Future<void> _import() async {
    if (await importProducts(context)) await _load();
  }

  Future<void> _export() => guard(context, () => exportProducts(context));

  Widget _categoryHeader(String category) {
    final st = CategoryStyle.of(category);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.orange.withValues(alpha: 0.10),
            child: Icon(st.icon, size: 16, color: AppColors.orange),
          ),
          const SizedBox(width: 8),
          Text(
            category,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = products.where((p) => showInactive || p.active).toList();
    String? lastCat;
    return Scaffold(
      appBar: gradientAppBar(
        context,
        title: Text(Brand.pharmacy ? 'Médicaments et prix' : 'Produits et prix'),
        actions: isWide(context)
            ? [
                FilterChip(label: const Text('Inactifs'), selected: showInactive, onSelected: (v) => setState(() => showInactive = v)),
                const SizedBox(width: 4),
                OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file), label: const Text('Importer Excel')),
                const SizedBox(width: 6),
                OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.download), label: const Text('Exporter Excel')),
                const SizedBox(width: 8),
              ]
            : [
                // Téléphone : tout dans un menu pour ne pas déborder.
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'import') _import();
                    if (v == 'export') _export();
                    if (v == 'inactive') setState(() => showInactive = !showInactive);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'import',
                      child: ListTile(leading: Icon(Icons.upload_file), title: Text('Importer depuis Excel')),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: ListTile(leading: Icon(Icons.download), title: Text('Exporter vers Excel')),
                    ),
                    CheckedPopupMenuItem(value: 'inactive', checked: showInactive, child: const Text('Afficher les produits hors vente')),
                  ],
                ),
              ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Produit')),
      body: PatternBackground(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(key: const ValueKey('scan-add'), onPressed: _scanAdd, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner un article')),
                        FilledButton.tonalIcon(key: const ValueKey('bulk-add'), onPressed: _bulkAdd, icon: const Icon(Icons.playlist_add), label: const Text('Ajout multiple')),
                      ],
                    ),
                  ),
                  if (list.isEmpty)
                    const EmptyState(Icons.inventory_2_outlined, 'Aucun article. Scannez, ajoutez-en plusieurs d\'un coup, importez un fichier Excel ou chargez les exemples (Gestion > Exemples).'),
                  for (final p in list) ...[
                    if (p.category != lastCat) _categoryHeader(lastCat = p.category),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                        leading: Opacity(
                          opacity: p.active ? 1 : 0.4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: ProductImage(image: p.image, category: p.category, name: p.name),
                            ),
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(fontWeight: FontWeight.w700, decoration: p.active ? null : TextDecoration.lineThrough),
                        ),
                        subtitle: Row(
                          children: [
                            if (!mode.directSale) ...[Icon(p.station == Station.kitchen ? Icons.soup_kitchen : Icons.local_bar, size: 15, color: stationColor(p.station)), const SizedBox(width: 4)],
                            Flexible(
                              child: Text(
                                [
                                  if (!mode.directSale) p.station.label,
                                  if (p.trackStock) 'stock ${p.stockQty}',
                                  if (p.cost != null) 'achat ${fcfa(p.cost!)} · marge ${p.marginRate!.toStringAsFixed(0)} %',
                                  if (p.barcode != null) '▮ ${p.barcode}',
                                  if (!p.active) 'hors vente',
                                ].join(' · '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            fcfa(p.price),
                            style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.brick),
                          ),
                        ),
                        onTap: () => _edit(p),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
