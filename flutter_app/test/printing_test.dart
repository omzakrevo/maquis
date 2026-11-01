import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maquis_resto_pro/core/money.dart';
import 'package:maquis_resto_pro/data/models.dart';
import 'package:maquis_resto_pro/printing/bluetooth_printer.dart';
import 'package:maquis_resto_pro/printing/escpos.dart';
import 'package:maquis_resto_pro/printing/print_service.dart';
import 'package:maquis_resto_pro/printing/network_printer.dart';
import 'package:maquis_resto_pro/printing/ticket.dart';
import 'package:maquis_resto_pro/printing/ticket_builder.dart';

final shop = ShopInfo(name: 'Maquis Le Baobab', address: 'Ouaga 2000', phone: '70 00 00 00', footer: 'Merci !');

OrderDetail sampleOrder({int paid = 0}) => OrderDetail(
  OrderSummary(id: 'x', number: '261021-007', tableLabel: 'Table 3', status: 'open', createdAt: DateTime(2026, 10, 21, 20, 15), total: 5100, paid: paid, serverName: 'Awa'),
  [OrderItem(name: 'Brakina', price: 800, quantity: 2, station: Station.bar), OrderItem(name: 'Poulet braisé entier avec attiéké et alloco', price: 3500, quantity: 1, station: Station.kitchen)],
  [if (paid > 0) PaymentRecord(amount: paid, method: 'cash', createdAt: DateTime(2026, 10, 21, 21), received: 10000, change: 10000 - paid)],
);

