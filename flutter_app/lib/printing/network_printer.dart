import 'dart:io';
import 'dart:typed_data';

/// Imprimante thermique réseau (Ethernet/Wi-Fi), port RAW 9100.
/// USB et Bluetooth : à ajouter via un adaptateur dédié (voir docs/architecture.md).
abstract class PrinterTransport {
  Future<void> send(Uint8List bytes);
}

class NetworkPrinter implements PrinterTransport {
  NetworkPrinter(this.host, {this.port = 9100, this.timeout = const Duration(seconds: 5)});
  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<void> send(Uint8List bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
    } on SocketException catch (e) {
      throw PrinterException('Imprimante $host:$port injoignable (${e.osError?.message ?? e.message})');
    } finally {
      await socket?.close();
      socket?.destroy();
    }
  }
}

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;
  @override
  String toString() => message;
}
