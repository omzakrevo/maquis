// Modèle de ticket indépendant de l'imprimante : sert à l'aperçu écran
// et à l'encodage ESC/POS.
enum TAlign { left, center, right }

sealed class TicketElement {}

class TextLine extends TicketElement {
  TextLine(this.text, {this.align = TAlign.left, this.bold = false, this.big = false});
  final String text;
  final TAlign align;
  final bool bold;
  final bool big; // double largeur + double hauteur
}

/// Ligne "libellé ......... montant" justifiée sur la largeur du papier.
class PairLine extends TicketElement {
  PairLine(this.left, this.right, {this.bold = false});
  final String left;
  final String right;
  final bool bold;
}

class Separator extends TicketElement {
  Separator([this.char = '-']);
  final String char;
}

class QrCode extends TicketElement {
  QrCode(this.data, {this.size = 6});
  final String data;
  final int size;
}

class Feed extends TicketElement {
  Feed([this.lines = 1]);
  final int lines;
}

class Ticket {
  Ticket(this.title, this.elements);
  final String title;
  final List<TicketElement> elements;

  /// Mise en page texte, identique à ce que sort l'imprimante (sans styles).
  List<String> layout(int width) {
    final out = <String>[];
    for (final e in elements) {
      switch (e) {
        case TextLine():
          final w = e.big ? width ~/ 2 : width;
          for (final l in wrap(e.text, w)) {
            out.add(_aligned(e.big ? l.split('').join(' ') : l, width, e.align));
          }
        case PairLine():
          out.addAll(pairLines(e.left, e.right, width));
        case Separator():
          out.add(e.char * width);
        case QrCode():
          out.add(_aligned('[ QR code ]', width, TAlign.center));
        case Feed():
          for (var i = 0; i < e.lines; i++) {
            out.add('');
          }
      }
    }
    return out;
  }

  String toPlainText(int width) => layout(width).join('\n');

  /// Aperçu : blocs de texte (String) et QR codes (QrCode) dans l'ordre d'impression.
  List<Object> previewBlocks(int width) {
    final out = <Object>[];
    final buf = <String>[];
    void flush() {
      if (buf.isNotEmpty) out.add(buf.join('\n'));
      buf.clear();
    }

    for (final e in elements) {
      if (e is QrCode) {
        flush();
        out.add(e);
      } else {
        buf.addAll(Ticket('', [e]).layout(width));
      }
    }
    flush();
    return out;
  }
}

String _aligned(String s, int width, TAlign a) {
  if (s.length >= width) return s;
  switch (a) {
    case TAlign.left:
      return s;
    case TAlign.right:
      return s.padLeft(width);
    case TAlign.center:
      return ' ' * ((width - s.length) ~/ 2) + s;
  }
}

/// Coupe un texte en lignes de [width] caractères maximum, sur les espaces si possible.
List<String> wrap(String text, int width) {
  if (width <= 0) return [text];
  final lines = <String>[];
  for (final para in text.split('\n')) {
    var rest = para.trimRight();
    if (rest.isEmpty) {
      lines.add('');
      continue;
    }
    while (rest.length > width) {
      var cut = rest.lastIndexOf(' ', width);
      if (cut <= 0) cut = width;
      lines.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    lines.add(rest);
  }
  return lines;
}

List<String> pairLines(String left, String right, int width) {
  if (right.isEmpty) return wrap(left, width);
  final maxLeft = width - right.length - 1;
  // Pas la place pour les deux sur une ligne sans couper un mot court (date,
  // montant…) : libellé sur sa ligne, valeur alignée à droite en dessous.
  if (maxLeft < 4 || (left.length > maxLeft && maxLeft < 18)) return [...wrap(left, width), right.padLeft(width)];
  final leftLines = wrap(left, maxLeft);
  final last = leftLines.removeLast();
  return [...leftLines, last + ' ' * (width - last.length - right.length) + right];
}
