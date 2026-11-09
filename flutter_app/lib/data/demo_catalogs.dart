// Catalogues d'exemple chargeables depuis Paramètres, un par type d'établissement.
// Tous marqués « démo » : on les supprime en un geste quand on démarre pour de vrai.
// Codes-barres EAN-13 fictifs (préfixe 2 = usage interne), prix en FCFA.

class DemoItem {
  const DemoItem(this.name, this.category, this.price, this.cost, this.barcode, this.stock, [this.image]);
  final String name;
  final String category;
  final int price;
  final int cost;
  final String barcode;
  final int stock;
  final String? image;
}

const pharmacyDemo = <DemoItem>[
  DemoItem('Paracétamol 500 mg (10 cp)', 'Antalgiques', 150, 100, '2100000000012', 120, 'asset:assets/demo/pharma/paracetamol.jpg'),
  DemoItem('Ibuprofène 400 mg (10 cp)', 'Anti-inflammatoires', 300, 200, '2100000000029', 80, 'asset:assets/demo/pharma/ibuprofene.jpg'),
  DemoItem('Amoxicilline 500 mg (12 gél.)', 'Antibiotiques', 1000, 700, '2100000000036', 40, 'asset:assets/demo/pharma/amoxicilline.jpg'),
  DemoItem('Artéméther-Luméfantrine 20/120 (24 cp)', 'Antipaludiques', 1500, 1050, '2100000000043', 50, 'asset:assets/demo/pharma/artemether.jpg'),
  DemoItem('Métronidazole 250 mg (20 cp)', 'Antibiotiques', 500, 330, '2100000000050', 40, 'asset:assets/demo/pharma/metronidazole.jpg'),
  DemoItem('Oméprazole 20 mg (14 gél.)', 'Digestif', 1200, 800, '2100000000067', 30, 'asset:assets/demo/pharma/omeprazole.jpg'),
  DemoItem('Vitamine C 500 mg (tube)', 'Vitamines', 1000, 650, '2100000000074', 35, 'asset:assets/demo/pharma/vitamine_c.jpg'),
  DemoItem('SRO sachet', 'Réhydratation', 150, 90, '2100000000081', 100, 'asset:assets/demo/pharma/sro.jpg'),
  DemoItem('Cotrimoxazole 480 mg (20 cp)', 'Antibiotiques', 400, 260, '2100000000098', 45, 'asset:assets/demo/pharma/cotrimoxazole.jpg'),
  DemoItem('Sirop contre la toux 125 ml', 'Sirops', 1500, 1000, '2100000000104', 25, 'asset:assets/demo/pharma/sirop_toux.jpg'),
  DemoItem('Paracétamol sirop enfant 100 ml', 'Sirops', 1000, 650, '2100000000111', 30, 'asset:assets/demo/pharma/paracetamol_sirop.jpg'),
  DemoItem('Alcool 70° 250 ml', 'Antiseptiques', 500, 300, '2100000000128', 40, 'asset:assets/demo/pharma/alcool.jpg'),
  DemoItem('Povidone iodée 10 % 125 ml', 'Antiseptiques', 1800, 1200, '2100000000135', 15, 'asset:assets/demo/pharma/povidone.jpg'),
  DemoItem('Compresses stériles (boîte de 50)', 'Pansements', 1500, 950, '2100000000142', 20, 'asset:assets/demo/pharma/compresses.jpg'),
  DemoItem('Bande élastique 10 cm', 'Pansements', 600, 380, '2100000000159', 30, 'asset:assets/demo/pharma/bande.jpg'),
  DemoItem('Seringue 5 ml', 'Matériel médical', 100, 50, '2100000000166', 200, 'asset:assets/demo/pharma/seringue.jpg'),
  DemoItem('Gants d\'examen (boîte de 100)', 'Matériel médical', 4000, 2800, '2100000000173', 10, 'asset:assets/demo/pharma/gants.jpg'),
  DemoItem('Thermomètre digital', 'Matériel médical', 2500, 1600, '2100000000180', 8, 'asset:assets/demo/pharma/thermometre.jpg'),
];

