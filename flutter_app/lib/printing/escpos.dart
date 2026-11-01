// Encodeur ESC/POS (Epson et compatibles : la plupart des imprimantes
// thermiques 58/80 mm vendues localement).
import 'dart:convert';
import 'dart:typed_data';

import 'package:qr/qr.dart' as qr;

import 'ticket.dart';

const _esc = 0x1B;
const _gs = 0x1D;

/// Correspondance CP858 (≈ CP850 + €) des caractères français courants.
const Map<String, int> _cp858 = {
  'Ç': 0x80,
  'ü': 0x81,
  'é': 0x82,
  'â': 0x83,
  'ä': 0x84,
  'à': 0x85,
  'ç': 0x87,
  'ê': 0x88,
  'ë': 0x89,
  'è': 0x8A,
  'ï': 0x8B,
  'î': 0x8C,
  'Ä': 0x8E,
  'É': 0x90,
  'ô': 0x93,
  'ö': 0x94,
  'û': 0x96,
  'ù': 0x97,
  'Ö': 0x99,
  'Ü': 0x9A,
  'Â': 0xB6,
  'À': 0xB7,
  'Ê': 0xD2,
  'Ë': 0xD3,
  'È': 0xD4,
  '€': 0xD5,
  'Î': 0xD7,
  'Ï': 0xD8,
  'Ô': 0xE2,
  'Û': 0xEA,
  'Ù': 0xEB,
  '°': 0xF8,
};

const Map<String, String> _ascii = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'À': 'A',
  'Â': 'A',
  'Ä': 'A',
  'ç': 'c',
  'Ç': 'C',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'É': 'E',
  'È': 'E',
  'Ê': 'E',
  'Ë': 'E',
  'î': 'i',
  'ï': 'i',
  'Î': 'I',
  'Ï': 'I',
  'ô': 'o',
  'ö': 'o',
  'Ô': 'O',
  'Ö': 'O',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'Ù': 'U',
  'Û': 'U',
  'Ü': 'U',
  'œ': 'oe',
  'Œ': 'OE',
  '’': "'",
  '‘': "'",
  '«': '"',
  '»': '"',
  '…': '...',
  '–': '-',
  '—': '-',
  '€': 'EUR',
  '°': 'o',
  ' ': ' ',
  ' ': ' ',
};

String stripAccents(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_ascii[ch] ?? ch);
  }
  return b.toString();
}

List<int> encodeText(String s, {required bool stripAccentsMode}) {
  final out = <int>[];
  final src = stripAccentsMode ? stripAccents(s) : s.replaceAll('œ', 'oe').replaceAll('Œ', 'OE').replaceAll('’', "'").replaceAll('…', '...');
  for (final rune in src.runes) {
    final ch = String.fromCharCode(rune);
    if (rune < 0x80) {
      out.add(rune);
    } else if (!stripAccentsMode && _cp858.containsKey(ch)) {
      out.add(_cp858[ch]!);
    } else {
      final fallback = _ascii[ch];
      out.addAll(fallback != null ? ascii.encode(fallback) : [0x3F]); // '?'
    }
  }
  return out;
}

class EscPosEncoder {
  EscPosEncoder({required this.charsPerLine, this.stripAccentsMode = true, this.codePage = 19, this.cut = true, this.qrAsImage = true});
  final int charsPerLine;
  final bool stripAccentsMode;
  final int codePage; // 19 = CP858 sur Epson ; varie selon les modèles
  final bool cut;

  /// true : QR dessiné en image (GS v 0), compris par toutes les imprimantes
  /// thermiques. false : commande QR native (GS ( k), ignorée par certains modèles.
  final bool qrAsImage;

  /// Largeur imprimable en points : 384 (58 mm) ou 576 (80 mm).
  int get paperDots => charsPerLine >= 48 ? 576 : 384;

