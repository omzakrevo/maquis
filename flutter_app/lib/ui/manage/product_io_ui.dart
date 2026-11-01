import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/product_io.dart';
import '../common.dart';
import '../theme.dart';

String _stamp() {
  final n = DateTime.now();
  String two(int v) => '$v'.padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
}

/// Exporte le catalogue en .xlsx (choix de l'emplacement par l'utilisateur).
Future<void> exportProducts(BuildContext context) async {
  final repo = AppScope.read(context).repo;
  final products = await repo.products(includeInactive: true);
  final bytes = exportProductsXlsx(products);
  final name = 'produits_maquis_${_stamp()}.xlsx';
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Enregistrer le fichier Excel',
    fileName: name,
    bytes: bytes,
    mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (uri == null) return; // annulé
  if (context.mounted) toast(context, '${products.length} produit(s) exporté(s) dans $name');
}

/// Importe un fichier .xlsx ou .csv après aperçu et confirmation. Renvoie true si importé.
Future<bool> importProducts(BuildContext context) async {
  final scope = AppScope.read(context);
  final f = await FilePicker.pickFile(dialogTitle: 'Choisir le fichier Excel des produits', type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
  if (f == null) return false;
  final Uint8List bytes;
  try {
    bytes = await f.readAsBytes();
  } catch (_) {
    if (context.mounted) toast(context, 'Impossible de lire le fichier', error: true);
    return false;
  }
  final file = parseProductsFile(bytes, f.name);
  final existing = {for (final p in await scope.repo.products(includeInactive: true)) p.name.trim().toLowerCase(): p};
  if (!context.mounted) return false;
  final news = file.rows.where((r) => !existing.containsKey(r.name.trim().toLowerCase())).toList();
  final updates = file.rows.length - news.length;
  final missingPrice = news.where((r) => r.price == null).toList();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Importer « ${f.name} »'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  KpiCard(label: 'Nouveaux', value: '${news.length}', icon: Icons.add_circle_outline, color: AppColors.green, width: 150),
                  KpiCard(label: 'Mis à jour', value: '$updates', icon: Icons.sync, color: AppColors.orange, width: 150),
                  KpiCard(label: 'Ignorées', value: '${file.issues.length}', icon: Icons.warning_amber, color: file.issues.isEmpty ? AppColors.muted : AppColors.red, width: 150),
                ],
              ),
              if (missingPrice.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Prix manquant pour : ${missingPrice.map((r) => r.name).join(', ')}. Complétez le fichier : l\'import sera refusé.',
                    style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              if (file.issues.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Lignes ignorées', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final i in file.issues.take(12)) Text('• $i', style: const TextStyle(fontSize: 13)),
                if (file.issues.length > 12) Text('… et ${file.issues.length - 12} autre(s)'),
              ],
              if (file.rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Aperçu', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final r in file.rows.take(10))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(existing.containsKey(r.name.trim().toLowerCase()) ? Icons.sync : Icons.add, size: 18, color: AppColors.muted),
                    title: Text(r.name),
                    subtitle: Text(
                      [if (r.category != null) r.category!, if (r.station != null) r.station!.label, if (r.stock != null) 'stock ${r.stock}', if (r.active == false) 'hors vente'].join(' · '),
                    ),
                    trailing: Text(r.price == null ? '—' : fcfa(r.price!), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                if (file.rows.length > 10) Text('… et ${file.rows.length - 10} autre(s) produit(s)'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton.icon(
          onPressed: file.rows.isEmpty || missingPrice.isNotEmpty ? null : () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.upload_file),
          label: Text('Importer ${file.rows.length} produit(s)'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final result = await guard(context, () => scope.repo.importProducts(scope.user, file.rows));
  if (result == null || !context.mounted) return false;
  toast(context, 'Import terminé : ${result.created} créé(s), ${result.updated} mis à jour${result.stockAdjusted > 0 ? ', ${result.stockAdjusted} stock(s) ajusté(s)' : ''}');
  return true;
}
