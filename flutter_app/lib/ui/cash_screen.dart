import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/permissions.dart';
import '../data/models.dart';
import '../printing/ticket_builder.dart';
import 'common.dart';
import 'theme.dart';
import 'ticket_preview.dart';

/// Ouverture / clôture de caisse, rapport X en cours, historique des Z.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});
  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  CashSession? session;
  ZReport? live;
  List<CashSession> history = [];
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final s = await repo.currentSession();
    final r = s == null ? null : await repo.currentReport();
    final h = await repo.sessions();
    if (!mounted) return;
    setState(() {
      session = s;
      live = r;
      history = h.where((x) => x.status == 'closed').toList();
      loading = false;
    });
  }

  Future<void> _open() async {
    final scope = AppScope.read(context);
    final float = await promptAmount(context, 'Ouvrir la caisse', label: 'Fond de caisse (monnaie de départ)', initial: 0, allowZero: true);
    if (float == null || !mounted) return;
    await guard(context, () => scope.repo.openSession(scope.user, float), success: 'Caisse ouverte');
    await _load();
  }

  Future<void> _close() async {
    final scope = AppScope.read(context);
    final expected = live?.expectedCash ?? 0;
    if ((live?.openOrdersCount ?? 0) > 0) {
      final go = await confirm(
        context,
        'Commandes impayées',
        '${live!.openOrdersCount} commande(s) restent non soldées (${fcfa(live!.openOrdersBalance)}). Elles resteront ouvertes pour la prochaine session. Continuer la clôture ?',
        ok: 'Continuer',
      );
      if (!go || !mounted) return;
    }
    final counted = await promptAmount(context, 'Clôturer la caisse', label: 'Espèces comptées dans le tiroir', allowZero: true);
    if (counted == null || !mounted) return;
    final diff = counted - expected;
    final ok = await confirm(
      context,
      'Confirmer la clôture',
      'Attendu : ${fcfa(expected)}\nCompté : ${fcfa(counted)}\n${diff == 0 ? 'Aucun écart.' : (diff > 0 ? 'Excédent : ${fcfa(diff)}' : 'Manquant : ${fcfa(-diff)}')}\n\nLa clôture est définitive.',
      ok: 'Clôturer',
      danger: diff != 0,
    );
    if (!ok || !mounted) return;
    final z = await guard(context, () => scope.repo.closeSession(scope.user, counted), success: 'Caisse clôturée');
    await _load();
    if (z != null && mounted) {
      final shop = await scope.repo.shopInfo();
      if (mounted) await showTicket(context, zReportTicket(shop, z));
    }
  }

  Future<void> _showReport(ZReport z) async {
    final shop = await AppScope.read(context).repo.shopInfo();
    if (mounted) await showTicket(context, zReportTicket(shop, z));
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user;
    final repo = AppScope.of(context).repo;
    if (loading) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    final s = session;
    final z = live;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (s == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.lock_outline, size: 36),
                      title: Text('Caisse fermée'),
                      subtitle: Text('Ouvrez la caisse en début de service en saisissant le fond de caisse.'),
                    ),
                    if (user.can(Permission.manageCashSession)) FilledButton.icon(onPressed: _open, icon: const Icon(Icons.lock_open), label: const Text('Ouvrir la caisse')),
                  ],
                ),
              ),
            )
          else if (z != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: const CircleAvatar(
                  backgroundColor: Color(0x1A2F9E44),
                  child: Icon(Icons.lock_open, color: AppColors.green),
                ),
                title: Text(
                  'Caisse ouverte depuis ${dateTimeOf(s.openedAt)}',
                  style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Par ${s.openedBy ?? '?'} · fond de caisse ${fcfa(s.openingFloat)}', style: TextStyle(color: AppColors.muted)),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                KpiCard(label: 'Total encaissé', value: fcfa(z.totalCollected), icon: Icons.account_balance_wallet, color: AppColors.green),
                KpiCard(label: 'Espèces attendues', value: fcfa(z.expectedCash), icon: Icons.payments, color: AppColors.orange),
                KpiCard(label: 'Impayés', value: '${z.openOrdersCount} · ${fcfa(z.openOrdersBalance)}', icon: Icons.hourglass_bottom, color: AppColors.amber),
                KpiCard(label: 'Commandes soldées', value: '${z.ordersClosed}', icon: Icons.done_all, color: AppColors.ink),
              ],
            ),
            const SectionTitle('Encaissements par mode'),
            Card(
              child: Column(
                children: [
                  for (final m in ['cash', 'mobile_money', 'card', 'credit'])
                    if (z.byMethod.containsKey(m))
                      ListTile(
                        dense: true,
                        title: Text(methodLabel(m)),
                        trailing: Text(fcfa(z.byMethod[m]!), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  if (z.byMethod.isEmpty) const ListTile(title: Text('Aucun encaissement pour l\'instant')),
                  if (z.creditsIssuedFromChange > 0) ListTile(dense: true, title: const Text('Monnaie laissée en avoir (espèces en plus)'), trailing: Text(fcfa(z.creditsIssuedFromChange))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: () => _showReport(z), icon: const Icon(Icons.receipt), label: const Text('Rapport X')),
                if (user.can(Permission.manageCashSession))
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    onPressed: _close,
                    icon: const Icon(Icons.lock),
                    label: const Text('Clôturer (rapport Z)'),
                  ),
              ],
            ),
          ],
          if (user.can(Permission.viewReports)) ...[
            const SectionTitle('Clôtures précédentes'),
            if (history.isEmpty) const ListTile(title: Text('Aucune clôture')),
            for (final h in history)
              Card(
                child: Builder(
                  builder: (context) {
                    final r = repo.storedReport(h);
                    final diff = r?.difference ?? 0;
                    return ListTile(
                      title: Text('${dateTimeOf(h.openedAt)} → ${h.closedAt == null ? '?' : dateTimeOf(h.closedAt!)}'),
                      subtitle: Text('Encaissé ${fcfa(r?.totalCollected ?? 0)} · ${h.closedBy ?? ''}'),
                      trailing: Text(
                        diff == 0 ? 'OK' : fcfa(diff),
                        style: TextStyle(fontWeight: FontWeight.w800, color: diff == 0 ? Colors.green.shade700 : cs.error),
                      ),
                      onTap: r == null ? null : () => _showReport(r),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
