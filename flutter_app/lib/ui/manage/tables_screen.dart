import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../common.dart';
import '../theme.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});
  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  List<DiningTable> tables = [];
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final t = await AppScope.read(context).repo.tables(includeInactive: true);
    if (!mounted) return;
    setState(() {
      tables = t;
      loading = false;
    });
  }

  Future<void> _edit([DiningTable? t]) async {
    final scope = AppScope.read(context);
    final label = await promptText(context, t == null ? 'Nouvelle table' : 'Renommer', label: 'Nom (Table 9, Terrasse 1, VIP…)', initial: t?.label ?? '');
    if (label == null || !mounted) return;
    await guard(context, () => scope.repo.saveTable(scope.user, id: t?.id, label: label, active: t?.active ?? true));
    await _load();
  }

  Future<void> _toggle(DiningTable t, bool active) async {
    final scope = AppScope.read(context);
    await guard(context, () => scope.repo.saveTable(scope.user, id: t.id, label: t.label, active: active));
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: gradientAppBar(context, title: const Text('Tables')),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Table')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              const Text('« Comptoir » et « À emporter » sont toujours disponibles.'),
              for (final t in tables)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.table_restaurant),
                    title: Text(t.label),
                    onTap: () => _edit(t),
                    trailing: Switch(value: t.active, onChanged: (v) => _toggle(t, v)),
                  ),
                ),
            ],
          ),
  );
}
