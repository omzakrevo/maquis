/// Formatage des montants en FCFA (entiers, jamais de virgule flottante).
String fcfa(int amount, {bool suffix = true}) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buf${suffix ? ' F' : ''}';
}

/// Lit un montant saisi par l'utilisateur ("1 500", "1500", "1.500").
/// Renvoie null si la saisie n'est pas un entier positif ou nul.
int? parseFcfa(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s.  ]'), '').replaceAll(RegExp(r'[Ff]$'), '');
  if (cleaned.isEmpty || !RegExp(r'^\d+$').hasMatch(cleaned)) return null;
  return int.tryParse(cleaned);
}