void main() {
  test('formatage FCFA', () {
    expect(fcfa(0), '0 F');
    expect(fcfa(800), '800 F');
    expect(fcfa(1500), '1 500 F');
    expect(fcfa(1234567), '1 234 567 F');
    expect(fcfa(-2500), '-2 500 F');
    expect(parseFcfa('1 500'), 1500);
    expect(parseFcfa('2.000F'), 2000);
    expect(parseFcfa('-3'), isNull);
    expect(parseFcfa('abc'), isNull);
  });

  test('mise en page 32 colonnes : aucune ligne ne dépasse', () {
    final t = customerReceipt(shop, sampleOrder(paid: 5100), cashierName: 'Issa');
    final lines = t.layout(32);
    for (final l in lines) {
      expect(l.length, lessThanOrEqualTo(32), reason: l);
    }
    final text = lines.join('\n');
    expect(text, contains('REÇU'));
    expect(text, contains('5 100 F'));
    expect(text, contains('SOLDÉ'));
    expect(lines.any((l) => l.contains('2 x 800 F') && l.endsWith('1 600 F')), isTrue, reason: 'prix unitaire et total de ligne');
    expect(text, contains('MERCI'));
  });

  test('addition avec reste à payer', () {
    final text = customerReceipt(shop, sampleOrder(paid: 0)).toPlainText(48);
    expect(text, contains('ADDITION'));
    expect(text, isNot(contains('SOLDÉ')));
  });

  test('encodage accents : CP858 ou suppression', () {
    expect(encodeText('Café', stripAccentsMode: false), [0x43, 0x61, 0x66, 0x82]);
    expect(encodeText('Café', stripAccentsMode: true), 'Cafe'.codeUnits);
    expect(stripAccents('Poulet braisé, attiéké… à côté'), 'Poulet braise, attieke... a cote');
    expect(encodeText('漢', stripAccentsMode: false), [0x3F]);
  });

  test('ESC/POS : init, coupe, QR', () {
    final t = Ticket('t', [TextLine('Bonjour', bold: true), QrCode('AVOIR:ABCD-EFGH')]);
    final bytes = EscPosEncoder(charsPerLine: 32, qrAsImage: false).encode(t);
    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x03]);
    final asString = String.fromCharCodes(bytes);
    expect(asString, contains('Bonjour'));
    expect(asString, contains('AVOIR:ABCD-EFGH'));
  });

  test('bons de préparation séparés bar / cuisine', () {
    final beer = Product(id: '1', name: 'Brakina', category: 'Bières', price: 800);
    final dish = Product(id: '2', name: 'Riz gras', category: 'Plats', price: 1000, station: Station.kitchen);
    final split = splitByStation([CartLine(beer, 2), CartLine(dish, 1), CartLine(beer, 0)]);
    expect(split.keys, containsAll([Station.bar, Station.kitchen]));
    expect(split[Station.bar]!.length, 1);
    final text = preparationTicket(station: Station.kitchen, orderNumber: '261021-001', tableLabel: 'Table 2', lines: split[Station.kitchen]!, note: 'Sans piment').toPlainText(32);
    expect(text, contains('Riz gras'));
    expect(text, contains('Sans piment'));
    expect(text, isNot(contains('F'))); // pas de prix sur un bon cuisine
  });

  test('envoi réseau TCP 9100 vers une fausse imprimante', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <int>[];
    final done = server.first.then((client) async {
      await for (final chunk in client) {
        received.addAll(chunk);
      }
    });
    final payload = Uint8List.fromList([0x1B, 0x40, 0x41, 0x0A]);
    await NetworkPrinter('127.0.0.1', port: server.port).send(payload);
    await done.timeout(const Duration(seconds: 5));
    await server.close();
    expect(received, payload);
  });

  test('imprimante injoignable : message clair', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    await expectLater(NetworkPrinter('127.0.0.1', port: port, timeout: const Duration(seconds: 2)).send(Uint8List(1)), throwsA(isA<PrinterException>()));
  });

  test('addition et reçu portent un QR pour le scan', () {
    final t = customerReceipt(shop, sampleOrder());
    expect(t.elements.whereType<QrCode>().single.data, 'CMD:261021-007');
    final text = t.toPlainText(32);
    expect(text, contains('[ QR code ]'));
    expect(text, contains('Scannez à la caisse pour payer'));
  });

  test('choix du transport selon le type d\'imprimante', () {
    PrinterSettings ps(PrinterType t) => PrinterSettings(type: t, host: '192.168.1.50', port: 9100, paperWidth: 58, stripAccents: true, codePage: 19, btAddress: 'AA:BB');
    expect(PrintService.defaultTransport(ps(PrinterType.bluetooth)), isA<BluetoothPrinter>());
    expect(PrintService.defaultTransport(ps(PrinterType.network)), isA<NetworkPrinter>());
  });

  test('ticket de commande : prix unitaires, total en gros, remerciement, QR', () {
    final t = orderTicket(shop, sampleOrder());
    final text = t.toPlainText(32);
    expect(text, contains('ADDITION'));
    expect(text, contains('N O N   P A Y É'));
    expect(text, contains('Servi par : Awa'));
    expect(text, contains('1 x 3 500 F'));
    expect(text, contains('T O T A L   5   1 0 0   F')); // double largeur dans l'aperçu
    expect(text, contains('RESTE À PAYER'));
    expect(text, contains('MERCI !'));
    expect(text, contains('Scannez à la caisse pour payer'));
    final big = t.elements.whereType<TextLine>().firstWhere((l) => l.text.startsWith('TOTAL'));
    expect(big.big && big.bold, isTrue);
  });

  test('QR en image raster (GS v 0) compatible toutes imprimantes', () {
    final m = qrMatrix('CMD:261021-007');
    expect(m.length, 21); // version 1
    final raster = qrRaster('CMD:261021-007', paperDots: 384);
    expect(raster.sublist(0, 4), [0x1D, 0x76, 0x30, 0x00]);
    expect(raster[4] | (raster[5] << 8), 48); // 384 points = 48 octets par ligne
    final withImage = EscPosEncoder(charsPerLine: 32).encode(Ticket('t', [QrCode('X')]));
    final native = EscPosEncoder(charsPerLine: 32, qrAsImage: false).encode(Ticket('t', [QrCode('X')]));
    bool has(List<int> b, List<int> seq) => String.fromCharCodes(b).contains(String.fromCharCodes(seq));
    expect(has(withImage, [0x1D, 0x76, 0x30]), isTrue);
    expect(has(withImage, [0x1D, 0x28, 0x6B]), isFalse);
    expect(has(native, [0x1D, 0x28, 0x6B]), isTrue);
  });

  test('ligne date + serveur trop longue : pas de date coupée', () {
    final lines = pairLines('21/10/2026 10:12', 'Serveur : Propriétaire', 32);
    expect(lines, ['21/10/2026 10:12', '          Serveur : Propriétaire']);
    for (final l in lines) {
      expect(l.length, lessThanOrEqualTo(32));
    }
  });

  test('ticket de commande : prix unitaire, total de ligne, total, QR, remerciement', () {
    final t = orderTicket(shop, sampleOrder());
    final text = t.toPlainText(32);
    expect(text, contains('ADDITION'));
    expect(text, contains('N O N   P A Y É'));
    expect(text, contains('Servi par : Awa'));
    expect(text, contains('2 x 800 F'));
    expect(text, contains('1 600 F'));
    expect(text, contains('MERCI !'));
    expect(t.elements.whereType<QrCode>().single.data, 'CMD:261021-007');
    for (final l in t.layout(32)) {
      expect(l.length, lessThanOrEqualTo(32), reason: l);
    }
  });
}
