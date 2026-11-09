import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maquis_resto_pro/app.dart';
import 'package:maquis_resto_pro/data/database.dart';
import 'package:maquis_resto_pro/data/models.dart';
import 'package:maquis_resto_pro/data/pos_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester tester, [int ms = 300]) async {
  // Les accès SQLite sont de vraies E/S : on les laisse se terminer hors FakeAsync.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms ~/ 3)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.widgetWithText(FilledButton, d).first);
    await tester.pump();
  }
  await tester.tap(find.byIcon(Icons.login));
  await settle(tester);
}

void main() {
  sqfliteFfiInit();

  testWidgets('premier démarrage : connexion, PIN imposé, commande, encaissement', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late PosRepository repo;
    await tester.runAsync(() async {
      repo = PosRepository(await openPosDatabase(databaseFactoryFfi, inMemoryDatabasePath));
    });
    await tester.pumpWidget(PosApp(repo: repo));
    await settle(tester);

    expect(find.textContaining('Propriétaire'), findsWidgets);
    await typePin(tester, '0000');

    // Changement de PIN obligatoire.
    expect(find.text('Choisir un nouveau PIN'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nouveau PIN'), '4826');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmer le PIN'), '4826');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester, 600);

    // Écran de commande.
    expect(find.text('Brakina'), findsOneWidget);
    await tester.tap(find.text('Brakina'));
    await tester.tap(find.text('Brakina'));
    await tester.tap(find.text('Riz gras'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700)); // total animé
    expect(find.text('2 600 F'), findsOneWidget);
    await tester.tap(find.text('Envoyer la commande'));
    await settle(tester);
    expect(find.text('Commande envoyée'), findsOneWidget); // coche de réussite
    await tester.pump(const Duration(milliseconds: 1600));
    await settle(tester);
    // Ticket client (pas d'imprimante configurée → aperçu) : prix unitaires et total.
    expect(find.textContaining('ADDITION'), findsOneWidget);
    expect(find.textContaining('N O N   P A Y É'), findsOneWidget);
    expect(find.textContaining('2 x 800 F'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await settle(tester);

    // Ouvrir la caisse.
    await tester.tap(find.text('Caisse').last);
    await settle(tester);
    await tester.tap(find.text('Ouvrir la caisse'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '10000');
    await tester.tap(find.text('Valider'));
    await settle(tester);
    expect(find.textContaining('Caisse ouverte depuis'), findsOneWidget);

    // Encaisser la commande.
    await tester.tap(find.text('En cours').last);
    await settle(tester);
    expect(find.textContaining('1 commande(s) non soldée(s)'), findsOneWidget);
    await tester.tap(find.text('Encaisser'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Somme donnée par le client'), '5000');
    await tester.pump();
    expect(find.text('Monnaie à rendre : 2 400 F'), findsOneWidget);
    await tester.tap(find.textContaining('Valider 2 600 F'));
    await settle(tester);
    expect(find.text('Commande soldée'), findsOneWidget);
    expect(find.text('Rendre 2 400 F au client'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    await settle(tester);
    // « Imprimer le reçu » coché par défaut → aperçu du reçu PAYÉ.
    expect(find.textContaining('REÇU'), findsOneWidget);
    expect(find.textContaining('P A Y É'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await settle(tester);
    expect(find.textContaining('0 commande(s) non soldée(s)'), findsOneWidget);

    await tester.runAsync(() async {
      final open = await repo.openOrders();
      expect(open, isEmpty);
      await repo.db.close();
    });
  });

  testWidgets('mode boutique : scan du code-barres, encaissement direct, ticket', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late PosRepository repo;
    await tester.runAsync(() async {
      repo = PosRepository(await openPosDatabase(databaseFactoryFfi, inMemoryDatabasePath));
      final owner = (await repo.users()).first;
      await repo.saveSettings(owner, {'business_mode': 'shop'});
      // Catalogue propre à la boutique (celui du maquis n'y apparaît pas).
      expect(await repo.products(), isEmpty);
      await repo.addProducts(owner, [NewProductInput(name: 'Brakina', category: 'Boissons', price: 800, cost: 600, stock: 24, barcode: ' 6111234567890\n')]);
      await repo.openSession(owner, 5000);
    });
    await tester.pumpWidget(PosApp(repo: repo));
    await settle(tester);
    await typePin(tester, '0000');
    await tester.enterText(find.widgetWithText(TextField, 'Nouveau PIN'), '4826');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmer le PIN'), '4826');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester, 600);

    // Pas de table ni de serveuse en boutique.
    expect(find.textContaining('Vente directe'), findsOneWidget);
    expect(find.text('Servi par'), findsNothing);
    // La douchette tape le code puis Entrée.
    final field = find.byType(TextField).first;
    for (var i = 0; i < 2; i++) {
      await tester.enterText(field, '6111234567890');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Encaisser 1 600 F'), findsOneWidget);
    await tester.tap(find.text('Encaisser 1 600 F'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Somme donnée par le client'), '2000');
    await tester.pump();
    expect(find.text('Monnaie à rendre : 400 F'), findsOneWidget);
    await tester.tap(find.textContaining('Valider 1 600 F'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    await settle(tester);
    expect(find.textContaining('REÇU'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await settle(tester);

    await tester.runAsync(() async {
      expect(await repo.openOrders(), isEmpty);
      expect((await repo.productByBarcode('PRD:6111234567890'))?.name, 'Brakina');
      await repo.db.close();
    });
  });
}
