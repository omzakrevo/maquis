# CAISSE PRO — V0.8 (anciennement MAQUIS & RESTO PRO, caisse sur poste unique)

Caisse pour maquis, bars, restaurants, boutiques et pharmacies, en FCFA, qui fonctionne **sans Internet sur un seul appareil**
(tablette/téléphone Android ou PC Windows). Ce n'est pas encore une caisse multi-postes ni un SaaS :
voir « Limites » plus bas.

## Nouveautés V0.7 — déclinaison Pharmacie et prix d'achat

- Paramètres > Type d'établissement : **Maquis / Resto / Bar**, **Boutique / Alimentation** ou **Pharmacie**.
- Prix d'achat sur la fiche produit, à chaque entrée de stock et dans l'Excel ; marge affichée en direct.
- Gestion > **Marges et bénéfices** : bénéfice brut par période et par produit, valeur du stock, export Excel.
- Le coût d'achat est enregistré sur chaque vente : les bénéfices passés restent justes quand le prix d'achat change.
- En mode Pharmacie, l'application passe en vert sobre avec le logo « PHARMA PRO » (icône d'accueil Android comprise) et propose de retirer les produits de démonstration.
- Limites actuelles pour une pharmacie : pas encore de lots ni de dates de péremption, pas d'ordonnance ni de tiers payant (assurance).

## Version Windows

La version Windows se compile sur une machine Windows (Flutter ne la fabrique pas depuis Linux). Deux façons :

1. **Par GitHub (sans rien installer)** : envoyer ce dossier dans un dépôt GitHub, onglet **Actions > Windows > Run workflow**. Après ~10 minutes, télécharger dans **Artifacts** : `MaquisRestoPro_V…_Windows_installation.exe` (installateur avec raccourcis) et `…_Windows_portable.zip` (à dézipper, lancer `maquis_resto_pro.exe`). Avec un tag `v0.6.2`, les fichiers sont aussi publiés dans **Releases**.
2. **Sur un PC Windows** avec Flutter et Visual Studio 2022 (« Développement Desktop en C++ ») : double-cliquer `flutter_app\build_windows.bat` ; résultat dans `flutter_app\dist`. Avec Inno Setup 6 installé, l'installateur est aussi fabriqué.

Windows 10 ou 11, 64 bits. Imprimantes : réseau (IP) ou Bluetooth appairée dans Windows ; scan avec une douchette USB.

## Nouveautés V0.6.1 — lecteur intégré des terminaux de caisse

Paramètres > **Lecteur de codes** : *Automatique* (lecteur intégré si le terminal est reconnu, sinon caméra), *Lecteur intégré* ou *Caméra*, et **Tester le lecteur**.

| Marque | Allumage par l'application | Réception du code |
|---|---|---|
| Sunmi (V2 Pro, L2…) | oui (service `com.sunmi.scanner`) | diffusion ou clavier |
| Zebra | oui (DataWedge, profil avec « Barcode input » activé) | clavier (DataWedge par défaut) |
| Honeywell | oui (`ACTION_CONTROL_SCANNER`) | clavier |
| Newland | oui (`nlscan.action.SCANNER_TRIG`) | diffusion ou clavier |
| iMin, Urovo, autres | non : appuyer sur le bouton de scan du terminal | diffusion ou clavier |

Sur l'écran Commande / Vente, le bouton physique de scan ajoute directement le produit au panier. Le mode « remplissage direct » (Direct fill) du lecteur ne fonctionne pas avec l'application : choisir **sortie clavier** ou **diffusion**. Terminal sans bouton de scan : activer le **bouton de scan à l'écran / bouton flottant** dans l'appli Scanner du terminal. En cas de problème : Paramètres > Lecteur de codes > **Diagnostic du lecteur** > Copier. Si rien ne s'affiche après un scan, vérifier dans les réglages du lecteur du terminal (appli « Scanner » / « ScanWedge ») que la sortie est en **diffusion (broadcast)** ou en **clavier avec Entrée**. Pour une sortie « intent » personnalisée, utiliser l'action `bf.omzakrevo.SCAN` et la donnée `data`.

## Nouveautés V0.6

