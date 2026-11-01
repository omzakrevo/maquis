import '../core/money.dart';
import '../data/models.dart';
import 'ticket.dart';

String _dt(DateTime d) => '${'${d.day}'.padLeft(2, '0')}/${'${d.month}'.padLeft(2, '0')}/${d.year} ${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';

List<TicketElement> _header(ShopInfo shop) => [
  TextLine(shop.name, align: TAlign.center, bold: true, big: true),
  if (shop.address.isNotEmpty) TextLine(shop.address, align: TAlign.center),
  if (shop.phone.isNotEmpty) TextLine('Tél : ${shop.phone}', align: TAlign.center),
  Separator(),
];

/// Ticket client : « TICKET DE COMMANDE » (juste après validation), « ADDITION »
/// (avant paiement) ou « REÇU » (soldé). Chaque ligne montre le prix unitaire et
/// le total ; total général en gros caractères ; QR pour retrouver/encaisser ;
/// message de remerciement.
Ticket customerReceipt(ShopInfo shop, OrderDetail d, {String? cashierName, String? heading}) {
  final s = d.summary;
  final paidInFull = s.balance <= 0 && d.items.isNotEmpty;
  final title = heading ?? (paidInFull ? 'REÇU' : 'ADDITION');
  final count = d.items.fold<int>(0, (a, i) => a + i.quantity);
  final thanks = shop.footer.trim().isEmpty ? 'Merci de votre visite !' : shop.footer.trim();
  return Ticket('${title[0]}${title.substring(1).toLowerCase()} ${s.number}', [
    ..._header(shop),
    TextLine(title, align: TAlign.center, bold: true),
    // Statut de paiement en gros caractères.
    TextLine(paidInFull ? 'PAYÉ' : (d.payments.isEmpty ? 'NON PAYÉ' : 'PAIEMENT PARTIEL'), align: TAlign.center, bold: true, big: true),
    PairLine('N° ${s.number}', s.tableLabel, bold: true),
    TextLine(_dt(s.createdAt)),
    if (s.serverName != null) TextLine('Servi par : ${s.serverName}', bold: true),
    Separator(),
    for (final i in d.items) ...[TextLine(i.name, bold: true), PairLine('   ${i.quantity} x ${fcfa(i.price)}', fcfa(i.total))],
    Separator(),
    PairLine('Nombre d\'articles', '$count'),
    TextLine('TOTAL ${fcfa(s.total)}', align: TAlign.right, bold: true, big: true),
    if (d.payments.isNotEmpty) ...[
      Separator('.'),
      for (final p in d.payments) ...[
        PairLine('${methodLabel(p.method)}${p.reference != null ? ' (${p.reference})' : ''}', fcfa(p.amount)),
        if (p.method == 'cash' && (p.received ?? 0) > p.amount)
          (p.change ?? 0) > 0 ? PairLine('   Reçu ${fcfa(p.received!)}', 'Rendu ${fcfa(p.change!)}') : PairLine('   Reçu ${fcfa(p.received!)}', 'Avoir ${fcfa(p.received! - p.amount)}'),
      ],
      PairLine(paidInFull ? 'SOLDÉ' : 'RESTE À PAYER', fcfa(s.balance < 0 ? 0 : s.balance), bold: true),
    ] else if (!paidInFull)
      PairLine('RESTE À PAYER', fcfa(s.balance), bold: true),
    if (cashierName != null) TextLine('Caisse : $cashierName'),
    Separator(),
    // QR scanné à la caisse pour retrouver la commande et l'encaisser en un geste.
    QrCode('CMD:${s.number}', size: 5),
    TextLine(paidInFull ? 'Scannez pour retrouver ce reçu' : 'Scannez à la caisse pour payer', align: TAlign.center),
    Feed(),
    TextLine(thanks.toUpperCase(), align: TAlign.center, bold: true),
    TextLine('À très bientôt !', align: TAlign.center),
    TextLine('Montants en FCFA', align: TAlign.center),
  ]);
}

/// Ticket client imprimé juste après la validation d'une commande.
Ticket orderTicket(ShopInfo shop, OrderDetail d) => customerReceipt(shop, d, heading: 'ADDITION');

