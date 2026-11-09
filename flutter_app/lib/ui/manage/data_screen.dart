import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../data/demo_catalogs.dart';
import '../../data/models.dart';
import '../common.dart';
import '../theme.dart';

/// Articles d'exemple (chargement / suppression) et remise à zéro de l'établissement en cours.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key});
  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  int products = 0, demo = 0, sales = 0;
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final all = await repo.products(includeInactive: true);
    final d = await repo.demoProductsActive();
    final o = (await repo.recentOrders(limit: 100000)).length;
    if (!mounted) return;
    setState(() {
      products = all.length;
      demo = d;
      sales = o;
      loading = false;
    });
  }

  String get _place => switch (AppColors.mode) {
    BusinessMode.pharmacy => 'la pharmacie',
    BusinessMode.shop => 'la boutique',
    BusinessMode.restaurant => 'le maquis / restaurant',
  };

  String get _demoWhat => switch (AppColors.mode) {
    BusinessMode.pharmacy => 'Médicaments et produits de soin (antalgiques, antibiotiques, antipaludiques, sirops, pansements, matériel médical) avec photos',
    BusinessMode.shop => 'Pièces détachées de moto (bougie, kit chaîne, freins, câbles, filtres, huile, batterie, pneus…) avec photos',
    BusinessMode.restaurant => 'Bières, sodas, jus et plats avec photos',
  };

  Future<void> _loadDemo() async {
    final scope = AppScope.read(context);
    final n = await guard(context, () => scope.repo.loadDemoCatalog(scope.user));
    if (n != null && mounted) toast(context, n == 0 ? 'Les exemples sont déjà là (remis en vente)' : '$n article(s) d\'exemple ajouté(s)');
    await _load();
  }

  Future<void> _deleteDemo() async {
    final scope = AppScope.read(context);
    final yes = await confirm(
      context,
      'Supprimer les exemples',
      'Supprimer les $demo article(s) d\'exemple de $_place ?\n\nVos propres articles ne sont pas touchés. Un exemple déjà vendu est seulement retiré de la vente, pour garder l\'historique juste.',
      ok: 'Supprimer',
      danger: true,
    );
    if (!yes || !mounted) return;
    final r = await guard(context, () => scope.repo.deleteDemoProducts(scope.user));
    if (r != null && mounted) toast(context, '${r.$1} supprimé(s)${r.$2 > 0 ? ', ${r.$2} retiré(s) de la vente' : ''}');
    await _load();
  }

  Future<void> _reset() async {
    final scope = AppScope.read(context);
    final ok = await confirm(
      context,
      'Tout effacer pour $_place ?',
      'Seront supprimés définitivement :\n• les $products article(s) et leur stock\n• les $sales vente(s), paiements et l\'historique de stock\n\nLes autres types d\'établissement, les employés, les réglages, les sessions de caisse et les avoirs clients restent.\n\nCette action est irréversible : exportez d\'abord vos rapports si besoin.',
      ok: 'Continuer',
      danger: true,
    );
    if (!ok || !mounted) return;
    final typed = await promptText(context, 'Confirmation', label: 'Tapez EFFACER pour confirmer', ok: 'Tout effacer', minLength: 7);
    if (typed == null || !mounted) return;
    if (typed.trim().toUpperCase() != 'EFFACER') {
      toast(context, 'Confirmation incorrecte : rien n\'a été effacé', error: true);
      return;
    }
    await guard(context, () => scope.repo.resetBusinessData(scope.user), success: 'Tout est effacé : vous pouvez enregistrer vos articles');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user;
    final count = demoCatalogFor(AppColors.mode.name).length;
    return Scaffold(
      appBar: gradientAppBar(context, title: const Text('Exemples et remise à zéro')),
      body: PatternBackground(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.store, color: AppColors.orange),
                      title: Text(AppColors.mode.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('$products article(s) · $demo exemple(s) · $sales vente(s)\nChaque type d\'établissement a son propre catalogue, son stock et ses ventes.'),
                      isThreeLine: true,
                    ),
                  ),
                  const SectionTitle('Articles d\'exemple'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$count articles pour essayer l\'application', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('$_demoWhat. Prix d\'achat et de vente, code-barres et stock de départ inclus.', style: TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(key: const ValueKey('load-demo'), onPressed: _loadDemo, icon: const Icon(Icons.download_done), label: const Text('Charger les exemples')),
                              OutlinedButton.icon(
                                key: const ValueKey('delete-demo'),
                                onPressed: demo == 0 ? null : _deleteDemo,
                                icon: const Icon(Icons.delete_sweep),
                                label: Text('Supprimer les exemples ($demo)'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SectionTitle('Recommencer à zéro'),
                  Card(
                    color: const Color(0xFFFFF5F5),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tout effacer pour $_place',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.red),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Supprime tous les articles, le stock et les ventes de ce type d\'établissement pour enregistrer vos articles depuis le début.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 12),
                          if (user.role == Role.owner)
                            FilledButton.icon(
                              key: const ValueKey('reset-business'),
                              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                              onPressed: products == 0 && sales == 0 ? null : _reset,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Tout effacer…'),
                            )
                          else
                            Text(
                              'Réservé au propriétaire.',
                              style: TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
