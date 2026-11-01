import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final _random = Random.secure();

String randomSalt([int bytes = 16]) => base64UrlEncode(List<int>.generate(bytes, (_) => _random.nextInt(256)));

/// Hachage du PIN : SHA-256 itéré avec sel. Suffisant pour un poste local ;
/// côté serveur/cloud, préférer Argon2 ou bcrypt.
String hashPin(String pin, String salt, {int iterations = 20000}) {
  List<int> digest = utf8.encode('$salt:$pin');
  for (var i = 0; i < iterations; i++) {
    digest = sha256.convert(digest).bytes;
  }
  return base64UrlEncode(digest);
}

bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

/// Alphabet sans caractères ambigus (pas de 0/O, 1/I/L).
const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Code d'avoir lisible : 8 caractères, affiché "ABCD-EFGH".
String generateCreditCode() {
  final chars = List.generate(8, (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)]).join();
  return '${chars.substring(0, 4)}-${chars.substring(4)}';
}

String normalizeCreditCode(String input) => input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Seul le haché du code est stocké : un code perdu ne peut pas être relu en base.
String hashCreditCode(String code) => sha256.convert(utf8.encode('avoir:${normalizeCreditCode(code)}')).toString();
