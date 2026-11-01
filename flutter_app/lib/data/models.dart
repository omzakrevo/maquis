import '../core/permissions.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class AppUser {
  AppUser({required this.id, required this.name, required this.role, required this.active, required this.mustChangePin});
  final String id;
  final String name;
  final Role role;
  final bool active;
  final bool mustChangePin;

  bool can(Permission p) => active && roleCan(role, p);

  factory AppUser.fromMap(Map<String, Object?> m) =>
      AppUser(id: m['id'] as String, name: m['name'] as String, role: Role.parse(m['role'] as String), active: _i(m['active']) == 1, mustChangePin: _i(m['must_change_pin']) == 1);
}

enum Station {
  bar('Bar'),
  kitchen('Cuisine');

  const Station(this.label);
  final String label;
  static Station parse(String? v) => v == 'kitchen' ? Station.kitchen : Station.bar;
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.active = true,
    this.trackStock = false,
    this.stockQty = 0,
    this.alertQty = 0,
    this.station = Station.bar,
    this.image,
    this.barcode,
    this.cost,
  });
  final String id;
  final String name;
  final String category;
  final int price;

  /// `asset:assets/products/x.jpg` (photo embarquée) ou `file:/chemin` (photo de l'appareil).
  final String? image;

  /// Code-barres (EAN) ou contenu du QR collé sur le produit (mode boutique).
  final String? barcode;

  /// Prix d'achat unitaire (null = non renseigné).
  final int? cost;
  final bool active;
  final bool trackStock;
  final int stockQty;
  final int alertQty;
  final Station station;

  bool get lowStock => trackStock && stockQty <= alertQty;

  /// Marge unitaire et taux de marge sur le prix de vente (null sans prix d'achat).
  int? get margin => cost == null ? null : price - cost!;
  double? get marginRate => cost == null || price == 0 ? null : (price - cost!) * 100 / price;

  factory Product.fromMap(Map<String, Object?> m) => Product(
    id: m['id'] as String,
    name: m['name'] as String,
    category: m['category'] as String,
    price: _i(m['price_xof']),
    active: _i(m['active']) == 1,
    trackStock: _i(m['track_stock']) == 1,
    stockQty: _i(m['stock_qty']),
    alertQty: _i(m['alert_qty']),
    station: Station.parse(m['station'] as String?),
    image: m['image'] as String?,
    barcode: m['barcode'] as String?,
    cost: m['cost_xof'] as int?,
  );

  Product copyWith({String? name, String? category, int? price, bool? active, bool? trackStock, int? alertQty, Station? station}) => Product(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    price: price ?? this.price,
    active: active ?? this.active,
    trackStock: trackStock ?? this.trackStock,
    stockQty: stockQty,
    alertQty: alertQty ?? this.alertQty,
    station: station ?? this.station,
    image: image,
    barcode: barcode,
    cost: cost,
  );
}

class DiningTable {
  DiningTable({required this.id, required this.label, required this.active});
  final String id;
  final String label;
  final bool active;
  factory DiningTable.fromMap(Map<String, Object?> m) => DiningTable(id: m['id'] as String, label: m['label'] as String, active: _i(m['active']) == 1);
}

class CartLine {
  CartLine(this.product, this.quantity);
  final Product product;
  int quantity;
  int get total => product.price * quantity;
}

class OrderSummary {
  OrderSummary({required this.id, required this.number, required this.tableLabel, required this.status, required this.createdAt, required this.total, required this.paid, this.serverName, this.note});
  final String id;
  final String number;
  final String tableLabel;
  final String status;
  final DateTime createdAt;
  final int total;
  final int paid;
  final String? serverName;
  final String? note;
  int get balance => total - paid;

  factory OrderSummary.fromMap(Map<String, Object?> m) => OrderSummary(
    id: m['id'] as String,
    number: m['number'] as String,
    tableLabel: (m['table_label'] as String?)?.trim().isNotEmpty == true ? m['table_label'] as String : 'Comptoir',
    status: m['status'] as String,
    createdAt: _d(m['created_at'])!,
    total: _i(m['total']),
    paid: _i(m['paid']),
    serverName: m['server_name'] as String?,
    note: m['note'] as String?,
  );
}

class OrderItem {
  OrderItem({required this.name, required this.price, required this.quantity, required this.station});
  final String name;
  final int price;
  final int quantity;
  final Station station;
  int get total => price * quantity;
  factory OrderItem.fromMap(Map<String, Object?> m) =>
      OrderItem(name: m['name_snapshot'] as String, price: _i(m['price_xof']), quantity: _i(m['quantity']), station: Station.parse(m['station'] as String?));
}

