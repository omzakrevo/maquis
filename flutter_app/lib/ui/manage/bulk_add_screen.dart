import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/hardware_scanner.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/pos_repository.dart' show normalizeBarcode;
import '../common.dart';
import '../scan_screen.dart';
import '../theme.dart';

class _Row {
  _Row({String barcode = '', String category = ''}) : barcode = TextEditingController(text: barcode), category = TextEditingController(text: category);
  final name = TextEditingController();
  final TextEditingController category;
  final price = TextEditingController();
  final cost = TextEditingController();
  final stock = TextEditingController();
  final TextEditingController barcode;
  final nameFocus = FocusNode();
  final key = UniqueKey();

  bool get blank => name.text.trim().isEmpty && price.text.trim().isEmpty && cost.text.trim().isEmpty && stock.text.trim().isEmpty && barcode.text.trim().isEmpty;

  void dispose() {
    for (final c in [name, category, price, cost, stock, barcode]) {
      c.dispose();
    }
    nameFocus.dispose();
  }
}

/// Enregistrement de plusieurs articles d'un coup : on scanne les codes-barres à la chaîne
/// (douchette, lecteur intégré ou caméra) puis on complète nom et prix ; tout est enregistré
/// en une fois, avec le stock de départ et le prix d'achat.
class BulkAddScreen extends StatefulWidget {
  const BulkAddScreen({super.key, this.existing = const []});

