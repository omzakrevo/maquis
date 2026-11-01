import '../data/models.dart';
import '../data/pos_repository.dart';
import 'bluetooth_printer.dart';
import 'escpos.dart';
import 'network_printer.dart';
import 'ticket.dart';

/// Envoie un ticket à l'imprimante configurée (réseau ou Bluetooth).
class PrintService {
  PrintService(this.repo, {PrinterTransport Function(PrinterSettings s)? transportFactory}) : _factory = transportFactory ?? defaultTransport;
  final PosRepository repo;
  final PrinterTransport Function(PrinterSettings s) _factory;

  static PrinterTransport defaultTransport(PrinterSettings s) => switch (s.type) {
    PrinterType.bluetooth => BluetoothPrinter(s.btAddress),
    _ => NetworkPrinter(s.host, port: s.port),
  };

  Future<bool> isConfigured() async => (await repo.printerSettings()).configured;

  Future<int> charsPerLine() async => (await repo.printerSettings()).charsPerLine;

  Future<void> print(Ticket ticket) async {
    final s = await repo.printerSettings();
    if (!s.configured) throw PrinterException('Aucune imprimante configurée (Gestion > Paramètres)');
    final bytes = EscPosEncoder(charsPerLine: s.charsPerLine, stripAccentsMode: s.stripAccents, codePage: s.codePage, qrAsImage: s.qrAsImage).encode(ticket);
    await _factory(s).send(bytes);
  }
}
