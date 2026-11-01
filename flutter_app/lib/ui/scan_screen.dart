import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/hardware_scanner.dart';
import '../core/money.dart';
import '../core/permissions.dart';
import '../printing/ticket_builder.dart';
import 'common.dart';
import 'order_screen.dart';
import 'orders_screen.dart';
import 'motion.dart';
import 'theme.dart';
import 'ticket_preview.dart';

bool get cameraScanSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Ouvre le scanner et renvoie le texte lu (QR, code-barres ou saisie manuelle).
/// Selon Paramètres : lecteur intégré du terminal de caisse (allumé automatiquement)
/// ou caméra. Une douchette USB/Bluetooth se comporte comme un clavier : le champ la reçoit.
Future<String?> scanCode(BuildContext context, {String title = 'Scanner un ticket'}) async {
  final settings = await AppScope.read(context).repo.settings();
  final builtin = await useBuiltinScanner(settings['scan_source']);
  if (!context.mounted) return null;
  return Navigator.push<String>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ScanPage(title: title, builtin: builtin),
    ),
  );
}

class _ScanPage extends StatefulWidget {
  const _ScanPage({required this.title, required this.builtin});
  final String title;
  final bool builtin;
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final manual = TextEditingController();
  final manualFocus = FocusNode();
  MobileScannerController? controller;
  StreamSubscription<String>? hwSub;
  late bool builtin = widget.builtin;
  bool hwTriggered = false;
  String? hwStatus;
  bool typing = false; // clavier à l'écran pour saisir le numéro
  bool done = false;

  @override
  void initState() {
    super.initState();
    if (builtin) {
      _startBuiltin();
    } else {
      _startCamera();
    }
  }

