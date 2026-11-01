# Architecture

## État actuel (V0.3)

```
┌──────────── Appareil unique (Android ou Windows) ────────────┐
│  ui/  écrans Flutter                                          │
│    │  appelle                                                 │
│  data/pos_repository.dart  ← règles métier, permissions,      │
│    │                          transactions, audit, outbox      │
│  data/database.dart        ← SQLite + migrations versionnées  │
│  printing/                 ← tickets → ESC/POS → TCP / BT     │
└───────────────────────────────────────────────────────────────┘
```

Principes déjà en place, à conserver quand on passera au serveur :

- **Toute écriture passe par `PosRepository`**, qui vérifie la permission de l'utilisateur qui agit, s'exécute
  dans une transaction, écrit dans `audit_logs` et ajoute un événement numéroté dans `sync_outbox`.
- **Montants en entiers FCFA** partout (aucune virgule flottante).
- **Idempotence** des paiements (`payments.idempotency_key`) et des mouvements d'avoir.
- **Avoirs atomiques** : la décrémentation du solde est conditionnelle (`WHERE balance_xof = ancien solde`) et dans
  la même transaction que le paiement ; contraintes `CHECK` en base (solde ≥ 0, ≤ montant initial).
- **Une seule session de caisse ouverte** (index unique partiel).
- **Instantané du nom et du prix** dans `order_items` : modifier un prix ne change pas les commandes passées.
- **Migrations** : liste ordonnée dans `database.dart` ; on n'en modifie jamais une publiée, on en ajoute une.
- `data/` et `printing/` (sauf `network_printer.dart`, qui n'utilise que `dart:io`) n'importent pas Flutter.

### Rapport Z — calcul des espèces attendues

```
espèces attendues = fond de caisse
                  + encaissements « Espèces » de la session (montants nets, monnaie déjà rendue)
                  + monnaie laissée en avoir pendant la session (le client a donné plus d'espèces)
écart             = espèces comptées − espèces attendues
```

## Cible

- **Serveur local** : service Dart indépendant (Windows ou mini-PC) réutilisant `data/` ; SQLite WAL ; REST +
  WebSocket ; file d'impression centralisée ; les téléphones des serveurs deviennent des clients.
- **Cloud** : Supabase PostgreSQL (`database/postgresql.sql`), backend de confiance pour licences et données
  multi-établissements ; RLS activée sans accès client direct.
- **Synchronisation** : consommer `sync_outbox` par `seq` croissant, accusés de réception (`delivered_at`),
  déduplication par identifiant d'événement.
- **Paiements** : `mobile_money` reste une déclaration manuelle tant qu'aucune API opérateur n'est intégrée.
- **Impression** : `NetworkPrinter` (TCP 9100) et `BluetoothPrinter` (SPP, plugin print_bluetooth_thermal) existent ;
  ajouter un transport USB (Windows : spouleur RAW ; Android : USB host) derrière la même interface `PrinterTransport`.

## Feuille de route

| # | Module | État |
|---|---|---|
| 1 | Authentification PIN + rôles + audit | ✅ V0.2 (poste unique) |
| 2 | Impression ESC/POS réseau + Bluetooth, bons bar/cuisine, QR | ✅ V0.2–V0.3 (USB à faire) |
| 3 | Avoirs clients atomiques, caisse de fin de journée (X/Z) | ✅ V0.2 |
| 4 | Stocks simples (mouvements, inventaire, alertes, historique détaillé) | ✅ V0.2–V0.3 |
| 4b | Scan QR des tickets et avoirs | ✅ V0.3 |
| 5 | Service local API + clients serveurs (multi-postes) | À faire — prochaine étape |
| 6 | Écran cuisine/bar (KDS) temps réel | À faire (dépend de 5) |
| 7 | Sauvegarde automatique + export Excel des ventes | À faire |
| 8 | Synchronisation cloud, multi-établissements | À faire |
| 9 | Portail Super Admin, abonnements, licences appareils | À faire |