class PaymentRecord {
  PaymentRecord({required this.amount, required this.method, required this.createdAt, this.reference, this.received, this.change});
  final int amount;
  final String method;
  final DateTime createdAt;
  final String? reference;
  final int? received;
  final int? change;
  factory PaymentRecord.fromMap(Map<String, Object?> m) => PaymentRecord(
    amount: _i(m['amount_xof']),
    method: m['method'] as String,
    createdAt: _d(m['created_at'])!,
    reference: m['reference'] as String?,
    received: (m['received_xof'] as num?)?.toInt(),
    change: (m['change_xof'] as num?)?.toInt(),
  );
}

class OrderDetail {
  OrderDetail(this.summary, this.items, this.payments);
  final OrderSummary summary;
  final List<OrderItem> items;
  final List<PaymentRecord> payments;
}

const paymentMethodLabels = {'cash': 'Espèces', 'mobile_money': 'Mobile Money', 'card': 'Carte', 'credit': 'Avoir'};

String methodLabel(String m) => paymentMethodLabels[m] ?? m;

class PaymentRequest {
  PaymentRequest({required this.orderId, required this.amount, required this.method, required this.idempotencyKey, this.reference, this.receivedCash, this.changeAsCredit = false, this.creditCode});
  final String orderId;
  final int amount;
  final String method;
  final String idempotencyKey;
  final String? reference;
  final int? receivedCash;
  final bool changeAsCredit;
  final String? creditCode;
}

class PaymentResult {
  PaymentResult({required this.orderClosed, required this.change, this.issuedCreditCode, this.issuedCreditAmount = 0, this.duplicate = false});
  final bool orderClosed;
  final int change;
  final String? issuedCreditCode;
  final int issuedCreditAmount;
  final bool duplicate;
}

class Credit {
  Credit({required this.id, required this.codeHint, required this.initial, required this.balance, required this.status, required this.createdAt, this.customerName, this.reason});
  final String id;
  final String codeHint;
  final int initial;
  final int balance;
  final String status;
  final DateTime createdAt;
  final String? customerName;
  final String? reason;
  factory Credit.fromMap(Map<String, Object?> m) => Credit(
    id: m['id'] as String,
    codeHint: (m['code_hint'] as String?) ?? '',
    initial: _i(m['initial_xof']),
    balance: _i(m['balance_xof']),
    status: (m['status'] as String?) ?? 'active',
    createdAt: _d(m['created_at']) ?? DateTime.now(),
    customerName: m['customer_name'] as String?,
    reason: m['reason'] as String?,
  );
}

class IssuedCredit {
  IssuedCredit(this.credit, this.code);
  final Credit credit;
  final String code;
}

class CashSession {
  CashSession({required this.id, required this.openedAt, required this.openingFloat, required this.status, this.closedAt, this.openedBy, this.closedBy, this.reportJson});
  final String id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int openingFloat;
  final String status;
  final String? openedBy;
  final String? closedBy;
  final String? reportJson;
  factory CashSession.fromMap(Map<String, Object?> m) => CashSession(
    id: m['id'] as String,
    openedAt: _d(m['opened_at'])!,
    closedAt: _d(m['closed_at']),
    openingFloat: _i(m['opening_float_xof']),
    status: m['status'] as String,
    openedBy: m['opened_by_name'] as String?,
    closedBy: m['closed_by_name'] as String?,
    reportJson: m['report_json'] as String?,
  );
}

class ProductSale {
  ProductSale(this.name, this.quantity, this.total);
  final String name;
  final int quantity;
  final int total;
  Map<String, Object> toJson() => {'name': name, 'quantity': quantity, 'total': total};
  factory ProductSale.fromJson(Map<String, dynamic> j) => ProductSale(j['name'] as String, _i(j['quantity']), _i(j['total']));
}

/// Rapport de clôture (ticket Z) d'une session de caisse.
class ZReport {
  ZReport({
    required this.sessionId,
    required this.openedAt,
    required this.closedAt,
    required this.openedBy,
    required this.closedBy,
    required this.openingFloat,
    required this.byMethod,
    required this.paymentsCount,
    required this.ordersClosed,
    required this.ordersCancelled,
    required this.cancelledTotal,
    required this.openOrdersCount,
    required this.openOrdersBalance,
    required this.creditsIssuedFromChange,
    required this.creditsIssuedManual,
    required this.creditsRedeemed,
    required this.expectedCash,
    required this.countedCash,
    required this.topProducts,
  });
  final String sessionId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String openedBy;
  final String? closedBy;
  final int openingFloat;
  final Map<String, int> byMethod;
  final int paymentsCount;
  final int ordersClosed;
  final int ordersCancelled;
  final int cancelledTotal;
  final int openOrdersCount;
  final int openOrdersBalance;
  final int creditsIssuedFromChange;
  final int creditsIssuedManual;
  final int creditsRedeemed;
  final int expectedCash;
  final int? countedCash;
  final List<ProductSale> topProducts;

