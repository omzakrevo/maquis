/// Rôles et permissions. Côté appareil unique, c'est le dépôt (PosRepository)
/// qui vérifie les permissions avant chaque écriture ; l'interface ne fait que
/// masquer ce qui n'est pas autorisé.
enum Role {
  owner('Propriétaire'),
  manager('Gérant'),
  cashier('Caissier'),
  server('Serveur');

  const Role(this.label);
  final String label;

  static Role parse(String value) => Role.values.firstWhere((r) => r.name == value, orElse: () => Role.server);
}

enum Permission { takeOrders, takePayments, manageCashSession, cancelOrders, issueCredits, manageCatalog, manageStock, manageTables, manageUsers, manageSettings, viewReports, viewAudit }

const Map<Role, Set<Permission>> _grants = {
  Role.owner: {...Permission.values},
  Role.manager: {
    Permission.takeOrders,
    Permission.takePayments,
    Permission.manageCashSession,
    Permission.cancelOrders,
    Permission.issueCredits,
    Permission.manageCatalog,
    Permission.manageStock,
    Permission.manageTables,
    Permission.manageSettings,
    Permission.viewReports,
    Permission.viewAudit,
  },
  Role.cashier: {Permission.takeOrders, Permission.takePayments, Permission.manageCashSession, Permission.viewReports},
  Role.server: {Permission.takeOrders},
};

bool roleCan(Role role, Permission permission) => _grants[role]!.contains(permission);

class PermissionDenied implements Exception {
  PermissionDenied(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Erreur métier affichable telle quelle à l'utilisateur.
class BusinessError implements Exception {
  BusinessError(this.message);
  final String message;
  @override
  String toString() => message;
}