/// Bon de préparation pour le bar ou la cuisine (sans prix).
Ticket preparationTicket({required Station station, required String orderNumber, required String tableLabel, required List<CartLine> lines, String? note, String? serverName, bool addition = false}) {
  return Ticket('${station.label} $orderNumber', [
    TextLine(station.label.toUpperCase(), align: TAlign.center, bold: true, big: true),
    if (addition) TextLine('*** AJOUT ***', align: TAlign.center, bold: true),
    TextLine(tableLabel, align: TAlign.center, big: true),
    PairLine('N° $orderNumber', _dt(DateTime.now())),
    if (serverName != null) TextLine('Serveur : $serverName'),
    Separator(),
    for (final l in lines) TextLine('${l.quantity}  x  ${l.product.name}', bold: true),
    if (note != null && note.trim().isNotEmpty) ...[Separator(), TextLine('Note : $note')],
    Feed(),
  ]);
}

/// Bon d'avoir remis au client : le code n'est visible qu'ici.
Ticket creditVoucher(ShopInfo shop, IssuedCredit issued) {
  final c = issued.credit;
  return Ticket('Avoir ${issued.code}', [
    ..._header(shop),
    TextLine('BON D\'AVOIR', align: TAlign.center, bold: true, big: true),
    TextLine(fcfa(c.initial), align: TAlign.center, bold: true, big: true),
    Feed(),
    QrCode('AVOIR:${issued.code}'),
    TextLine(issued.code, align: TAlign.center, bold: true, big: true),
    Separator(),
    if (c.customerName != null) TextLine('Client : ${c.customerName}'),
    if (c.reason != null) TextLine('Motif : ${c.reason}'),
    TextLine('Émis le ${_dt(c.createdAt)}'),
    TextLine('À présenter lors d\'un prochain achat. Utilisable en une ou plusieurs fois. Non remboursable en espèces.'),
    Feed(),
  ]);
}

Ticket zReportTicket(ShopInfo shop, ZReport z) {
  final diff = z.difference;
  return Ticket(z.closedAt == null ? 'Rapport X' : 'Rapport Z', [
    ..._header(shop),
    TextLine(z.closedAt == null ? 'RAPPORT X (en cours)' : 'RAPPORT Z - CLÔTURE', align: TAlign.center, bold: true),
    TextLine('Ouverture : ${_dt(z.openedAt)} (${z.openedBy})'),
    if (z.closedAt != null) TextLine('Clôture   : ${_dt(z.closedAt!)} (${z.closedBy ?? '?'})'),
    Separator(),
    TextLine('ENCAISSEMENTS', bold: true),
    for (final m in ['cash', 'mobile_money', 'card', 'credit'])
      if (z.byMethod.containsKey(m)) PairLine('  ${methodLabel(m)}', fcfa(z.byMethod[m]!)),
    PairLine('Total encaissé', fcfa(z.totalCollected), bold: true),
    PairLine('Nb paiements', '${z.paymentsCount}'),
    PairLine('Commandes soldées', '${z.ordersClosed}'),
    PairLine('Commandes annulées', '${z.ordersCancelled} (${fcfa(z.cancelledTotal)})'),
    PairLine('Impayés en cours', '${z.openOrdersCount} (${fcfa(z.openOrdersBalance)})'),
    Separator(),
    TextLine('AVOIRS', bold: true),
    PairLine('  Monnaie en avoir', fcfa(z.creditsIssuedFromChange)),
    PairLine('  Avoirs manuels émis', fcfa(z.creditsIssuedManual)),
    PairLine('  Avoirs utilisés', fcfa(z.creditsRedeemed)),
    Separator(),
    TextLine('ESPÈCES', bold: true),
    PairLine('  Fond de caisse', fcfa(z.openingFloat)),
    PairLine('  Attendu en caisse', fcfa(z.expectedCash), bold: true),
    if (z.countedCash != null) PairLine('  Compté', fcfa(z.countedCash!)),
    if (diff != null) PairLine(diff == 0 ? '  Écart' : (diff > 0 ? '  Excédent' : '  Manquant'), fcfa(diff), bold: true),
    if (z.topProducts.isNotEmpty) ...[Separator(), TextLine('VENTES PAR ARTICLE', bold: true), for (final p in z.topProducts) PairLine('  ${p.quantity} x ${p.name}', fcfa(p.total))],
    Feed(),
    TextLine('Imprimé le ${_dt(DateTime.now())}', align: TAlign.center),
  ]);
}

/// Regroupe les lignes d'un panier par poste (bar/cuisine) pour les bons.
Map<Station, List<CartLine>> splitByStation(List<CartLine> lines) {
  final out = <Station, List<CartLine>>{};
  for (final l in lines.where((l) => l.quantity > 0)) {
    out.putIfAbsent(l.product.station, () => []).add(l);
  }
  return out;
}
