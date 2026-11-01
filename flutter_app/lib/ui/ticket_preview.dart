import 'package:flutter/material.dart';

import '../printing/escpos.dart' show qrMatrix;
import '../printing/ticket.dart';
import 'common.dart';

/// Aperçu du ticket tel qu'il sortira sur le papier, avec bouton Imprimer.
Future<void> showTicket(BuildContext context, Ticket ticket) async {
  final scope = AppScope.read(context);
  final width = await scope.printer.charsPerLine();
  final configured = await scope.printer.isConfigured();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ticket.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: width * 9.0 + 32,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF7),
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in ticket.previewBlocks(width))
                  if (b is QrCode)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Center(
                        child: SizedBox(width: 130, height: 130, child: CustomPaint(painter: QrPainter(b.data))),
                      ),
                    )
                  else
                    Text(
                      b as String,
                      style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Courier New', 'Courier'], fontSize: 13, height: 1.25, color: Colors.black87),
                    ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        FilledButton.icon(
          onPressed: configured
              ? () async {
                  final ok = await guard(ctx, () => scope.printer.print(ticket).then((_) => true), success: 'Ticket envoyé à l\'imprimante');
                  if (ok == true && ctx.mounted) Navigator.pop(ctx);
                }
              : null,
          icon: const Icon(Icons.print),
          label: Text(configured ? 'Imprimer' : 'Imprimante non configurée'),
        ),
      ],
    ),
  );
}

/// Impression directe si une imprimante est configurée, sinon aperçu.
Future<void> printOrPreview(BuildContext context, Ticket ticket) async {
  final scope = AppScope.read(context);
  if (await scope.printer.isConfigured()) {
    try {
      await scope.printer.print(ticket);
      return;
    } catch (e) {
      if (context.mounted) toast(context, '$e — aperçu affiché', error: true);
    }
  }
  if (context.mounted) await showTicket(context, ticket);
}

/// Dessine un QR code à l'écran (même matrice que celle imprimée).
class QrPainter extends CustomPainter {
  QrPainter(this.data) : _m = qrMatrix(data);
  final String data;
  final List<List<bool>> _m;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _m.length + 4;
    final cell = size.shortestSide / n;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final p = Paint()..color = Colors.black;
    for (var r = 0; r < _m.length; r++) {
      for (var c = 0; c < _m.length; c++) {
        if (_m[r][c]) canvas.drawRect(Rect.fromLTWH((c + 2) * cell, (r + 2) * cell, cell + 0.4, cell + 0.4), p);
      }
    }
  }

  @override
  bool shouldRepaint(QrPainter old) => old.data != data;
}