- **Correctif « DatabaseException »** à l'ajout de produit, à la validation d'une commande et à l'ouverture de caisse : la V0.5 utilisait une syntaxe SQL (`ON CONFLICT … DO UPDATE`) absente du SQLite des Android 7 à 10. Remplacée, et toute la suite de tests passe maintenant sur SQLite 3.22 (le plus ancien visé). Un test bloque désormais toute syntaxe trop récente.
- **Serveuses** : à la prise de commande, la caisse choisit « Servi par » dans la liste des serveuses ; une serveuse connectée avec son compte est attribuée automatiquement et **ne peut pas encaisser** (elle remet l'addition, la commande attend à la caisse).
- **Ventes par serveuse** (Gestion) : par période (jour, semaine, mois, mois dernier, dates au choix) — commandes, **bouteilles/boissons**, articles, chiffre d'affaires, encaissé, **prime** calculée (X F par boisson et/ou % du chiffre d'affaires), détail par produit, export Excel pour la paie.
- **Addition à la validation** : « ADDITION », mention **NON PAYÉ** en gros, quantité × prix unitaire, total de ligne, total en bas, nom de la serveuse (« Servi par »), QR code.
- **Encaissement** : interrupteur « Imprimer le reçu » dans la boîte de paiement (choix retenu) ; le reçu indique **PAYÉ** ou **PAIEMENT PARTIEL**.
- **Mode Boutique / Alimentation** (Paramètres > Type d'établissement) : pas de table ni de serveuse ; on scanne le code-barres (douchette, lecteur intégré du terminal ou caméra), le produit s'ajoute au panier, puis **Encaisser** → espèces (somme donnée, monnaie calculée) ou Orange Money / Moov / Wave → ticket. Code-barres sur la fiche produit et dans l'import/export Excel (colonne « Code-barres »), unicité contrôlée.
- **« Encaisser maintenant »** aussi en mode maquis, pour les ventes au comptoir.
- **Petits écrans de caisse (5")** : grille de 3 produits par ligne, boîtes de dialogue resserrées, indicateurs sur deux colonnes, sélecteurs sans retour à la ligne, écran de connexion qui tient sans défiler. Vérifié par des tests à 360×640 et 320×569.
- 43 tests automatisés.

## Nouveautés V0.5

- **Ticket client complet** imprimé dès la validation de la commande : pour chaque article, quantité × prix unitaire et total de la ligne ; nombre d'articles ; **TOTAL** en gros caractères ; paiements reçus et reste à payer ; **QR code** (scanné à la caisse pour encaisser) ; message de remerciement.
- **Réglage « Après validation, imprimer »** : ticket client, bons bar/cuisine, les deux, ou rien.
- **QR imprimé en image** (option activée par défaut) : fonctionne aussi sur les imprimantes qui ne savent pas dessiner les QR elles-mêmes.
- **Commandes en attente** : bouton « Imprimer » sur chaque commande (ticket avec le reste à payer), et réimpression des bons bar/cuisine depuis le détail.
- **Import / export Excel des produits** (Gestion > Produits) : l'export produit un `.xlsx` avec une feuille « Produits » et une feuille « Mode d'emploi » ; l'import accepte `.xlsx` et `.csv`, montre un aperçu (nouveaux, mis à jour, lignes ignorées avec la raison) avant d'appliquer, crée ou met à jour par nom, et enregistre le stock indiqué comme un inventaire « Import Excel ».

## Nouveautés V0.4

- **Impression Bluetooth réparée (Android)** : module natif maison à la place du plugin, qui échouait avec beaucoup d'imprimantes.
  - Trois méthodes de connexion essayées automatiquement (sécurisée, non sécurisée, canal 1) ;
  - données envoyées sans altération (le plugin insérait un octet parasite dans les commandes ESC/POS) ;
  - prise en charge des imprimantes **Bluetooth LE** ;
  - bouton « À proximité » pour trouver une imprimante non appairée ;
  - le ticket de test affiche un compte rendu (méthode utilisée) ou l'erreur détaillée.
- **Design plus sobre** : fond clair uni, en-tête blanc, un seul accent orange ; la couleur vient des photos.
- **Animations** : transitions entre onglets et écrans, apparition en cascade des produits et des listes, rebond au toucher d'un produit, pastille de quantité animée, total qui défile, coche animée après l'envoi d'une commande et l'encaissement, secousse sur PIN erroné. Désactivées automatiquement si le téléphone est réglé sur « Supprimer les animations ».

### Dépannage de l'imprimante Bluetooth

1. Gestion > Paramètres et imprimante > **Bluetooth**.
2. **Appairées** (imprimante déjà appairée dans les réglages Android, code souvent 0000 ou 1234) ou **À proximité** (recherche 8 s, utile pour les modèles BLE).
3. Choisissez l'imprimante puis **Enregistrer et imprimer un ticket de test**.
   - « Ticket envoyé » mais rien ne sort : papier à l'envers (face thermique vers la tête), largeur 58/80 mm, ou activez « Imprimer sans accents ».
   - « Impossible de se connecter » : imprimante éteinte ou en veille, déjà connectée à un autre téléphone, ou trop loin. Le détail technique liste l'erreur de chaque méthode : envoyez-le si le problème persiste.
   - Autorisation refusée : Paramètres Android > Applications > Maquis & Resto Pro > Autorisations > Appareils à proximité.

## Nouveautés V0.3

- **Logo et icône** : logo original (bol fumant, bouteille, étoile), icône Android adaptative, icône Windows, écran de démarrage orange.
- **Interface colorée** : en-têtes en dégradé terre cuite/orange/or, motif inspiré du pagne en fond, couleur et icône par catégorie, cartes indicateurs colorées, écran de connexion sur photo de grillade.
- **Photos des produits** : 12 photos libres de droits (Wikimedia Commons / Flickr, licences CC BY et CC BY-SA, crédits dans *Gestion > À propos* et `assets/products/CREDITS.md`). Chaque produit peut recevoir sa propre photo (galerie, appareil photo, ou fichier sous Windows).
- **Imprimantes Bluetooth** : choix Aperçu / Réseau / Bluetooth dans les paramètres, recherche des imprimantes appairées, ticket de test. Android et Windows.
- **Scan** : chaque addition et chaque reçu portent un QR. Le bouton « Scanner un ticket » retrouve la commande et propose d'encaisser en un geste ; il lit aussi les bons d'avoir. Caméra sur Android ; douchette USB ou saisie du numéro sur Windows.
- **Historique des stocks** : toutes les entrées, sorties, ventes et inventaires, avec qui, quand, combien, fournisseur/n° de bon ; filtres par type, période et produit, totaux.

## Ce que fait la V0.2 (toujours inclus)

| Domaine | Fonctions |
|---|---|
| **Connexion** | Chaque employé a un PIN (4 à 6 chiffres, haché et salé). Premier démarrage : compte *Propriétaire*, PIN `0000` à changer obligatoirement. Blocage 2 min après 5 PIN erronés. Bouton « Verrouiller / changer d'utilisateur ». |
| **Rôles** | Propriétaire (tout), Gérant (catalogue, stocks, annulations, avoirs, rapports, paramètres), Caissier (commandes, encaissements, ouverture/clôture), Serveur (prise de commande seulement). Les permissions sont vérifiées dans la couche métier, pas seulement masquées à l'écran. |
| **Commande** | Grille de produits par catégorie avec recherche, panier, choix de la table (ou Comptoir / À emporter), note pour la cuisine. Numéro journalier `AAMMJJ-001`. Ajout d'articles à une commande déjà ouverte. Prix relus en base au moment de l'envoi. |
| **Encaissement** | Paiements partiels ; espèces avec calcul de la monnaie et boutons de billets rapides ; Mobile Money (Orange, Moov, Wave) avec référence obligatoire ; paiement par avoir. Double appui sur « Valider » sans risque (clé d'idempotence). Encaissement impossible si la caisse n'est pas ouverte. |
| **Avoirs** | « Pas de monnaie » : la monnaie peut être rendue sous forme de bon d'avoir (code `ABCD-EFGH` + QR). Avoirs manuels (plat indisponible, geste commercial) par le gérant. Utilisation en une ou plusieurs fois, contrôle du solde dans la même transaction que le paiement. Seul le haché du code est stocké. |
| **Caisse** | Ouverture avec fond de caisse, rapport X en cours (encaissé par mode, espèces attendues, impayés), clôture avec espèces comptées → rapport Z figé avec écart (excédent / manquant), historique des clôtures. |
| **Annulation** | Réservée au gérant/propriétaire, motif obligatoire, refusée si un paiement existe déjà (on émet alors un avoir), stock restitué. |
| **Stocks** | Suivi optionnel par produit, décrément à la vente, entrées/sorties/inventaire avec motif, alerte de stock bas visible sur la grille de commande. |
| **Tickets** | Addition, reçu, bons de préparation séparés **bar / cuisine**, bon d'avoir avec QR, rapports X/Z. Aperçu à l'écran dans tous les cas. |
| **Impression** | Imprimante thermique ESC/POS **réseau** (Ethernet/Wi-Fi, port 9100) ou **Bluetooth** (V0.3), papier 58 ou 80 mm, accents en CP858 ou impression sans accents. Ticket de test dans Paramètres. |
| **Traçabilité** | Journal d'activité (qui a fait quoi, quand) ; chaque écriture alimente une file `sync_outbox` numérotée, prête pour la future synchronisation. |
| **Données V0.1** | Une base créée par la V0.1 est migrée automatiquement (schéma v1 → v2) sans perte. |

## Structure

```
flutter_app/
  lib/
    main.dart                 démarrage, emplacement de la base
    app.dart                  thème, routage connexion → changement de PIN → accueil
    core/                     montants FCFA, rôles/permissions, hachage PIN, codes d'avoir
    data/
      database.dart           ouverture SQLite + migrations (sans dépendance Flutter)
      pos_repository.dart     TOUTES les règles métier (sans dépendance Flutter)
      models.dart
    printing/                 modèle de ticket, encodeur ESC/POS, envoi TCP, modèles de tickets
    ui/                       écrans (connexion, commande, en cours, caisse, avoirs, gestion…)
  assets/brand/               logo (SVG + PNG) et sources de l'icône
  assets/products/            photos produits + CREDITS.md
  test/                       36 tests : métier, impression, Excel, migration, parcours écran complet
database/
  sqlite.sql                  schéma local v2 (référence)
  postgresql.sql              fondation cloud multi-établissements (inchangée)
docs/architecture.md
```

`data/` et `printing/` (hors envoi réseau) n'importent pas Flutter : ils pourront être repris tels quels
par le futur service local Dart.

## Lancer / compiler

Prérequis : Flutter 3.35 ou plus récent (testé avec 3.47.7).

```bash
cd flutter_app
flutter pub get
flutter test                      # 36 tests
flutter run -d windows            # PC Windows (Visual Studio C++ requis)
flutter run                       # téléphone/tablette Android branché
flutter build apk --release --split-per-abi   # APK (arm64-v8a pour la plupart des appareils récents)
flutter build windows --release   # à lancer depuis Windows
```

Emplacement de la base : Android → dossier de l'application ; Windows → `%APPDATA%\bf.omzakrevo\MAQUIS & RESTO PRO\`
(chemin exact donné par `getApplicationSupportDirectory`). Pour sauvegarder, copier le fichier `maquis_resto_v1.db`
caisse fermée.

## Premier démarrage

1. PIN `0000` → choisir un PIN personnel.
2. Gestion > Paramètres et imprimante : nom de l'établissement, adresse, téléphone ; type d'imprimante (réseau : adresse IP ; Bluetooth : appairer dans les réglages du téléphone puis « Rechercher »), puis ticket de test.
3. Gestion > Produits : corriger les prix (ceux livrés sont **fictifs**), ajouter vos produits et leurs photos, activer le suivi de stock sur les boissons.
4. Gestion > Employés : créer serveurs et caissiers (ils changeront leur PIN à la première connexion).
5. Caisse > Ouvrir la caisse avec le fond de caisse.

## Limites (à lire avant tout usage réel)

- **Un seul appareil** : pas encore de serveur local ni de synchronisation entre téléphones des serveurs et caisse. Les serveuses se connectent avec leur PIN **sur l'appareil de la caisse** (ou une caisse par appareil, sans partage des commandes).
- **Mobile Money = déclaration manuelle** : l'application n'interroge pas l'opérateur ; le caissier vérifie le SMS.
- Imprimantes **USB** non prises en charge (réseau et Bluetooth uniquement). Réseau testé contre une imprimante simulée, Bluetooth non testé sur matériel réel : faire le ticket de test.
- Scan par caméra sur Android uniquement ; sous Windows, utiliser une douchette USB (elle tape le code comme un clavier) ou saisir le numéro.
- Pas de sauvegarde automatique ni de chiffrement de la base sur l'appareil.
- Pas de remboursement en espèces : les corrections après paiement passent par un avoir.
- Le hachage du PIN (SHA-256 itéré) convient pour un poste local ; côté serveur, passer à Argon2/bcrypt.
- Faire une période d'essai en parallèle de la méthode actuelle avant d'encaisser de vrais clients.
