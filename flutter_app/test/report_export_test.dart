import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maquis_resto_pro/data/database.dart';
import 'package:maquis_resto_pro/data/models.dart';
import 'package:maquis_resto_pro/data/pos_repository.dart';
import 'package:maquis_resto_pro/data/report_export.dart';
import 'package:maquis_resto_pro/printing/pdf_writer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  sqfliteFfiInit();

  test('libellés de période', () {
    expect(reportPeriodLabel(DateTime(2026, 11, 9), DateTime(2026, 11, 10)), 'Journée du 09/11/2026');
    expect(reportPeriodLabel(DateTime(2026, 11, 1), DateTime(2026, 12, 1)), 'Novembre 2026');
    expect(reportPeriodLabel(DateTime(2026, 11, 3), DateTime(2026, 11, 8)), 'Du 03/11/2026 au 07/11/2026');
  });

  test('PDF minimal valide avec accents', () {
    final d = PdfDoc()..addPage();
    d.text(40, 40, 'Pharmacie « Élise » — 1 500 F, côté (test) \\ ok');
    final b = d.save();
    expect(String.fromCharCodes(b.take(8)), '%PDF-1.4');
    expect(String.fromCharCodes(b.skip(b.length - 6)), '%%EOF\n');
    expect(PdfDoc.textWidth('é', 10), greaterThan(0));
  });

  test('rapport exporté en PDF, Excel et ticket', () async {
    final repo = PosRepository(await openPosDatabase(databaseFactoryFfi, inMemoryDatabasePath));
    final owner = await repo.login((await repo.users()).single.id, '0000');
    await repo.saveSettings(owner, {'business_mode': 'pharmacy', 'shop_name': 'Pharmacie du Progrès'});
    await repo.loadDemoCatalog(owner);
    final meds = await repo.products();
    await repo.openSession(owner, 0);
    for (var i = 0; i < 12; i++) {
      final lines = [CartLine(meds[i % meds.length], 1 + i % 3), CartLine(meds[(i * 5) % meds.length], 1)];
      final id = await repo.createOrder(owner, tableLabel: 'Vente directe', lines: lines);
      final total = lines.fold(0, (a, l) => a + l.product.price * l.quantity);
      await repo.pay(owner, PaymentRequest(orderId: id, amount: total, method: i % 3 == 0 ? 'mobile_money' : 'cash', reference: 'OM$i', idempotencyKey: const Uuid().v4()));
    }
    final now = DateTime.now();
    final r = await repo.salesReport(owner, DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    final shop = await repo.shopInfo();
    final pdf = salesReportPdf(shop, r, accentRgb: 0x0B8A62);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final xlsx = salesReportXlsx(shop, r);
    final book = Excel.decodeBytes(xlsx);
    expect(book.tables.keys, containsAll(['Résumé', 'Par jour', 'Par heure', 'Articles', 'Catégories', 'Vendeurs', 'Stock bas']));
    final ticket = salesReportTicket(shop, r).toPlainText(32);
    expect(ticket, contains('RAPPORT DES VENTES'));
    expect(ticket, contains('Nombre de ventes'));
    final out = Platform.environment['SHOTS'];
    if (out != null) {
      File('$out/rapport.pdf').writeAsBytesSync(pdf);
      File('$out/rapport.xlsx').writeAsBytesSync(xlsx);
      File('$out/rapport_ticket.txt').writeAsStringSync(ticket);
    }
    await repo.db.close();
  });
}