  Uint8List encode(Ticket ticket) {
    final b = BytesBuilder();
    b.add([_esc, 0x40]); // initialisation
    if (!stripAccentsMode) b.add([_esc, 0x74, codePage]);
    for (final e in ticket.elements) {
      switch (e) {
        case TextLine():
          b.add([_esc, 0x61, e.align.index]);
          b.add([_esc, 0x45, e.bold ? 1 : 0]);
          b.add([_gs, 0x21, e.big ? 0x11 : 0x00]);
          final width = e.big ? charsPerLine ~/ 2 : charsPerLine;
          for (final l in wrap(e.text, width)) {
            b.add(encodeText(l, stripAccentsMode: stripAccentsMode));
            b.addByte(0x0A);
          }
          b.add([_gs, 0x21, 0x00]);
          b.add([_esc, 0x45, 0]);
        case PairLine():
          b.add([_esc, 0x61, 0]);
          b.add([_esc, 0x45, e.bold ? 1 : 0]);
          for (final l in pairLines(e.left, e.right, charsPerLine)) {
            b.add(encodeText(l, stripAccentsMode: stripAccentsMode));
            b.addByte(0x0A);
          }
          b.add([_esc, 0x45, 0]);
        case Separator():
          b.add([_esc, 0x61, 0]);
          b.add(encodeText(e.char * charsPerLine, stripAccentsMode: true));
          b.addByte(0x0A);
        case QrCode():
          if (qrAsImage) {
            b.add([_esc, 0x61, 0]);
            b.add(qrRaster(e.data, paperDots: paperDots, targetDots: charsPerLine >= 48 ? 300 : 240));
          } else {
            b.add([_esc, 0x61, 1]);
            b.add(qrCommands(e.data, size: e.size));
            b.addByte(0x0A);
          }
        case Feed():
          b.add([_esc, 0x64, e.lines.clamp(0, 255)]);
      }
    }
    b.add([_esc, 0x61, 0]);
    if (cut) {
      b.add([_gs, 0x56, 0x42, 0x03]); // avance de 3 lignes puis coupe partielle
    } else {
      b.add([_esc, 0x64, 4]);
    }
    return b.toBytes();
  }
}

/// Commandes GS ( k : QR code modèle 2, correction M.
List<int> qrCommands(String data, {int size = 6}) {
  final bytes = utf8.encode(data);
  final len = bytes.length + 3;
  return [
    _gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00, // modèle 2
    _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.clamp(1, 16), // taille module
    _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31, // correction M
    _gs, 0x28, 0x6B, len & 0xFF, (len >> 8) & 0xFF, 0x31, 0x50, 0x30, ...bytes, // stockage
    _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30, // impression
  ];
}

/// Matrice du QR code (true = module noir).
List<List<bool>> qrMatrix(String data) {
  final image = qr.QrImage(qr.QrCode(payload: qr.QrPayload.fromString(data), errorCorrectLevel: qr.QrErrorCorrectLevel.medium));
  final n = image.moduleCount;
  return [
    for (var r = 0; r < n; r++) [for (var c = 0; c < n; c++) image.isDark(r, c)],
  ];
}

/// QR code imprimé comme une image raster (GS v 0), centré sur la largeur du papier,
/// envoyé en bandes de 24 lignes pour ne pas saturer la mémoire des petites imprimantes.
List<int> qrRaster(String data, {required int paperDots, int targetDots = 240}) {
  final m = qrMatrix(data);
  final n = m.length;
  const quiet = 2; // marge blanche en modules
  final module = (targetDots ~/ (n + 2 * quiet)).clamp(2, 12);
  final size = (n + 2 * quiet) * module;
  final width = paperDots;
  final left = ((width - size) ~/ 2).clamp(0, width);
  final bytesPerRow = (width + 7) >> 3;
  final rows = <Uint8List>[];
  for (var y = 0; y < size; y++) {
    final row = Uint8List(bytesPerRow);
    final my = y ~/ module - quiet;
    if (my >= 0 && my < n) {
      for (var x = 0; x < size; x++) {
        final mx = x ~/ module - quiet;
        if (mx >= 0 && mx < n && m[my][mx]) {
          final px = left + x;
          row[px >> 3] |= 0x80 >> (px & 7);
        }
      }
    }
    rows.add(row);
  }
  final out = <int>[];
  const band = 24;
  for (var y0 = 0; y0 < rows.length; y0 += band) {
    final h = (rows.length - y0) < band ? rows.length - y0 : band;
    out.addAll([_gs, 0x76, 0x30, 0x00, bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF]);
    for (var y = y0; y < y0 + h; y++) {
      out.addAll(rows[y]);
    }
  }
  out.add(0x0A);
  return out;
}
