@Tags(['petit-ecran'])
library;

// Petits écrans de caisse (terminaux POS 5", téléphones) : chaque écran
// principal s'affiche sans débordement. Avec SHOTS=<dossier>, des captures
// PNG sont aussi enregistrées (polices réelles chargées).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maquis_resto_pro/app.dart';
import 'package:maquis_resto_pro/core/permissions.dart';
import 'package:maquis_resto_pro/data/database.dart';
import 'package:maquis_resto_pro/data/models.dart';
import 'package:maquis_resto_pro/data/pos_repository.dart';
import 'package:maquis_resto_pro/ui/theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show settle;

final shotsDir = Platform.environment['SHOTS'];
final boundary = GlobalKey();

// Les vraies polices (Roboto) : la police de test par défaut, aux glyphes carrés
// très larges, ne représente pas ce qu'affiche le terminal.
Future<void> loadRealFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f').readAsBytesSync();
      l.addFont(Future.value(ByteData.view(b.buffer)));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  await load('monospace', ['RobotoMono-Regular.ttf'].where((f) => File('$dir/$f').existsSync()).toList());
}

Future<void> shot(WidgetTester tester, String name) async {
  if (shotsDir == null) return;
  await tester.pump(const Duration(milliseconds: 600));
  await tester.runAsync(() async {
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$shotsDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<PosRepository> seeded() async {
  final dir = Directory.systemTemp.createTempSync('pos');
  final repo = PosRepository(await openPosDatabase(databaseFactoryFfi, '${dir.path}/t.db'));
  var owner = await repo.login((await repo.users()).single.id, '0000');
  await repo.setPin(owner, owner.id, '2580');
  owner = await repo.reloadUser(owner.id);
  await repo.updateUser(owner, owner.id, name: 'Zachari');
  owner = await repo.reloadUser(owner.id);
  await repo.saveSettings(owner, {'shop_name': 'Maquis Le Baobab', 'shop_address': 'Ouaga 2000, Ouagadougou', 'shop_phone': '70 00 00 00'});
  final awa = await repo.createUser(owner, name: 'Awa Ouédraogo', role: Role.server, pin: '1357');
  await repo.createUser(owner, name: 'Mariam', role: Role.server, pin: '1358');
  await repo.openSession(owner, 10000);
  final p = {for (final x in await repo.products()) x.name: x};
  final o1 = await repo.createOrder(owner, tableLabel: 'Terrasse 2', serverId: awa.id, lines: [CartLine(p['Brakina']!, 4), CartLine(p['Poulet braisé']!, 1), CartLine(p['Coca-Cola']!, 2)]);
  await repo.createOrder(owner, tableLabel: 'Table 5', lines: [CartLine(p['Castel']!, 3), CartLine(p['Riz gras']!, 2)]);
  final d = await repo.orderDetail(o1);
  await repo.pay(owner, PaymentRequest(orderId: o1, amount: d.summary.total, method: 'cash', idempotencyKey: 'k1', receivedCash: 10000));
  await repo.createOrder(owner, tableLabel: 'VIP 1', serverId: awa.id, lines: [CartLine(p['Beaufort']!, 6)]);
  return repo;
}

void main() {
  sqfliteFfiInit();

  for (final size in const [Size(360, 640), Size(320, 569)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('petit écran $tag : écrans principaux sans débordement', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      late PosRepository repo;
      await tester.runAsync(() async {
        await loadRealFonts();
        repo = await seeded();
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: PosApp(repo: repo),
        ),
      );
      await settle(tester);
      await shot(tester, '${tag}_01_connexion');
      await tester.tap(find.textContaining('Zachari'));
      await tester.pump();
      for (final d in '2580'.split('')) {
        await tester.tap(find.widgetWithText(FilledButton, d).first);
        await tester.pump();
      }
      await tester.tap(find.byIcon(Icons.login));
      await settle(tester, 600);

      // Prise de commande.
      await tester.tap(find.text('Brakina').first);
      await tester.tap(find.text('Brakina').first);
      await tester.tap(find.text('Castel').first);
      await tester.pump(const Duration(milliseconds: 700));
      await shot(tester, '${tag}_02_commande');
      await tester.tap(find.text('Panier'));
      await settle(tester);
      await shot(tester, '${tag}_03_panier');
      await tester.tap(find.text('Encaisser maintenant'));
      await settle(tester);
      await shot(tester, '${tag}_04_encaissement');
      await tester.tap(find.text('Mobile'));
      await tester.pump();
      await shot(tester, '${tag}_05_encaissement_mobile');
      await tester.tap(find.text('Annuler'));
      await settle(tester);
      // Le toast « non encaissée » ; fermer l'éventuel ticket.
      if (find.text('Fermer').evaluate().isNotEmpty) await tester.tap(find.text('Fermer').first);
      await settle(tester);

      for (final tab in ['En cours', 'Caisse', 'Avoirs', 'Gestion']) {
        await tester.tap(find.text(tab).last);
        await settle(tester);
        await shot(tester, '${tag}_1${['En cours', 'Caisse', 'Avoirs', 'Gestion'].indexOf(tab)}_${tab.replaceAll(' ', '_').toLowerCase()}');
      }
      // Imprimer l'addition d'une commande en cours : aperçu du ticket.
      await tester.tap(find.text('En cours').last);
      await settle(tester);
      await tester.tap(find.text('Imprimer').first);
      await settle(tester);
      await shot(tester, '${tag}_20_addition');
      await tester.tap(find.text('Fermer').first);
      await settle(tester);

      await tester.tap(find.text('Gestion').last);
      await settle(tester);
      for (final (i, tile) in ['Produits et prix', 'Stocks', 'Ventes par serveuse', 'Paramètres et imprimante'].indexed) {
        await tester.ensureVisible(find.text(tile));
        await tester.pump();
        final dy = tester.getCenter(find.text(tile)).dy;
        if (dy > size.height * 0.7) {
          await tester.drag(find.byType(GridView), Offset(0, -(dy - size.height / 2)));
          await settle(tester);
        }
        await tester.tap(find.text(tile));
        await settle(tester);
        await shot(tester, '${tag}_3${i}_${tile.split(' ').first.toLowerCase()}');
        if (tile == 'Produits et prix') {
          await tester.tap(find.text('Brakina').first);
          await settle(tester);
          await shot(tester, '${tag}_35_fiche_produit');
          await tester.tap(find.text('Annuler'));
          await settle(tester);
        }
        await tester.pageBack();
        await settle(tester);
      }
      await tester.runAsync(() => repo.db.close());
    });
  }

  testWidgets('petit écran boutique : scan, panier, encaissement', (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    late PosRepository repo;
    await tester.runAsync(() async {
      await loadRealFonts();
      repo = await seeded();
      final owner = (await repo.users()).firstWhere((u) => u.name == 'Zachari');
      await repo.saveSettings(owner, {'business_mode': 'shop', 'shop_name': 'Alimentation Wend-Kuuni'});
      var n = 0;
      for (final p in await repo.products()) {
        await repo.saveProduct(owner, id: p.id, name: p.name, category: p.category, price: p.price, station: p.station, barcode: '61100000000${n++}');
      }
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: PosApp(repo: repo),
      ),
    );
    await settle(tester);
    await tester.tap(find.textContaining('Zachari'));
    await tester.pump();
    for (final d in '2580'.split('')) {
      await tester.tap(find.widgetWithText(FilledButton, d).first);
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.login));
    await settle(tester, 600);
    expect(find.text('Vente'), findsWidgets);
    final field = find.byType(TextField).first;
    for (final code in ['611000000000', '611000000000', '611000000003']) {
      await tester.enterText(field, code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 800));
    await shot(tester, 'shop_01_vente');
    await tester.tap(find.byIcon(Icons.shopping_basket));
    await settle(tester);
    await shot(tester, 'shop_02_panier');
    await tester.tap(find.textContaining('Encaisser ').last);
    await settle(tester);
    await tester.tap(find.text('Mobile'));
    await tester.pump();
    await shot(tester, 'shop_03_orange_money');
    await tester.tap(find.text('Espèces'));
    await tester.pump();
    await tester.tap(find.text('5 000 F').last);
    await tester.pump();
    await shot(tester, 'shop_04_monnaie');
    await tester.tap(find.textContaining('Valider'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    await settle(tester);
    await shot(tester, 'shop_05_recu');
    await tester.runAsync(() => repo.db.close());
  });

  testWidgets('petit écran pharmacie : prix d\'achat et marges', (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    late PosRepository repo;
    await tester.runAsync(() async {
      await loadRealFonts();
      repo = await seeded();
      final owner = (await repo.users()).firstWhere((u) => u.name == 'Zachari');
      await repo.saveSettings(owner, {'business_mode': 'pharmacy', 'shop_name': 'Pharmacie du Marché'});
      expect(await repo.demoProductsActive(), 12);
      expect(await repo.hideDemoProducts(owner), 12);
      expect(await repo.demoProductsActive(), 0);
      final meds = [
        ('Paracétamol 500 mg', 'Antalgiques', 500, 320),
        ('Amoxicilline 500 mg', 'Antibiotiques', 2500, 1800),
        ('Sirop toux enfant', 'Sirops', 1500, null),
        ('Vitamine C 1000', 'Vitamines', 1000, 600),
      ];
      final ids = <String>[];
      for (final (n, c, pv, pa) in meds) {
        final id = await repo.saveProduct(owner, name: n, category: c, price: pv, trackStock: true, cost: pa);
        await repo.adjustStock(owner, id, 50, 'Livraison fournisseur', note: 'Grossiste', unitCost: pa);
        ids.add(id);
      }
      final ps = {for (final p in await repo.products()) p.id: p};
      await repo.createOrder(owner, tableLabel: 'Vente directe', lines: [CartLine(ps[ids[0]]!, 12), CartLine(ps[ids[1]]!, 3), CartLine(ps[ids[2]]!, 2), CartLine(ps[ids[3]]!, 5)]);
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: PosApp(repo: repo),
      ),
    );
    await settle(tester);
    await shot(tester, 'pharma_00_connexion');
    await tester.tap(find.textContaining('Zachari'));
    await tester.pump();
    for (final d in '2580'.split('')) {
      await tester.tap(find.widgetWithText(FilledButton, d).first);
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.login));
    await settle(tester, 600);
    await shot(tester, 'pharma_01_vente');
    await tester.tap(find.text('Gestion').last);
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Marges et bénéfices'),
      150,
      scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)),
    );
    await tester.pump();
    final dy = tester.getCenter(find.text('Marges et bénéfices')).dy;
    if (dy > 640 * 0.7) {
      await tester.drag(find.byType(GridView), Offset(0, -(dy - 320)));
      await settle(tester);
    }
    await tester.tap(find.text('Marges et bénéfices'));
    await settle(tester, 600);
    expect(find.text('Bénéfice brut'), findsOneWidget);
    await shot(tester, 'pharma_02_marges');
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await settle(tester);
    await shot(tester, 'pharma_03_marges_produits');
    await tester.pageBack();
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Médicaments et prix'),
      -150,
      scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)),
    );
    await tester.pump();
    await tester.tap(find.text('Médicaments et prix'));
    await settle(tester);
    await tester.tap(find.text('Amoxicilline 500 mg').first);
    await settle(tester);
    await shot(tester, 'pharma_04_fiche');
    AppColors.apply(BusinessMode.restaurant);
    await tester.runAsync(() => repo.db.close());
  });
}