  /// Catalogue actuel (pour signaler un code déjà enregistré).
  final List<Product> existing;
  @override
  State<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends State<BulkAddScreen> {
  final rows = <_Row>[];
  final scanInput = TextEditingController();
  final scanFocus = FocusNode();
  StreamSubscription<String>? hw;
  String? message;
  bool messageError = false;
  bool saving = false;
  late final List<String> cats = (widget.existing.map((p) => p.category).toSet().toList()..sort());

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      rows.add(_Row(category: cats.isEmpty ? '' : cats.first));
    }
    hw = HardwareScanner.results.listen((code) {
      if (!HardwareScanner.exclusive && mounted) _onCode(code);
    });
  }

  @override
  void dispose() {
    hw?.cancel();
    scanInput.dispose();
    scanFocus.dispose();
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _say(String m, {bool error = false}) => setState(() {
    message = m;
    messageError = error;
  });

  /// Un code lu : nouvelle ligne pré-remplie, ou +1 au stock si le code est déjà dans la liste.
  void _onCode(String raw) {
    var v = raw.trim();
    if (v.toUpperCase().startsWith('PRD:')) v = v.substring(4);
    final code = normalizeBarcode(v);
    if (code == null) return;
    final known = widget.existing.where((p) => p.barcode == code).firstOrNull;
    if (known != null) {
      _say('« ${known.name} » est déjà enregistré avec ce code. Pour ajouter du stock : Gestion > Stocks.', error: true);
      return;
    }
    final inList = rows.where((r) => normalizeBarcode(r.barcode.text) == code).firstOrNull;
    if (inList != null) {
      final q = (int.tryParse(inList.stock.text) ?? 0) + 1;
      setState(() => inList.stock.text = '$q');
      _say('Code $code déjà dans la liste : stock porté à $q.');
      return;
    }
    // On remplit d'abord une ligne vide sans code, sinon on en ajoute une.
    final free = rows.where((r) => r.barcode.text.trim().isEmpty && r.name.text.trim().isEmpty).firstOrNull;
    final row = free ?? _Row(category: rows.isEmpty ? '' : rows.last.category.text);
    setState(() {
      row.barcode.text = code;
      if (row.stock.text.isEmpty) row.stock.text = '1';
      if (free == null) rows.add(row);
    });
    _say('Code $code ajouté : saisissez le nom et le prix.');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.nameFocus.requestFocus();
    });
  }

  /// Caméra (ou lecteur intégré) en boucle jusqu'à « Annuler ».
  Future<void> _scanLoop() async {
    var n = 0;
    while (mounted) {
      final v = await scanCode(context, title: 'Scanner les articles (${rows.where((r) => r.barcode.text.isNotEmpty).length} lus) — Annuler pour terminer');
      if (v == null || !mounted) break;
      _onCode(v);
      n++;
    }
    if (n > 0) _say('$n code(s) scanné(s). Complétez les noms et les prix puis enregistrez.');
  }

  Future<void> _save() async {
    final scope = AppScope.read(context);
    final filled = rows.where((r) => !r.blank).toList();
    if (filled.isEmpty) {
      _say('Ajoutez au moins un article.', error: true);
      return;
    }
    final items = <NewProductInput>[];
    for (final (i, r) in filled.indexed) {
      final price = parseFcfa(r.price.text);
      if (r.name.text.trim().isEmpty || price == null) {
        _say('Ligne ${i + 1} : nom et prix de vente obligatoires.', error: true);
        return;
      }
      items.add(
        NewProductInput(
          name: r.name.text,
          category: r.category.text,
          price: price,
          cost: parseFcfa(r.cost.text),
          stock: int.tryParse(r.stock.text.trim()) ?? 0,
          barcode: r.barcode.text,
          alertQty: (int.tryParse(r.stock.text.trim()) ?? 0) > 0 ? 2 : 0,
        ),
      );
    }
    setState(() => saving = true);
    final n = await guard(context, () => scope.repo.addProducts(scope.user, items));
    if (!mounted) return;
    setState(() => saving = false);
    if (n != null) {
      toast(context, '$n article(s) enregistré(s)');
      Navigator.pop(context, n);
    }
  }

  InputDecoration _dec(String label, {String? suffix}) => InputDecoration(labelText: label, suffixText: suffix, isDense: true);

  Widget _rowCard(int i, _Row r, bool wide) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final name = TextField(controller: r.name, focusNode: r.nameFocus, textCapitalization: TextCapitalization.sentences, decoration: _dec('Nom de l\'article'));
    final cat = Autocomplete<String>(
      initialValue: TextEditingValue(text: r.category.text),
      optionsBuilder: (v) => cats.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: (v) => r.category.text = v,
      fieldViewBuilder: (ctx, ctrl, focus, submit) {
        ctrl.addListener(() => r.category.text = ctrl.text);
        return TextField(controller: ctrl, focusNode: focus, decoration: _dec('Catégorie'));
      },
    );
    final price = TextField(
      controller: r.price,
      keyboardType: TextInputType.number,
      inputFormatters: digits,
      decoration: _dec('Prix vente', suffix: 'F'),
    );
    final cost = TextField(
      controller: r.cost,
      keyboardType: TextInputType.number,
      inputFormatters: digits,
      decoration: _dec('Prix achat', suffix: 'F'),
    );
    final stock = TextField(controller: r.stock, keyboardType: TextInputType.number, inputFormatters: digits, decoration: _dec('Stock'));
    final code = TextField(
      controller: r.barcode,
      decoration: _dec('Code-barres').copyWith(
        suffixIcon: IconButton(
          tooltip: 'Scanner',
          icon: const Icon(Icons.qr_code_scanner, size: 20),
          onPressed: () async {
            final v = await scanCode(context, title: 'Code-barres de la ligne ${i + 1}');
            if (v != null) setState(() => r.barcode.text = normalizeBarcode(v.replaceFirst(RegExp('^PRD:', caseSensitive: false), '')) ?? '');
          },
        ),
      ),
    );
    final remove = IconButton(
      tooltip: 'Retirer la ligne',
      onPressed: () => setState(() {
        rows.remove(r);
        r.dispose();
      }),
      icon: const Icon(Icons.close, color: AppColors.red),
    );
    return Card(
      key: r.key,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 10),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(flex: 4, child: name),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: cat),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: price),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: cost),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: stock),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: code),
                  remove,
                ],
              )
            : Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Article ${i + 1}',
                        style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      remove,
                    ],
                  ),
                  name,
                  cat,
                  Row(
                    children: [
                      Expanded(child: price),
                      const SizedBox(width: 8),
                      Expanded(child: cost),
                      const SizedBox(width: 8),
                      SizedBox(width: 70, child: stock),
                    ],
                  ),
                  code,
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, title: const Text('Ajout multiple')),
      body: PatternBackground(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Scannez les articles un par un', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text('Chaque code lu crée une ligne (le même code deux fois = stock +1). Complétez ensuite nom et prix.', style: TextStyle(color: AppColors.muted)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('bulk-scan-input'),
                                controller: scanInput,
                                focusNode: scanFocus,
                                decoration: const InputDecoration(prefixIcon: Icon(Icons.barcode_reader), hintText: 'Douchette ou saisie du code', isDense: true),
                                onSubmitted: (v) {
                                  _onCode(v);
                                  scanInput.clear();
                                  scanFocus.requestFocus();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(onPressed: _scanLoop, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner')),
                          ],
                        ),
                        if (message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              message!,
                              style: TextStyle(color: messageError ? AppColors.red : AppColors.green, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                for (final (i, r) in rows.indexed) _rowCard(i, r, wide),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('bulk-add-row'),
                    onPressed: () => setState(() => rows.add(_Row(category: rows.isEmpty ? '' : rows.last.category.text))),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une ligne'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('bulk-save'),
        onPressed: saving ? null : _save,
        icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
        label: const Text('Tout enregistrer'),
      ),
    );
  }
}
