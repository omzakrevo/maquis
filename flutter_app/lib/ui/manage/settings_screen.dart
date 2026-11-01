import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/hardware_scanner.dart';
import '../../data/models.dart';
import '../../printing/bluetooth_printer.dart';
import '../../printing/ticket.dart';
import '../common.dart';
import '../scan_screen.dart';
import '../ticket_preview.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final c = <String, TextEditingController>{
    for (final k in ['shop_name', 'shop_address', 'shop_phone', 'ticket_footer', 'printer_host', 'printer_port', 'code_page']) k: TextEditingController(),
  };
  String paperWidth = '58';
  bool stripAccents = true;
  bool loading = true;
  PrinterType type = PrinterType.none;
  String btAddress = '';
  String btName = '';
  List<PairedPrinter>? paired;
  bool searching = false;
  bool testing = false;
  AfterOrderPrint afterOrder = AfterOrderPrint.client;
  bool qrImage = true;
  BusinessMode mode = BusinessMode.restaurant;
  String scanSource = 'auto';
  HardwareScannerInfo? scanner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) _load();
  }

  Future<void> _load() async {
    final s = await AppScope.read(context).repo.settings();
    final hw = await HardwareScanner.info();
    if (!mounted) return;
    scanner = hw;
    setState(() {
      for (final e in c.entries) {
        e.value.text = s[e.key] ?? '';
      }
      paperWidth = s['paper_width'] == '80' ? '80' : '58';
      stripAccents = (s['strip_accents'] ?? '1') == '1';
      type = PrinterType.values.firstWhere((t) => t.name == s['printer_type'], orElse: () => (s['printer_host'] ?? '').isEmpty ? PrinterType.none : PrinterType.network);
      btAddress = s['bt_address'] ?? '';
      btName = s['bt_name'] ?? '';
      afterOrder = AfterOrderPrint.values.firstWhere((v) => v.name == s['print_after_order'], orElse: () => AfterOrderPrint.client);
      qrImage = (s['qr_image'] ?? '1') == '1';
      mode = BusinessMode.parse(s['business_mode']);
      scanSource = s['scan_source'] ?? 'auto';
      loading = false;
    });
  }

  Future<bool> _save({bool quiet = false}) async {
    final scope = AppScope.read(context);
    final r = await guard(
      context,
      () => scope.repo
          .saveSettings(scope.user, {
            for (final e in c.entries) e.key: e.value.text.trim(),
            'paper_width': paperWidth,
            'strip_accents': stripAccents ? '1' : '0',
            'printer_type': type.name,
            'bt_address': btAddress,
            'bt_name': btName,
            'print_after_order': afterOrder.name,
            'qr_image': qrImage ? '1' : '0',
            'business_mode': mode.name,
            'scan_source': scanSource,
          })
          .then((_) => true),
      success: quiet ? null : 'Paramètres enregistrés',
    );
    if (r == true && !quiet && mode != AppColors.mode && mounted) await _switchMode();
    return r == true;
  }

  /// Nouveau type d'établissement : retirer les produits de démonstration
  /// (boissons, plats) puis changer couleurs, logo et icône de l'application.
  Future<void> _switchMode() async {
    final scope = AppScope.read(context);
    final demo = await scope.repo.demoProductsActive();
    if (mode.directSale && demo > 0 && mounted) {
      final hide = await confirm(
        context,
        'Produits de démonstration',
        'Les $demo produits livrés en exemple (bières, sodas, plats…) ne concernent pas ${mode == BusinessMode.pharmacy ? 'une pharmacie' : 'une boutique'}. Les retirer de la vente ?\n\nIls ne sont pas supprimés : vous pouvez les remettre en vente dans Gestion > Produits.',
        ok: 'Retirer',
      );
      if (hide && mounted) await guard(context, () => scope.repo.hideDemoProducts(scope.user), success: 'Produits de démonstration retirés');
    }
    AppColors.apply(mode); // l'application se redessine (couleurs, logo, nom)
  }

  Future<void> _test() async {
    if (!await _save(quiet: true) || !mounted) return;
    final t = Ticket('Test imprimante', [
      TextLine(c['shop_name']!.text, align: TAlign.center, bold: true, big: true),
      TextLine('Test d\'impression', align: TAlign.center),
      Separator(),
      PairLine('Imprimante', type == PrinterType.bluetooth ? (btName.isEmpty ? btAddress : btName) : c['printer_host']!.text),
      PairLine('Largeur', '$paperWidth mm'),
      TextLine('Accents : é è à ç ô ù'),
      TextLine('1234567890' * 5),
      QrCode('MAQUIS-RESTO-PRO'),
      TextLine('Si vous lisez ceci, tout fonctionne.', align: TAlign.center),
      Feed(),
    ]);
    if (type == PrinterType.none) {
      await showTicket(context, t);
      return;
    }
    if (type == PrinterType.bluetooth && btAddress.isEmpty) {
      toast(context, 'Choisissez d\'abord une imprimante dans la liste', error: true);
      return;
    }
    setState(() => testing = true);
    String? error;
    try {
      await AppScope.read(context).printer.print(t);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() => testing = false);
    final report = type == PrinterType.bluetooth ? BluetoothPrinter.lastReport : null;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(error == null ? Icons.check_circle : Icons.error, color: error == null ? const Color(0xFF2F9E44) : Theme.of(ctx).colorScheme.error, size: 44),
        title: Text(error == null ? 'Ticket envoyé' : 'L\'impression a échoué'),
        content: SingleChildScrollView(
          child: SelectableText(
            error == null
                ? 'Les données ont été transmises${report != null ? ' (${report.summary})' : ''}.\n\nSi rien ne sort : vérifiez le papier (face thermique vers la tête), la largeur 58/80 mm, et essayez « Imprimer sans accents ».'
                : '$error\n\nÀ vérifier :\n• imprimante allumée, batterie chargée, voyant Bluetooth actif ;\n• imprimante appairée dans les réglages Bluetooth ;\n• aucun autre téléphone connecté à elle ;\n• rapprochez-vous (moins de 5 m).',
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _searchBluetooth({bool nearby = false}) async {
    setState(() => searching = true);
    final list = await guard(context, () => nearby ? scanPrinters() : pairedPrinters());
    if (!mounted) return;
    setState(() {
      searching = false;
      if (list != null) paired = list;
    });
    if (list != null && list.isEmpty) {
      toast(context, nearby ? 'Aucun appareil trouvé à proximité. L\'imprimante est-elle allumée ?' : 'Aucun appareil appairé. Appairez l\'imprimante ou utilisez « À proximité ».', error: true);
    }
  }

  Future<void> _diagnoseScanner() async {
    final start = await HardwareScanner.start(); // tentative d'allumage, pour le compte rendu
    final d = await HardwareScanner.diagnose();
    await HardwareScanner.stop();
    if (!mounted) return;
    final sunmiModel = d['sunmiModel'];
    final lines = <String>[
      'Appareil : ${d['manufacturer'] ?? '?'} ${d['model'] ?? ''} (${d['brandBuild'] ?? ''}, ${d['device'] ?? ''})',
      'Android : ${d['android'] ?? '?'}',
      'Marque reconnue : ${d['detected'] ?? '?'}',
      'Service de scan Sunmi : ${d['sunmiService'] == true ? 'présent' : 'absent'}${d['sunmiConnected'] == true ? ', connecté' : ''}',
      if (sunmiModel != null) 'Tête de lecture Sunmi : $sunmiModel${sunmiModel == 100 ? ' (AUCUNE : ce modèle scanne avec la caméra)' : ''}',
      if (d['sunmiError'] != null) 'Erreur Sunmi : ${d['sunmiError']}',
      'ScanManager système (Urovo…) : ${d['urovoScanManager'] == true ? 'présent' : 'absent'}',
      'Applis de scan trouvées : ${(d['scannerApps'] as String?)?.isNotEmpty == true ? d['scannerApps'] : 'aucune'}',
      'Allumage : ${start.triggered ? 'OK' : 'échec'} — ${start.method}${start.error != null ? ' — ${start.error}' : ''}',
      'Dernier code reçu : ${d['lastCode'] ?? 'aucun'}',
      'Pilotes de scan installés :\n${d['scanPackages'] ?? '?'}',
    ];
    final text = lines.join('\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnostic du lecteur'),
        content: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 13))),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              toast(ctx, 'Copié : collez-le dans un message');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copier'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Widget _field(String key, String label, {TextInputType? type, bool digits = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c[key],
      keyboardType: type,
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: gradientAppBar(
      context,
      title: const Text('Paramètres'),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Enregistrer'),
        ),
      ],
    ),
    body: PatternBackground(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SectionTitle('Type d\'établissement'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final (m, icon, label) in [
                          (BusinessMode.restaurant, Icons.restaurant, 'Maquis / Resto / Bar'),
                          (BusinessMode.shop, Icons.storefront, 'Boutique / Alimentation'),
                          (BusinessMode.pharmacy, Icons.local_pharmacy, 'Pharmacie'),
                        ])
                          ChoiceChip(avatar: Icon(icon, size: 18), label: Text(label), selected: mode == m, onSelected: (_) => setState(() => mode = m)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                      child: Text(switch (mode) {
                        BusinessMode.shop =>
                          'Boutique / alimentation : on scanne le code-barres, le produit s\'ajoute au panier, puis « Encaisser » (espèces, Orange Money…), monnaie calculée, ticket imprimé. Pas de table ni de serveuse.',
                        BusinessMode.pharmacy =>
                          'Pharmacie : vente directe par scan du médicament, encaissement et ticket. Renseignez le prix d\'achat de chaque médicament (fiche, entrée de stock ou Excel) pour suivre marges, bénéfices et valeur du stock (Gestion > Marges et bénéfices).',
                        BusinessMode.restaurant => 'Maquis / restaurant / bar : commandes par table, serveuses, bons bar/cuisine, addition puis encaissement à la caisse.',
                      }, style: TextStyle(color: AppColors.muted)),
                    ),
                    const SectionTitle('Établissement (en-tête des tickets)'),
                    _field('shop_name', 'Nom'),
                    _field('shop_address', 'Adresse / quartier'),
                    _field('shop_phone', 'Téléphone', type: TextInputType.phone),
                    _field('ticket_footer', 'Message en bas du ticket'),
                    const SectionTitle('Imprimante thermique'),
                    SegmentedButton<PrinterType>(
                      showSelectedIcon: !isCompact(context),
                      segments: [
                        ButtonSegment(value: PrinterType.none, icon: isCompact(context) ? null : const Icon(Icons.visibility), label: const Text('Aperçu', maxLines: 1, softWrap: false)),
                        ButtonSegment(value: PrinterType.network, icon: isCompact(context) ? null : const Icon(Icons.lan), label: const Text('Réseau', maxLines: 1, softWrap: false)),
                        ButtonSegment(value: PrinterType.bluetooth, icon: isCompact(context) ? null : const Icon(Icons.bluetooth), label: const Text('Bluetooth', maxLines: 1, softWrap: false)),
                      ],
                      selected: {type},
                      onSelectionChanged: (v) => setState(() => type = v.first),
                    ),
                    const SizedBox(height: 12),
                    if (type == PrinterType.none) const Text('Pas d\'imprimante : les tickets s\'affichent à l\'écran (le client peut les photographier).'),
                    if (type == PrinterType.network) ...[
                      const Text('Imprimante Ethernet ou Wi-Fi, port RAW 9100 (réglage d\'usine de la plupart des modèles).'),
                      const SizedBox(height: 12),
                      _field('printer_host', 'Adresse IP (ex. 192.168.1.100)'),
                      _field('printer_port', 'Port', digits: true),
                    ],
                    if (type == PrinterType.bluetooth) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            bluetoothSupported
                                ? '1. Allumez l\'imprimante. Appairez-la dans les réglages Bluetooth (code souvent 0000 ou 1234) — ou utilisez « À proximité » pour les modèles BLE.\n2. Choisissez-la dans la liste.\n3. Lancez le ticket de test : un compte rendu s\'affiche.'
                                : 'Le Bluetooth n\'est pas disponible sur cet appareil.',
                          ),
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: btAddress.isEmpty ? Colors.grey.shade300 : AppColors.orange.withValues(alpha: 0.15),
                          child: Icon(Icons.print, color: btAddress.isEmpty ? Colors.grey : AppColors.orange),
                        ),
                        title: Text(btAddress.isEmpty ? 'Aucune imprimante choisie' : (btName.isEmpty ? btAddress : btName), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: btAddress.isEmpty ? null : Text(btAddress),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(onPressed: searching || !bluetoothSupported ? null : () => _searchBluetooth(), icon: const Icon(Icons.link), label: const Text('Appairées')),
                          if (Platform.isAndroid)
                            FilledButton.tonalIcon(onPressed: searching ? null : () => _searchBluetooth(nearby: true), icon: const Icon(Icons.bluetooth_searching), label: const Text('À proximité')),
                          if (searching)
                            const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (paired != null)
                        Card(
                          child: Column(
                            children: [
                              for (final d in paired!)
                                ListTile(
                                  leading: Icon(d.address == btAddress ? Icons.radio_button_checked : Icons.radio_button_off, color: AppColors.orange),
                                  title: Text(d.name.isEmpty ? 'Appareil sans nom' : d.name, style: TextStyle(fontWeight: d.printerLike ? FontWeight.w700 : null)),
                                  subtitle: Text('${d.address} · ${d.typeLabel}${d.bonded ? '' : ' · non appairé'}'),
                                  trailing: d.printerLike ? const Chip(label: Text('Imprimante'), visualDensity: VisualDensity.compact) : null,
                                  onTap: () async {
                                    setState(() {
                                      btAddress = d.address;
                                      btName = d.name;
                                    });
                                    await _save(quiet: true);
                                    if (mounted) toast(this.context, '« ${d.name.isEmpty ? d.address : d.name} » choisie. Lancez le ticket de test.');
                                  },
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (HardwareScanner.platformSupported) ...[
                      const SectionTitle('Lecteur de codes (QR, code-barres)'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final (v, l) in [('auto', 'Automatique'), ('builtin', 'Lecteur intégré du terminal'), ('camera', 'Caméra')])
                            ChoiceChip(label: Text(l), selected: scanSource == v, onSelected: (_) => setState(() => scanSource = v)),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: Text(
                          [
                            'Appareil : ${scanner?.model ?? '?'}${scanner != null && scanner!.knownPos ? ' (${scanner!.brandLabel})' : ''}.',
                            if (scanSource == 'auto')
                              scanner?.knownPos == true
                                  ? 'Terminal de caisse reconnu : le lecteur intégré sera utilisé.'
                                  : 'Marque non reconnue : la caméra sera utilisée (choisissez « Lecteur intégré » si votre terminal en a un).',
                            if (scanSource != 'camera' && scanner?.softTrigger == true) 'Le lecteur s\'allume tout seul quand l\'application demande un scan.',
                            if (scanSource != 'camera' && scanner?.softTrigger != true) 'Sur ce modèle, appuyez sur le bouton de scan du terminal quand l\'écran de scan s\'affiche.',
                            'Le bouton physique fonctionne aussi directement sur l\'écran de commande / vente.',
                          ].join('\n'),
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            if (!await _save(quiet: true) || !context.mounted) return;
                            final v = await scanCode(context, title: 'Test du lecteur');
                            if (v != null && context.mounted) toast(context, 'Lu : $v');
                          },
                          icon: const Icon(Icons.barcode_reader),
                          label: const Text('Tester le lecteur'),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(onPressed: _diagnoseScanner, icon: const Icon(Icons.troubleshoot), label: const Text('Diagnostic du lecteur')),
                      ),
                    ],
                    const SectionTitle('Après validation d\'une commande, imprimer'),
                    // Puces : lisibles même sur un écran de 5".
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [for (final v in AfterOrderPrint.values) ChoiceChip(label: Text(v.label), selected: afterOrder == v, onSelected: (_) => setState(() => afterOrder = v))],
                    ),
                    const SizedBox(height: 6),
                    Text(switch (afterOrder) {
                      AfterOrderPrint.client => 'Le client reçoit son ticket avec les prix, le total et le QR pour payer.',
                      AfterOrderPrint.kitchen => 'Seuls les bons sans prix pour le bar et la cuisine sont imprimés.',
                      AfterOrderPrint.both => 'Ticket client + bons bar/cuisine.',
                      AfterOrderPrint.none => 'Rien n\'est imprimé automatiquement (bouton « Imprimer » dans En cours).',
                    }, style: TextStyle(color: AppColors.muted)),
                    const SectionTitle('Format du ticket'),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: '58', label: Text(isCompact(context) ? '58 mm' : '58 mm (32 car.)')),
                        ButtonSegment(value: '80', label: Text(isCompact(context) ? '80 mm' : '80 mm (48 car.)')),
                      ],
                      selected: {paperWidth},
                      onSelectionChanged: (s) => setState(() => paperWidth = s.first),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: stripAccents,
                      onChanged: (v) => setState(() => stripAccents = v),
                      title: const Text('Imprimer sans accents'),
                      subtitle: const Text('Recommandé si les accents sortent en caractères bizarres'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: qrImage,
                      onChanged: (v) => setState(() => qrImage = v),
                      title: const Text('QR code en image'),
                      subtitle: const Text('Compatible avec toutes les imprimantes. Désactivez seulement si le QR sort déformé.'),
                    ),
                    if (!stripAccents) _field('code_page', 'Table de caractères ESC t (19 = CP858 sur Epson)', digits: true),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: testing ? null : _test,
                      icon: testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print),
                      label: Text(testing ? 'Envoi en cours…' : 'Enregistrer et imprimer un ticket de test'),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }
}