const motoPartsDemo = <DemoItem>[
  DemoItem('Bougie d\'allumage', 'Allumage', 1000, 600, '2200000000019', 40, 'asset:assets/demo/moto/bougie.jpg'),
  DemoItem('Kit chaîne + pignons', 'Transmission', 9000, 6500, '2200000000026', 10, 'asset:assets/demo/moto/kit_chaine.jpg'),
  DemoItem('Plaquettes de frein avant', 'Freinage', 2500, 1600, '2200000000033', 25, 'asset:assets/demo/moto/plaquettes.jpg'),
  DemoItem('Mâchoires de frein arrière', 'Freinage', 2000, 1300, '2200000000040', 25, 'asset:assets/demo/moto/machoires.jpg'),
  DemoItem('Câble d\'embrayage', 'Câbles', 1500, 900, '2200000000057', 20, 'asset:assets/demo/moto/cable_embrayage.jpg'),
  DemoItem('Câble d\'accélérateur', 'Câbles', 1200, 700, '2200000000064', 20, 'asset:assets/demo/moto/cable_accel.jpg'),
  DemoItem('Filtre à air', 'Filtres', 2000, 1200, '2200000000071', 15, 'asset:assets/demo/moto/filtre_air.jpg'),
  DemoItem('Huile moteur 4T 1 L', 'Huiles', 4000, 3000, '2200000000088', 30, 'asset:assets/demo/moto/huile_4t.jpg'),
  DemoItem('Batterie 12 V 5 Ah', 'Électricité', 9000, 6500, '2200000000095', 8, 'asset:assets/demo/moto/batterie.jpg'),
  DemoItem('Pneu 2.75-17', 'Pneus', 12000, 9000, '2200000000101', 10),
  DemoItem('Chambre à air 17"', 'Pneus', 2500, 1600, '2200000000118', 20),
  DemoItem('Ampoule de phare 12 V', 'Électricité', 1000, 550, '2200000000125', 30),
  DemoItem('Rétroviseurs (paire)', 'Accessoires', 3000, 1900, '2200000000132', 12),
  DemoItem('Levier de frein', 'Freinage', 1500, 900, '2200000000149', 15),
  DemoItem('Kit piston + segments', 'Moteur', 8000, 5500, '2200000000156', 6),
  DemoItem('Carburateur', 'Moteur', 10000, 7000, '2200000000163', 5),
  DemoItem('Roulement de roue', 'Roues', 1500, 900, '2200000000170', 25),
  DemoItem('Poignées de guidon (paire)', 'Accessoires', 1500, 900, '2200000000187', 15),
];

/// Maquis : les boissons et plats livrés avec l'application (sans code-barres ni suivi de stock).
const restaurantDemo = <DemoItem>[
  DemoItem('Brakina', 'Bières', 800, 550, '', 0, 'asset:assets/products/brakina.jpg'),
  DemoItem('Beaufort', 'Bières', 800, 550, '', 0, 'asset:assets/products/beaufort.jpg'),
  DemoItem('Sobbra', 'Bières', 800, 550, '', 0, 'asset:assets/products/sobbra.jpg'),
  DemoItem('Castel', 'Bières', 1000, 700, '', 0, 'asset:assets/products/castel.jpg'),
  DemoItem('Coca-Cola', 'Sodas', 500, 350, '', 0, 'asset:assets/products/coca_cola.jpg'),
  DemoItem('Youki', 'Sodas', 500, 350, '', 0, 'asset:assets/products/youki.jpg'),
  DemoItem('Eau minérale', 'Eaux', 500, 300, '', 0, 'asset:assets/products/eau_minerale.jpg'),
  DemoItem('Bissap', 'Jus', 500, 250, '', 0, 'asset:assets/products/bissap.jpg'),
  DemoItem('Riz gras', 'Plats', 1000, 600, '', 0, 'asset:assets/products/riz_gras.jpg'),
  DemoItem('Poulet braisé', 'Plats', 3500, 2300, '', 0, 'asset:assets/products/poulet_braise.jpg'),
  DemoItem('Poisson braisé', 'Plats', 3000, 2000, '', 0, 'asset:assets/products/poisson_braise.jpg'),
  DemoItem('Attiéké', 'Plats', 1000, 550, '', 0, 'asset:assets/products/attieke.jpg'),
];

List<DemoItem> demoCatalogFor(String business) => switch (business) {
  'pharmacy' => pharmacyDemo,
  'shop' => motoPartsDemo,
  _ => restaurantDemo,
};
