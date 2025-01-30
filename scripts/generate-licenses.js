// Fonction pour générer une clé de licence aléatoire
function generateLicenseKey() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const segments = 4;
  const segmentLength = 4;
  let key = '';
  
  for (let i = 0; i < segments; i++) {
    for (let j = 0; j < segmentLength; j++) {
      key += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    if (i < segments - 1) key += '-';
  }
  
  return key;
}

// Générer 200 licences
const licenses = [];
const periods = ['1 mois', '3 mois', '6 mois', '1 an', 'à vie'];
const weights = [30, 25, 20, 15, 10]; // Pourcentages pour chaque période

for (let i = 0; i < 200; i++) {
  // Sélection pondérée de la période
  const random = Math.random() * 100;
  let cumulativeWeight = 0;
  let selectedPeriod = periods[0];
  
  for (let j = 0; j < weights.length; j++) {
    cumulativeWeight += weights[j];
    if (random <= cumulativeWeight) {
      selectedPeriod = periods[j];
      break;
    }
  }

  const license = {
    key: generateLicenseKey(),
    period: selectedPeriod,
    status: 'active'
  };
  licenses.push(license);
}

// Afficher les licences au format CSV
console.log('licence,periode,etat');
licenses.forEach(license => {
  console.log(`${license.key},${license.period},${license.status}`);
});