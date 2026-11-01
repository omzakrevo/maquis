import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/permissions.dart';
import '../../data/models.dart';
import '../common.dart';
import '../theme.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser> users = [];
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final u = await AppScope.read(context).repo.users(includeInactive: true);
    if (!mounted) return;
    setState(() {
      users = u;
      loading = false;
    });
  }

  Future<void> _create() async {
    final scope = AppScope.read(context);
    final name = TextEditingController();
    final pin = TextEditingController();
    var role = Role.server;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nouvel employé'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom ou prénom'),
              ),
              DropdownButtonFormField<Role>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: [
                  for (final r in Role.values)
                    if (r != Role.owner || scope.user.role == Role.owner) DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => set(() => role = v ?? role),
              ),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'PIN provisoire (4 à 6 chiffres)'),
              ),
              Text(_roleHelp(role), style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await guard(
      context,
      () => scope.repo.createUser(scope.user, name: name.text, role: role, pin: pin.text),
      success: 'Employé créé. Il devra changer son PIN à la première connexion.',
    );
    await _load();
  }

  String _roleHelp(Role r) => switch (r) {
    Role.owner => 'Tous les droits, y compris les employés.',
    Role.manager => 'Catalogue, stocks, annulations, avoirs, rapports, paramètres.',
    Role.cashier => 'Commandes, encaissements, ouverture/clôture de caisse.',
    Role.server => 'Prise de commande uniquement.',
  };

  Future<void> _actions(AppUser u) async {
    final scope = AppScope.read(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(u.role.label),
            ),
            ListTile(leading: const Icon(Icons.password), title: const Text('Réinitialiser le PIN'), onTap: () => Navigator.pop(ctx, 'pin')),
            ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Changer le rôle'), onTap: () => Navigator.pop(ctx, 'role')),
            ListTile(leading: Icon(u.active ? Icons.person_off_outlined : Icons.person_outline), title: Text(u.active ? 'Désactiver' : 'Réactiver'), onTap: () => Navigator.pop(ctx, 'active')),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        final pin = await promptText(context, 'Nouveau PIN provisoire pour ${u.name}', label: '4 à 6 chiffres', minLength: 4);
        if (pin != null && mounted) await guard(context, () => scope.repo.setPin(scope.user, u.id, pin), success: 'PIN réinitialisé');
      case 'role':
        final role = await showDialog<Role>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Rôle'),
            children: [
              for (final r in Role.values)
                if (r != Role.owner || scope.user.role == Role.owner) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(r.label)),
            ],
          ),
        );
        if (role != null && mounted) await guard(context, () => scope.repo.updateUser(scope.user, u.id, role: role), success: 'Rôle modifié');
      case 'active':
        await guard(context, () => scope.repo.updateUser(scope.user, u.id, active: !u.active));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: gradientAppBar(context, title: const Text('Employés')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add), label: const Text('Employé')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              for (final u in users)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase())),
                    title: Text(u.name, style: TextStyle(decoration: u.active ? null : TextDecoration.lineThrough)),
                    subtitle: Text('${u.role.label}${u.mustChangePin ? ' · PIN à changer' : ''}${u.active ? '' : ' · désactivé'}'),
                    trailing: const Icon(Icons.more_vert),
                    onTap: () => _actions(u),
                  ),
                ),
            ],
          ),
  );
}