  void _startCamera() {
    if (cameraScanSupported) {
      controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
      );
    }
  }

  Future<void> _startBuiltin() async {
    HardwareScanner.exclusive = true;
    hwSub ??= HardwareScanner.results.listen(_finish);
    final r = await HardwareScanner.start();
    if (mounted) {
      setState(() {
        hwTriggered = r.triggered;
        hwStatus = [r.method, ?r.error].where((e) => e.isNotEmpty).join(' · ');
      });
    }
  }

  Future<void> _switchSource() async {
    if (builtin) {
      await HardwareScanner.stop();
      await hwSub?.cancel();
      hwSub = null;
      HardwareScanner.exclusive = false;
      setState(() {
        builtin = false;
        _startCamera();
      });
    } else {
      await controller?.dispose();
      setState(() {
        controller = null;
        builtin = true;
      });
      await _startBuiltin();
    }
  }

  void _finish(String value) {
    if (done || value.trim().isEmpty) return;
    done = true;
    Navigator.pop(context, value.trim());
  }

  Widget _builtinPanel() => PatternBackground(
    dark: true,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Pulse(child: const Icon(Icons.qr_code_scanner, size: 96, color: Colors.white)),
            const SizedBox(height: 16),
            Text(
              hwTriggered ? 'Lecteur allumé\nPrésentez le code devant la vitre du lecteur' : 'Appuyez sur le bouton de scan du terminal\n(sur le côté ou sous l\'écran) et présentez le code',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pas de bouton sur le côté ? Activez le « bouton de scan à l\'écran » (bouton flottant) dans l\'appli Scanner du terminal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (hwStatus != null) ...[
              const SizedBox(height: 6),
              Text(
                hwStatus!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(onPressed: _startBuiltin, icon: const Icon(Icons.refresh), label: const Text('Rallumer le lecteur')),
                if (cameraScanSupported)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: _switchSource,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Utiliser la caméra'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: gradientAppBar(
        context,
        title: Text(widget.title),
        actions: [
          if (c != null) IconButton(tooltip: 'Lampe', onPressed: () => c.toggleTorch(), icon: const Icon(Icons.flashlight_on)),
          if (c != null) IconButton(tooltip: 'Changer de caméra', onPressed: () => c.switchCamera(), icon: const Icon(Icons.cameraswitch)),
          if (c != null && HardwareScanner.platformSupported) IconButton(tooltip: 'Lecteur intégré du terminal', onPressed: _switchSource, icon: const Icon(Icons.barcode_reader)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: builtin
                ? _builtinPanel()
                : c == null
                ? PatternBackground(
                    dark: true,
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_scanner, size: 96, color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Scannez avec la douchette USB\nou saisissez le numéro ci-dessous',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: c,
                        onDetect: (capture) {
                          final v = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                          if (v != null) _finish(v);
                        },
                        errorBuilder: (context, error) => Center(
                          child: Text('Caméra indisponible : ${error.errorCode.name}', style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: Text(
                          'Placez le code dans le cadre',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]),
                        ),
                      ),
                    ],
                  ),
          ),
          Material(
            color: AppColors.paper,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      // En mode lecteur intégré, ce champ reçoit aussi les lecteurs réglés en
                      // « sortie clavier » ; le clavier de l'écran ne s'ouvre que sur demande.
                      child: TextField(
                        controller: manual,
                        focusNode: manualFocus,
                        autofocus: c == null,
                        keyboardType: builtin && !typing ? TextInputType.none : TextInputType.text,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Code lu ou n° saisi (ex. 261021-005)',
                          suffixIcon: builtin && !typing
                              ? IconButton(
                                  tooltip: 'Saisir au clavier',
                                  icon: const Icon(Icons.keyboard),
                                  onPressed: () {
                                    setState(() => typing = true);
                                    manualFocus.unfocus();
                                    Future.delayed(const Duration(milliseconds: 50), manualFocus.requestFocus);
                                  },
                                )
                              : null,
                        ),
                        onSubmitted: _finish,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: () => _finish(manual.text), child: const Text('OK')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (builtin) HardwareScanner.stop();
    HardwareScanner.exclusive = false;
    hwSub?.cancel();
    controller?.dispose();
    manual.dispose();
    manualFocus.dispose();
    super.dispose();
  }
}

/// Scan depuis la barre d'en-tête : retrouve la commande ou l'avoir et propose l'action utile.
Future<void> scanAndOpen(BuildContext context, {VoidCallback? onChanged}) async {
  final scope = AppScope.read(context);
  final code = await scanCode(context);
  if (code == null || !context.mounted) return;

  // Bon d'avoir
  final creditCode = code.toUpperCase().startsWith('AVOIR:') ? code.substring(6) : code;
  if (!code.toUpperCase().startsWith('CMD:')) {
    final credit = await scope.repo.creditByCode(creditCode);
    if (credit != null && context.mounted) {
      final status = switch (credit.status) {
        'active' => 'Actif',
        'exhausted' => 'Épuisé',
        _ => 'Annulé',
      };
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.confirmation_number, size: 40, color: AppColors.orange),
          title: const Text('Bon d\'avoir'),
          content: Text(
            'Solde : ${fcfa(credit.balance)} / ${fcfa(credit.initial)}\nStatut : $status${credit.customerName != null ? '\nClient : ${credit.customerName}' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
  }

  // Commande
  final order = await scope.repo.findOrder(code);
  if (!context.mounted) return;
  if (order == null) {
    toast(context, 'Aucune commande ni avoir ne correspond à « $code »', error: true);
    return;
  }
  if (order.status != 'open') {
    final d = await scope.repo.orderDetail(order.id);
    final shop = await scope.repo.shopInfo();
    if (context.mounted) {
      toast(context, order.status == 'closed' ? 'Commande N° ${order.number} déjà soldée' : 'Commande N° ${order.number} annulée');
      await showTicket(context, customerReceipt(shop, d));
    }
    return;
  }
  final user = scope.user;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.orange,
              child: Icon(Icons.receipt_long, color: Colors.white),
            ),
            title: Text('${order.tableLabel} · N° ${order.number}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Reste à payer : ${fcfa(order.balance)}'),
          ),
          if (user.can(Permission.takePayments))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop(ctx, 'pay'),
                icon: const Icon(Icons.payments),
                label: Text('Encaisser ${fcfa(order.balance)}'),
              ),
            ),
          ListTile(leading: const Icon(Icons.add_shopping_cart), title: const Text('Ajouter des articles'), onTap: () => Navigator.pop(ctx, 'add')),
          ListTile(leading: const Icon(Icons.receipt), title: const Text('Voir l\'addition'), onTap: () => Navigator.pop(ctx, 'bill')),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'pay':
      await runPaymentFlow(context, order);
    case 'add':
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddItemsPage(target: order)));
    case 'bill':
      final d = await scope.repo.orderDetail(order.id);
      final shop = await scope.repo.shopInfo();
      if (context.mounted) await showTicket(context, customerReceipt(shop, d));
  }
  onChanged?.call();
}
