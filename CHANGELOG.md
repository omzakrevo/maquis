# Journal des versions

## V0.8.0 — 01/11/2026 — l'application devient CAISSE PRO

- Nouveau nom général **CAISSE PRO** (maquis, restaurants, boutiques, pharmacies) et nouveau logo (ticket de caisse validé) ; icône d'application unique sur Android et Windows (`caisse_pro.exe`).
- En pharmacie, l'application garde la palette verte et le logo pharmacie à l'intérieur ; l'icône sur l'écran d'accueil ne change plus (le basculement d'icône de la V0.7.1 est retiré : il pouvait fermer l'application ou faire disparaître l'icône sur certains téléphones).
- Correctif installation : un seul APK pour tous les appareils, avec un numéro de version interne (5011) supérieur à toutes les versions précédentes. Avant, installer un APK « armv7 » après un APK « arm64 » était refusé par Android (vu comme une version plus ancienne).
- Le nom d'établissement par défaut devient « Mon établissement » (migration v6).

## V0.7.1 — 31/10/2026

- Mode Pharmacie : palette verte et sobre dans toute l'application, logo « PHARMA PRO » (croix et gélule), écran de connexion sans photo de nourriture.
- Icône et nom sur l'écran d'accueil Android basculés automatiquement (« Pharma Pro » / « Maquis & Resto Pro ») selon le type d'établissement.
- En passant en Boutique ou Pharmacie, proposition de retirer de la vente les produits de démonstration (bières, plats…), sans les supprimer.
- Libellés adaptés : « Médicaments et prix », catégories pharmaceutiques avec icônes, « Ventes par vendeur », tables masquées en vente directe.

## V0.7.0 — 30/10/2026

- Nouveau type d'établissement **Pharmacie** (vente directe par scan, comme la boutique ; libellés adaptés, pas de poste bar/cuisine).
- **Prix d'achat** des produits/médicaments : fiche produit (marge affichée en direct, alerte « vendu à perte »), entrée de stock (le prix de la livraison devient le prix d'achat), colonne Excel « Prix d'achat (FCFA) ».
- Coût d'achat **figé sur chaque vente** : changer un prix d'achat ne modifie pas les bénéfices passés.
- Écran **Marges et bénéfices** (Gestion) : chiffre d'affaires, coût d'achat, bénéfice brut, taux de marge, détail par produit, valeur du stock au prix d'achat et de vente, produits sans prix d'achat signalés, export Excel. Réservé aux rôles qui voient les rapports.
- Base : schéma v5 (migration automatique, testée sur SQLite 3.22).
- 45 tests automatisés.

## V0.6.2 — 22/10/2026

- Lecteur intégré : allumage Sunmi corrigé (stop puis scan, attente de la connexion au service), lecteurs « ScanManager » système (Urovo et clones chinois), réception des diffusions iData / Chainway / clones.
- Paramètres > Lecteur de codes > « Diagnostic du lecteur » : marque, service de scan, modèle de tête, pilotes de scan installés, résultat de l'allumage ; bouton « Copier ».
- Écran de scan : méthode d'allumage utilisée et erreur affichées ; conseil « bouton de scan à l'écran ».

## V0.6.1 — 22/10/2026

- Lecteur de codes intégré des terminaux de caisse Android : allumé automatiquement à chaque scan (Sunmi par son service de scan, Zebra DataWedge, Honeywell, Newland) ; codes reçus par diffusion (Sunmi, iMin, Urovo, Newland) ou en sortie clavier.
- Bouton physique de scan actif directement sur l'écran Commande / Vente : le produit s'ajoute au panier.
- Paramètres > Lecteur de codes : Automatique / Lecteur intégré / Caméra, modèle détecté, bouton « Tester le lecteur ».
- Caméra : formats EAN-8, UPC-A/E et Code 39 ajoutés.

## V0.6 — 22/10/2026