  int get totalCollected => byMethod.values.fold(0, (a, b) => a + b);
  int? get difference => countedCash == null ? null : countedCash! - expectedCash;

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'opened_at': openedAt.toUtc().toIso8601String(),
    'closed_at': closedAt?.toUtc().toIso8601String(),
    'opened_by': openedBy,
    'closed_by': closedBy,
    'opening_float': openingFloat,
    'by_method': byMethod,
    'payments_count': paymentsCount,
    'orders_closed': ordersClosed,
    'orders_cancelled': ordersCancelled,
    'cancelled_total': cancelledTotal,
    'open_orders_count': openOrdersCount,
    'open_orders_balance': openOrdersBalance,
    'credits_issued_change': creditsIssuedFromChange,
    'credits_issued_manual': creditsIssuedManual,
    'credits_redeemed': creditsRedeemed,
    'expected_cash': expectedCash,
    'counted_cash': countedCash,
    'top_products': topProducts.map((p) => p.toJson()).toList(),
  };

  factory ZReport.fromJson(Map<String, dynamic> j) => ZReport(
    sessionId: j['session_id'] as String,
    openedAt: DateTime.parse(j['opened_at'] as String).toLocal(),
    closedAt: j['closed_at'] == null ? null : DateTime.parse(j['closed_at'] as String).toLocal(),
    openedBy: j['opened_by'] as String,
    closedBy: j['closed_by'] as String?,
    openingFloat: _i(j['opening_float']),
    byMethod: (j['by_method'] as Map).map((k, v) => MapEntry(k as String, _i(v))),
    paymentsCount: _i(j['payments_count']),
    ordersClosed: _i(j['orders_closed']),
    ordersCancelled: _i(j['orders_cancelled']),
    cancelledTotal: _i(j['cancelled_total']),
    openOrdersCount: _i(j['open_orders_count']),
    openOrdersBalance: _i(j['open_orders_balance']),
    creditsIssuedFromChange: _i(j['credits_issued_change']),
    creditsIssuedManual: _i(j['credits_issued_manual']),
    creditsRedeemed: _i(j['credits_redeemed']),
    expectedCash: _i(j['expected_cash']),
    countedCash: (j['counted_cash'] as num?)?.toInt(),
    topProducts: ((j['top_products'] as List?) ?? []).map((e) => ProductSale.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

enum StockKind {
  entry('Entrées'),
  exit('Sorties'),
  sale('Ventes'),
  count('Inventaires'),
  cancel('Annulations');

  const StockKind(this.label);
  final String label;
}

class StockMovement {
  StockMovement({required this.productName, required this.delta, required this.reason, required this.createdAt, this.userName, this.note, this.orderNumber, this.productImage, this.unitCost});
  final int? unitCost;
  final String productName;
  final int delta;
  final String reason;
  final DateTime createdAt;
  final String? userName;
  final String? note;
  final String? orderNumber;
  final String? productImage;

  StockKind get kind {
    if (reason == 'Vente') return StockKind.sale;
    if (reason == 'Annulation commande') return StockKind.cancel;
    if (reason == 'Inventaire') return StockKind.count;
    return delta > 0 ? StockKind.entry : StockKind.exit;
  }

  factory StockMovement.fromMap(Map<String, Object?> m) => StockMovement(
    productName: m['product_name'] as String,
    delta: _i(m['quantity_delta']),
    reason: m['reason'] as String,
    createdAt: _d(m['created_at'])!,
    userName: m['user_name'] as String?,
    note: m['note'] as String?,
    orderNumber: m['order_number'] as String?,
    productImage: m['product_image'] as String?,
    unitCost: m['unit_cost_xof'] as int?,
  );
}

class AuditEntry {
  AuditEntry({required this.action, required this.objectType, required this.createdAt, this.userName, this.details});
  final String action;
  final String objectType;
  final DateTime createdAt;
  final String? userName;
  final String? details;
  factory AuditEntry.fromMap(Map<String, Object?> m) =>
      AuditEntry(action: m['action'] as String, objectType: m['object_type'] as String, createdAt: _d(m['created_at'])!, userName: m['user_name'] as String?, details: m['details'] as String?);
}

enum PrinterType { none, network, bluetooth }

/// Ce qui s'imprime automatiquement après la validation d'une commande.
enum AfterOrderPrint {
  client('Ticket client'),
  kitchen('Bons bar/cuisine'),
  both('Les deux'),
  none('Rien');

  const AfterOrderPrint(this.label);
  final String label;
  bool get clientTicket => this == client || this == both;
  bool get preparation => this == kitchen || this == both;
}

class PrinterSettings {
  PrinterSettings({
    required this.type,
    required this.host,
    required this.port,
    required this.paperWidth,
    required this.stripAccents,
    required this.codePage,
    this.btAddress = '',
    this.btName = '',
    this.qrAsImage = true,
    this.afterOrder = AfterOrderPrint.client,
  });
  final PrinterType type;
  final String host;
  final int port;
  final int paperWidth; // 58 ou 80 mm
  final bool stripAccents;
  final int codePage;
  final String btAddress;
  final String btName;
  final bool qrAsImage;
  final AfterOrderPrint afterOrder;
  int get charsPerLine => paperWidth >= 80 ? 48 : 32;
  bool get configured => switch (type) {
    PrinterType.network => host.trim().isNotEmpty,
    PrinterType.bluetooth => btAddress.trim().isNotEmpty,
    PrinterType.none => false,
  };
  String get label => switch (type) {
    PrinterType.network => 'Réseau $host:$port',
    PrinterType.bluetooth => 'Bluetooth ${btName.isEmpty ? btAddress : btName}',
    PrinterType.none => 'Aucune',
  };
}

class ShopInfo {
  ShopInfo({required this.name, required this.address, required this.phone, required this.footer});
  final String name;
  final String address;
  final String phone;
  final String footer;
}

/// Ventes d'une serveuse sur une période.
class ServerSales {
  ServerSales({required this.userId, required this.name, required this.role, required this.orders, required this.items, required this.drinks, required this.revenue, required this.collected});
  final String userId;
  final String name;
  final Role role;
  final int orders;
  final int items;
  final int drinks;
  final int revenue;
  final int collected;
}

/// Règle de prime : montant fixe par boisson vendue + pourcentage du chiffre d'affaires.
class BonusRules {
  const BonusRules({this.perDrink = 0, this.percent = 0});
  final int perDrink;
  final double percent;
  bool get isSet => perDrink > 0 || percent > 0;
  int bonusFor(ServerSales s) => s.drinks * perDrink + (s.revenue * percent / 100).round();
}

/// Type d'établissement : change l'écran de vente.
enum BusinessMode {
  restaurant('Maquis / Restaurant / Bar'),
  shop('Boutique / Alimentation'),
  pharmacy('Pharmacie / Dépôt pharmaceutique');

  const BusinessMode(this.label);
  final String label;

  /// Vente directe au comptoir (scan → panier → encaissement), sans table ni serveuse.
  bool get directSale => this != BusinessMode.restaurant;
  static BusinessMode parse(String? v) => BusinessMode.values.firstWhere((m) => m.name == v, orElse: () => BusinessMode.restaurant);
}

/// Marge d'un produit sur une période (ventes non annulées).
class ProductProfit {
  ProductProfit({required this.productId, required this.name, required this.quantity, required this.revenue, required this.cost, required this.quantityWithoutCost});
  final String productId;
  final String name;
  final int quantity;
  final int revenue;

  /// Coût d'achat des unités dont le prix d'achat était connu au moment de la vente.
  final int cost;

  /// Unités vendues sans prix d'achat : leur bénéfice n'est pas calculable.
  final int quantityWithoutCost;
  int get revenueWithCost => quantity == 0 ? 0 : (revenue * (quantity - quantityWithoutCost) / quantity).round();
  int get profit => revenueWithCost - cost;
  double? get rate => revenueWithCost == 0 ? null : profit * 100 / revenueWithCost;
}

class ProfitReport {
  ProfitReport({required this.products, required this.stockValueCost, required this.stockValueSale, required this.productsWithoutCost});
  final List<ProductProfit> products;

  /// Valeur du stock au prix d'achat et au prix de vente (produits suivis en stock).
  final int stockValueCost;
  final int stockValueSale;

  /// Produits actifs sans prix d'achat renseigné.
  final int productsWithoutCost;
  int get revenue => products.fold(0, (a, p) => a + p.revenue);
  int get revenueWithCost => products.fold(0, (a, p) => a + p.revenueWithCost);
  int get cost => products.fold(0, (a, p) => a + p.cost);
  int get profit => revenueWithCost - cost;
  double? get rate => revenueWithCost == 0 ? null : profit * 100 / revenueWithCost;
  int get unitsWithoutCost => products.fold(0, (a, p) => a + p.quantityWithoutCost);
}
