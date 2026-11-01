import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les terminaux POS tournent souvent sous Android 7 à 10, dont le SQLite système
/// (3.9 à 3.22) ignore les syntaxes récentes. Ce test refuse leur retour dans le code.
void main() {
  test('aucune syntaxe SQLite trop récente pour les vieux Android', () {
    final forbidden = <String, String>{
      r'ON\s+CONFLICT\s*\([^)]*\)\s*DO': 'UPSERT (SQLite 3.24)',
      r'\bRETURNING\b': 'RETURNING (SQLite 3.35)',
      r'\bIIF\s*\(': 'IIF (SQLite 3.32)',
      r'->>': 'opérateurs JSON (SQLite 3.38)',
      r'\bOVER\s*\(': 'fonctions de fenêtre (SQLite 3.25)',
      r'\bNULLS\s+(FIRST|LAST)\b': 'NULLS FIRST/LAST (SQLite 3.30)',
      r'\bDROP\s+COLUMN\b': 'DROP COLUMN (SQLite 3.35)',
      r'\bRENAME\s+COLUMN\b': 'RENAME COLUMN (SQLite 3.25)',
      r'\bSTRICT\b': 'tables STRICT (SQLite 3.37)',
    };
    final problems = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        for (final e in forbidden.entries) {
          if (RegExp(e.key, caseSensitive: false).hasMatch(l)) problems.add('${f.path}:${i + 1} ${e.value}');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
