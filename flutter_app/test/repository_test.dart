import 'package:flutter_test/flutter_test.dart';
import 'package:maquis_resto_pro/core/permissions.dart';
import 'package:maquis_resto_pro/data/database.dart';
import 'package:maquis_resto_pro/data/models.dart';
import 'package:maquis_resto_pro/data/pos_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

void main() {
  sqfliteFfiInit();
  late PosRepository repo;
  late AppUser owner;

  setUp(() async {
    final db = await openPosDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    repo = PosRepository(db);
    final u = (await repo.users()).single;
    owner = await repo.login(u.id, '0000');
  });
  tearDown(() => repo.db.close());

  Future<Product> product(String name) async => (await repo.products()).firstWhere((p) => p.name == name);

  Future<String> order(Map<String, int> lines, {AppUser? by}) async {
    final cart = <CartLine>[];
    for (final e in lines.entries) {
      cart.add(CartLine(await product(e.key), e.value));
    }
    return repo.createOrder(by ?? owner, tableLabel: 'Table 1', lines: cart);
  }

  PaymentRequest req(String orderId, int amount, String method, {int? received, bool changeAsCredit = false, String? code, String? ref, String? key}) =>
      PaymentRequest(orderId: orderId, amount: amount, method: method, idempotencyKey: key ?? uuid.v4(), receivedCash: received, changeAsCredit: changeAsCredit, creditCode: code, reference: ref);

  test('premier démarrage : propriétaire PIN 0000 à changer, 12 produits, 8 tables', () async {
    expect(owner.role, Role.owner);
    expect(owner.mustChangePin, isTrue);
    expect((await repo.products()).length, 12);
    expect((await repo.tables()).length, 8);
  });

  test('PIN incorrect : compte bloqué après 5 essais', () async {
    for (var i = 0; i < 4; i++) {
      await expectLater(repo.login(owner.id, '9999'), throwsA(isA<BusinessError>()));
    }
    await expectLater(repo.login(owner.id, '9999'), throwsA(predicate((e) => '$e'.contains('bloqué'))));
    await expectLater(repo.login(owner.id, '0000'), throwsA(predicate((e) => '$e'.contains('bloqué'))));
  });

  test('changement de PIN et rôles', () async {
    await repo.setPin(owner, owner.id, '4826');
    expect((await repo.reloadUser(owner.id)).mustChangePin, isFalse);
    final server = await repo.createUser(owner, name: 'Awa', role: Role.server, pin: '1357');
    final s = await repo.login(server.id, '1357');
    await order({'Brakina': 1}, by: s); // un serveur peut prendre une commande
    await expectLater(repo.openSession(s, 0), throwsA(isA<PermissionDenied>()));
    await expectLater(repo.saveProduct(s, name: 'X', category: 'Y', price: 1), throwsA(isA<PermissionDenied>()));
    await expectLater(repo.updateUser(owner, owner.id, active: false), throwsA(isA<BusinessError>()));
  });

  test('numérotation journalière des commandes', () async {
    final a = await order({'Brakina': 1});
    final b = await order({'Castel': 1});
    final na = (await repo.orderDetail(a)).summary.number;
    final nb = (await repo.orderDetail(b)).summary.number;
    expect(na, endsWith('-001'));
    expect(nb, endsWith('-002'));
  });

  test('paiement impossible sans caisse ouverte', () async {
    final id = await order({'Brakina': 2});
    await expectLater(repo.pay(owner, req(id, 1600, 'cash')), throwsA(predicate((e) => '$e'.contains('Ouvrez la caisse'))));
  });

  test('paiements partiels, rendu monnaie, idempotence, clôture', () async {
    await repo.openSession(owner, 5000);
    final id = await order({'Brakina': 2, 'Poulet braisé': 1}); // 1600 + 3500 = 5100
    final key = uuid.v4();
    final r1 = await repo.pay(owner, req(id, 2000, 'cash', received: 2000, key: key));
    expect(r1.orderClosed, isFalse);
    final dup = await repo.pay(owner, req(id, 2000, 'cash', received: 2000, key: key));
    expect(dup.duplicate, isTrue);
    expect((await repo.orderDetail(id)).summary.paid, 2000);
    await expectLater(repo.pay(owner, req(id, 3101, 'cash')), throwsA(isA<BusinessError>()));
    await expectLater(repo.pay(owner, req(id, 1000, 'mobile_money')), throwsA(predicate((e) => '$e'.contains('référence'))));
    await repo.pay(owner, req(id, 1000, 'mobile_money', ref: 'OM123'));
    final r3 = await repo.pay(owner, req(id, 2100, 'cash', received: 5000));
    expect(r3.change, 2900);
    expect(r3.orderClosed, isTrue);
    expect(await repo.openOrders(), isEmpty);
    final z = await repo.closeSession(owner, 9000);
    expect(z.byMethod['cash'], 4100);
    expect(z.byMethod['mobile_money'], 1000);
    expect(z.expectedCash, 9100);
    expect(z.difference, -100);
    expect(z.ordersClosed, 1);
    expect(z.topProducts.first.name, 'Poulet braisé');
    expect(await repo.currentSession(), isNull);
  });

  test('monnaie rendue en avoir puis avoir utilisé sur une autre commande', () async {
    await repo.openSession(owner, 0);
    final a = await order({'Brakina': 1}); // 800
    final r = await repo.pay(owner, req(a, 800, 'cash', received: 2000, changeAsCredit: true));
    expect(r.change, 0);
    expect(r.issuedCreditAmount, 1200);
    final paidCash = (await repo.orderDetail(a)).payments.single;
    expect(paidCash.received, 2000);
    expect(paidCash.change, 0); // rien rendu en espèces : tout en avoir
    final code = r.issuedCreditCode!;
    expect((await repo.creditByCode(code.toLowerCase()))!.balance, 1200);

    final b = await order({'Castel': 1, 'Coca-Cola': 1}); // 1500
    await expectLater(repo.pay(owner, req(b, 1300, 'credit', code: code)), throwsA(predicate((e) => '$e'.contains('insuffisant'))));
    await repo.pay(owner, req(b, 1200, 'credit', code: code));
    final c = await repo.creditByCode(code);
    expect(c!.balance, 0);
    expect(c.status, 'exhausted');
    await expectLater(repo.pay(owner, req(b, 100, 'credit', code: code)), throwsA(predicate((e) => '$e'.contains('épuisé'))));
    await repo.pay(owner, req(b, 300, 'cash'));

    final z = await repo.closeSession(owner, 2300);
    // fond 0 + espèces 800 + 300 + 1200 laissés en avoir = 2300
    expect(z.expectedCash, 2300);
    expect(z.difference, 0);
    expect(z.creditsIssuedFromChange, 1200);
    expect(z.creditsRedeemed, 1200);
  });

  test('stock : décrément à la vente, restitution à l\'annulation', () async {
    final brakina = await product('Brakina');
    await repo.saveProduct(owner, id: brakina.id, name: brakina.name, category: brakina.category, price: brakina.price, trackStock: true, alertQty: 5);
    await repo.adjustStock(owner, brakina.id, 24, 'Livraison casier');
    final id = await order({'Brakina': 3});
    expect((await product('Brakina')).stockQty, 21);
    await expectLater(repo.cancelOrder(owner, id, ''), throwsA(isA<BusinessError>()));
    await repo.cancelOrder(owner, id, 'Erreur de saisie');
    expect((await product('Brakina')).stockQty, 24);
    expect((await repo.stockMovements(productId: brakina.id)).length, 3);
  });

  test('annulation refusée si un paiement existe', () async {
    await repo.openSession(owner, 0);
    final id = await order({'Castel': 2});
    await repo.pay(owner, req(id, 1000, 'cash'));
    await expectLater(repo.cancelOrder(owner, id, 'Client parti'), throwsA(predicate((e) => '$e'.contains('avoir'))));
  });

  test('ajout d\'articles à une commande ouverte, prix relu en base', () async {
    final id = await order({'Brakina': 1});
    final castel = await product('Castel');
    final stale = Product(id: castel.id, name: castel.name, category: castel.category, price: 1); // panier périmé
    await repo.addItems(owner, id, [CartLine(stale, 2)]);
    expect((await repo.orderDetail(id)).summary.total, 800 + 2000);
  });

  test('avoir manuel et annulation d\'avoir', () async {
    final issued = await repo.issueCredit(owner, amount: 3500, customerName: 'M. Ouédraogo', reason: 'Plat indisponible');
    expect(issued.code, matches(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$')));
    await repo.cancelCredit(owner, issued.credit.id, 'Erreur');
    expect((await repo.creditByCode(issued.code))!.status, 'cancelled');
  });

  test('chaque écriture alimente le journal et la file de synchronisation', () async {
    await order({'Brakina': 1});
    expect(await repo.pendingSyncEvents(), greaterThan(0));
    final log = await repo.auditLog();
    expect(log.map((e) => e.action), containsAll(['login', 'order_create']));
  });

  test('photos des produits de démonstration', () async {
    expect((await product('Brakina')).image, 'asset:assets/products/brakina.jpg');
    expect((await product('Poulet braisé')).image, 'asset:assets/products/poulet_braise.jpg');
    final b = await product('Brakina');
    await repo.saveProduct(owner, id: b.id, name: b.name, category: b.category, price: b.price, image: 'file:/tmp/x.jpg');
    expect((await product('Brakina')).image, 'file:/tmp/x.jpg');
    await repo.saveProduct(owner, id: b.id, name: b.name, category: b.category, price: b.price, clearImage: true);
    expect((await product('Brakina')).image, isNull);
  });

  test('historique des entrées de stock : qui, quand, note, filtres', () async {
    final castel = await product('Castel');
    await repo.saveProduct(owner, id: castel.id, name: castel.name, category: castel.category, price: castel.price, trackStock: true);
    await repo.adjustStock(owner, castel.id, 24, 'Livraison fournisseur', note: 'Brakina SA · bon 1452');
    await repo.adjustStock(owner, castel.id, -2, 'Casse / perte');
    await order({'Castel': 3});
    final entries = await repo.stockMovements(kind: StockKind.entry);
    expect(entries.single.delta, 24);
    expect(entries.single.note, 'Brakina SA · bon 1452');
    expect(entries.single.userName, owner.name);
    expect(entries.single.createdAt.difference(DateTime.now()).inMinutes.abs(), lessThan(1));
    expect((await repo.stockMovements(kind: StockKind.exit)).single.delta, -2);
    final sales = await repo.stockMovements(kind: StockKind.sale);
    expect(sales.single.delta, -3);
    expect(sales.single.orderNumber, isNotNull);
    expect(await repo.stockMovements(from: DateTime.now().add(const Duration(days: 1))), isEmpty);
    expect((await repo.stockMovements(productId: castel.id)).length, 3);
  });

  test('scan : retrouver une commande par QR (CMD:id) ou par numéro', () async {
    final id = await order({'Brakina': 1});
    final number = (await repo.orderDetail(id)).summary.number;
    expect((await repo.findOrder('CMD:$id'))!.id, id);
    expect((await repo.findOrder(number))!.id, id);
    expect(await repo.findOrder('CMD:inconnu'), isNull);
  });

  test('imprimante : type Bluetooth enregistré dans les paramètres', () async {
    expect((await repo.printerSettings()).type, PrinterType.none);
    await repo.saveSettings(owner, {'printer_type': 'bluetooth', 'bt_address': '66:22:AA:BB:CC:DD', 'bt_name': 'MTP-II'});
    final s = await repo.printerSettings();
    expect(s.type, PrinterType.bluetooth);
    expect(s.configured, isTrue);
    expect(s.label, 'Bluetooth MTP-II');
  });

  test('serveuse : attribution par la caisse, ventes, boissons et prime du mois', () async {
    final awa = await repo.createUser(owner, name: 'Awa', role: Role.server, pin: '1357');
    final fati = await repo.createUser(owner, name: 'Fati', role: Role.server, pin: '2468');
    final cashier = await repo.login((await repo.createUser(owner, name: 'Issa', role: Role.cashier, pin: '9753')).id, '9753');
    final awaU = await repo.login(awa.id, '1357');
    final cart = [CartLine(await product('Brakina'), 3), CartLine(await product('Poulet braisé'), 1)]; // 2400 + 3500
    // La caisse saisit pour Awa
    final o1 = await repo.createOrder(cashier, tableLabel: 'Table 2', lines: cart, serverId: awa.id);
    expect((await repo.orderDetail(o1)).summary.serverName, 'Awa');
    // Awa saisit elle-même
    await repo.createOrder(awaU, tableLabel: 'Table 4', lines: [CartLine(await product('Castel'), 2)]); // 2000
    // Awa ne peut pas mettre une commande au nom de Fati
    await expectLater(repo.createOrder(awaU, tableLabel: 'T', lines: cart, serverId: fati.id), throwsA(isA<PermissionDenied>()));
    // Commande annulée : exclue des ventes
    final o3 = await repo.createOrder(cashier, tableLabel: 'T', lines: [CartLine(await product('Castel'), 5)], serverId: fati.id);
    await repo.cancelOrder(owner, o3, 'Erreur de saisie');
    // Encaissement partiel d'une commande d'Awa
    await repo.openSession(owner, 0);
    await repo.pay(owner, req(o1, 5900, 'cash'));

    final now = DateTime.now();
    final sales = await repo.serverSales(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    final a = sales.singleWhere((x) => x.name == 'Awa');
    expect(a.orders, 2);
    expect(a.items, 6);
    expect(a.drinks, 5); // 3 Brakina + 2 Castel (poste Bar)
    expect(a.revenue, 7900);
    expect(a.collected, 5900);
    expect(sales.where((x) => x.name == 'Fati'), isEmpty);
    await repo.saveBonusRules(owner, const BonusRules(perDrink: 50, percent: 2));
    final rules = await repo.bonusRules();
    expect(rules.bonusFor(a), 5 * 50 + 158); // 2 % de 7 900 = 158
    final detail = await repo.serverProducts(awa.id, DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    expect(detail.first.name, 'Brakina');
    expect(detail.first.quantity, 3);
  });

  test('boutique : code-barres unique, recherche par scan, mode enregistré', () async {
    expect(await repo.businessMode(), BusinessMode.restaurant);
    await repo.saveSettings(owner, {'business_mode': 'shop'});
    expect(await repo.businessMode(), BusinessMode.shop);
    final list = await repo.products();
    final a = list[0], b = list[1];
    await repo.saveProduct(owner, id: a.id, name: a.name, category: a.category, price: a.price, station: a.station, barcode: '3017620422003\r\n');
    expect((await repo.productByBarcode(' 3017620422003 '))?.id, a.id);
    expect((await repo.productByBarcode('PRD:3017620422003'))?.id, a.id);
    expect(await repo.productByBarcode('0000'), isNull);
    // Même code sur un autre produit : refusé avec le nom du produit déjà lié.
    await expectLater(
      repo.saveProduct(owner, id: b.id, name: b.name, category: b.category, price: b.price, station: b.station, barcode: '3017620422003'),
      throwsA(isA<BusinessError>().having((e) => '$e', 'message', contains(a.name))),
    );
    // Sans paramètre barcode : le code est conservé ; '' le retire.
    await repo.saveProduct(owner, id: a.id, name: a.name, category: a.category, price: a.price + 50, station: a.station);
    expect((await repo.productByBarcode('3017620422003'))?.price, a.price + 50);
    await repo.saveProduct(owner, id: a.id, name: a.name, category: a.category, price: a.price, station: a.station, barcode: '');
    expect(await repo.productByBarcode('3017620422003'), isNull);
  });

  test('pharmacie : prix d\'achat, coût figé à la vente, marges et valeur du stock', () async {
    await repo.saveSettings(owner, {'business_mode': 'pharmacy'});
    expect(await repo.businessMode(), BusinessMode.pharmacy);
    expect(BusinessMode.pharmacy.directSale, isTrue);
    final id = await repo.saveProduct(owner, name: 'Paracétamol 500 mg', category: 'Antalgiques', price: 500, trackStock: true, cost: 300);
    var p = (await repo.products()).firstWhere((x) => x.id == id);
    expect(p.cost, 300);
    expect(p.margin, 200);
    expect(p.marginRate, 40);
    // Livraison avec nouveau prix d'achat : devient le prix d'achat du produit.
    await repo.adjustStock(owner, id, 100, 'Livraison fournisseur', note: 'Laborex', unitCost: 320);
    p = (await repo.products()).firstWhere((x) => x.id == id);
    expect(p.cost, 320);
    expect((await repo.stockMovements(productId: id)).first.unitCost, 320);
    await expectLater(repo.adjustStock(owner, id, -1, 'Casse / perte', unitCost: 10), throwsA(isA<BusinessError>()));
    // Produit sans prix d'achat
    final other = await repo.saveProduct(owner, name: 'Sirop toux', category: 'Sirops', price: 1500);
    await repo.openSession(owner, 0);
    final o1 = await repo.createOrder(owner, tableLabel: 'Vente directe', lines: [CartLine(p, 10), CartLine((await repo.products()).firstWhere((x) => x.id == other), 2)]);
    expect(o1, isNotEmpty);
    // Le prix d'achat change après la vente : le bénéfice déjà réalisé ne bouge pas.
    await repo.saveProduct(owner, id: id, name: p.name, category: p.category, price: 500, trackStock: true, cost: 450);
    final now = DateTime.now();
    final r = await repo.profitReport(owner, DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day + 1));
    final para = r.products.firstWhere((x) => x.productId == id);
    expect(para.quantity, 10);
    expect(para.revenue, 5000);
    expect(para.cost, 3200);
    expect(para.profit, 1800);
    expect(para.rate, 36);
    final sirop = r.products.firstWhere((x) => x.productId == other);
    expect(sirop.quantityWithoutCost, 2);
    expect(sirop.profit, 0);
    expect(r.revenue, 8000);
    expect(r.profit, 1800);
    expect(r.unitsWithoutCost, 2);
    expect(r.productsWithoutCost, greaterThanOrEqualTo(1));
    // Stock restant 90 au prix d'achat actuel (450) et de vente (500)
    expect(r.stockValueCost, greaterThanOrEqualTo(90 * 450));
    // Une serveuse ne voit pas les marges
    final awa = await repo.createUser(owner, name: 'Awa', role: Role.server, pin: '1357');
    await expectLater(repo.profitReport(awa, now, now), throwsA(isA<PermissionDenied>()));
  });
}