- Correctif : DatabaseException sur Android 7–10 (UPSERT non pris en charge par leur SQLite) ; tests exécutés sur SQLite 3.22 ; test anti-syntaxe récente.
- Serveuse liée à chaque commande (choix par la caisse, automatique pour la serveuse connectée, encaissement interdit au rôle serveur).
- Rapport « Ventes par serveuse » : boissons, articles, CA, encaissé, prime (par boisson et/ou % du CA), détail produits, export Excel.
- Addition « NON PAYÉ » avec prix unitaires, totaux, serveuse et QR ; reçu « PAYÉ » / « PAIEMENT PARTIEL ».
- Choix d'imprimer ou non le reçu dans la boîte d'encaissement.
- Mode Boutique / Alimentation : scan code-barres → panier → encaissement direct → ticket ; code-barres produit (fiche, Excel) ; « Encaisser maintenant » en mode maquis.
- Base : schéma v4 (code-barres produit, index unique, type d'établissement).
- Interface adaptée aux terminaux de caisse 5" (tests 360×640 et 320×569).
- 43 tests automatisés.

## V0.5 — 21/10/2026

- Ticket client après validation : prix unitaire et total par ligne, nombre d'articles, total en gros, reste à payer, QR, remerciement.
- Paramètre « Après validation, imprimer » (ticket client / bons bar-cuisine / les deux / rien).
- QR imprimé en image raster (compatibilité) ; vrai QR dans l'aperçu à l'écran.
- Bouton « Imprimer » sur les commandes en attente ; réimpression des bons bar/cuisine.
- Import (.xlsx, .csv) et export (.xlsx) des produits avec aperçu et rapport d'erreurs par ligne.
- Mise en page des tickets : une valeur trop longue passe à la ligne au lieu de couper la date.
- 36 tests automatisés.

## V0.4 — 21/10/2026

- Impression Bluetooth Android réécrite en natif (`ThermalPrinterChannel.kt`) : 3 méthodes de connexion RFCOMM, BLE (GATT), recherche à proximité, envoi par paquets sans octet ajouté, liaison réutilisée et reconnectée automatiquement, erreurs détaillées par étape.
- Windows : envoi Bluetooth en un seul bloc (le plugin corrompait les commandes découpées) et plus de test de connexion qui imprimait des espaces.
- Autorisations Android par version (12+ : Appareils à proximité ; 11 et moins : localisation pour la recherche).
- Ticket de test avec compte rendu de réussite/échec.
- Design sobre : surfaces claires, accent orange unique, cartes et puces neutres.
- Animations : transitions, cascades, rebond, compteurs, coche de réussite, secousse PIN.

## V0.3 — 21/10/2026

- Logo original + icône d'application (Android adaptative, Windows) + écran de démarrage.
- Refonte visuelle : palette chaude, dégradés, motif pagne, couleurs par catégorie, cartes produits avec photo.
- 12 photos produits libres de droits (crédits dans l'app et `assets/products/CREDITS.md`) ; photo personnalisée par produit.
- Impression Bluetooth (imprimantes thermiques appairées, Android/Windows), choix du type d'imprimante.
- QR sur additions et reçus ; scan (caméra Android, douchette USB/saisie Windows) pour retrouver une commande, l'encaisser ou vérifier un avoir.
- Historique des stocks : entrées/sorties/ventes/inventaires avec auteur, date/heure, fournisseur/n° de bon, filtres et totaux.
- Base : schéma v3 (photo produit, note sur mouvement de stock, paramètres Bluetooth), migration automatique.
- Correctif : un reçu dont la monnaie a été rendue en avoir indique « Avoir » et non « Rendu ».
- 28 tests automatisés.

## V0.2 — 21/10/2026

- Code découpé en modules (`core`, `data`, `printing`, `ui`) ; règles métier sorties de l'interface.
- Migration automatique de la base V0.1 (schéma v1 → v2) sans perte.
- Connexion par PIN, 4 rôles, permissions vérifiées côté métier, blocage après 5 erreurs, journal d'activité.
- Gestion des produits (prix, catégories, poste bar/cuisine, mise hors vente), des tables et des employés.
- Stocks : suivi optionnel, décrément à la vente, restitution à l'annulation, entrées/sorties/inventaire, alertes.
- Commandes : numéro journalier, note cuisine, ajout d'articles, annulation avec motif (gérant).
- Encaissement : espèces avec monnaie, Mobile Money avec référence, paiement par avoir, idempotence.
- Avoirs : monnaie rendue en avoir, avoirs manuels, codes avec QR, annulation.
- Sessions de caisse : fond de caisse, rapport X, clôture avec rapport Z et écart, historique.
- Tickets ESC/POS (addition, reçu, bons bar/cuisine, avoir, X/Z), impression réseau TCP 9100, aperçu écran.
- Base de données Windows déplacée dans le dossier applicatif de l'utilisateur (reprise de l'ancien fichier).
- Permission Internet Android (impression réseau), nom d'application, identifiant `bf.omzakrevo.maquis_resto_pro`.
- 22 tests automatisés, dont un parcours complet à l'écran.

## V0.1

- Prototype : catalogue préchargé, panier, commandes, impayés, encaissements partiels.
