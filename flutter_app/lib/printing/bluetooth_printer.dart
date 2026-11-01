import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'network_printer.dart';

/// Appareil Bluetooth vu par l'application.
class PairedPrinter {
  PairedPrinter(this.name, this.address, {this.type = 'unknown', this.bonded = true, this.printerLike = false});
  final String name;
  final String address;

  /// classic, ble, dual ou unknown
  final String type;
  final bool bonded;
  final bool printerLike;

  String get typeLabel => switch (type) {
    'classic' => 'Bluetooth classique',
    'ble' => 'Bluetooth LE',
    'dual' => 'Classique + LE',
    _ => 'Type inconnu',
  };

  factory PairedPrinter.fromMap(Map<Object?, Object?> m) =>
      PairedPrinter((m['name'] as String?) ?? '', m['address'] as String, type: (m['type'] as String?) ?? 'unknown', bonded: m['bonded'] == true, printerLike: m['printerLike'] == true);
}

/// Compte rendu d'une impression Bluetooth (affiché par le test d'impression).
class BluetoothPrintReport {
  BluetoothPrintReport({required this.transport, required this.method, required this.bytes, required this.reused});
  final String transport;
  final String? method;
  final int bytes;
  final bool reused;
  String get summary => '${transport == 'ble' ? 'Bluetooth LE' : 'Bluetooth classique'}${method != null ? ' · liaison $method' : ''} · $bytes octets${reused ? ' · liaison réutilisée' : ''}';
}

bool get bluetoothSupported => Platform.isAndroid || Platform.isWindows;

const _channel = MethodChannel('bf.omzakrevo/thermal_printer');

Future<int> _androidSdk() async {
  final s = await _channel.invokeMapMethod<String, Object?>('state');
  return (s?['sdk'] as int?) ?? 31;
}

/// Demande les autorisations utiles selon la version d'Android.
/// Android 12+ : « Appareils à proximité ». Android 11 et moins : localisation pour la recherche.
Future<void> ensureBluetoothPermissions({bool scan = false}) async {
  if (!Platform.isAndroid) return;
  final sdk = await _androidSdk();
  if (sdk >= 31) {
    final wanted = [Permission.bluetoothConnect, if (scan) Permission.bluetoothScan];
    final statuses = await wanted.request();
    if (statuses.values.any((s) => !s.isGranted)) {
      throw PrinterException(
        statuses.values.any((s) => s.isPermanentlyDenied)
            ? 'Autorisation « Appareils à proximité » refusée. Activez-la dans Paramètres Android > Applications > Caisse Pro > Autorisations.'
            : 'L\'application a besoin de l\'autorisation « Appareils à proximité » pour utiliser l\'imprimante Bluetooth.',
      );
    }
  } else if (scan) {
    final s = await Permission.locationWhenInUse.request();
    if (!s.isGranted) {
      throw PrinterException('Sur cette version d\'Android, la recherche Bluetooth exige l\'autorisation de localisation.');
    }
  }
}

PrinterException _fromPlatform(PlatformException e) {
  final details = e.details is String && (e.details as String).isNotEmpty ? '\n\nDétail technique :\n${e.details}' : '';
  return PrinterException('${e.message ?? e.code}$details');
}

/// Imprimantes déjà appairées dans les réglages Bluetooth du téléphone / de Windows.
Future<List<PairedPrinter>> pairedPrinters() async {
  if (!bluetoothSupported) throw PrinterException('Bluetooth non disponible sur cet appareil');
  await ensureBluetoothPermissions();
  if (Platform.isAndroid) {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('bonded') ?? [];
      return list.map(PairedPrinter.fromMap).toList();
    } on PlatformException catch (e) {
      throw _fromPlatform(e);
    }
  }
  final list = await PrintBluetoothThermal.pairedBluetooths;
  return list.map((b) => PairedPrinter(b.name, b.macAdress)).toList();
}

/// Recherche des appareils à proximité (y compris les imprimantes BLE non appairées). Android uniquement.
Future<List<PairedPrinter>> scanPrinters({int seconds = 8}) async {
  if (!Platform.isAndroid) return pairedPrinters();
  await ensureBluetoothPermissions(scan: true);
  try {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('scan', {'seconds': seconds}) ?? [];
    return list.map(PairedPrinter.fromMap).toList();
  } on PlatformException catch (e) {
    throw _fromPlatform(e);
  }
}

/// Imprimante thermique Bluetooth : classique (SPP) ou BLE.
class BluetoothPrinter implements PrinterTransport {
  BluetoothPrinter(this.address);
  final String address;

  static BluetoothPrintReport? lastReport;
  static String? _windowsConnected;

  // Une seule impression à la fois : la liaison Bluetooth n'est pas partageable.
  static Future<void> _queue = Future.value();

  @override
  Future<void> send(Uint8List bytes) {
    final job = _queue.then((_) => _send(bytes));
    _queue = job.catchError((_) {});
    return job;
  }

  Future<void> _send(Uint8List bytes) async {
    if (!bluetoothSupported) throw PrinterException('Bluetooth non disponible sur cet appareil');
    if (address.trim().isEmpty) throw PrinterException('Aucune imprimante Bluetooth choisie (Gestion > Paramètres)');
    await ensureBluetoothPermissions();
    if (Platform.isAndroid) {
      try {
        final r = await _channel.invokeMapMethod<String, Object?>('print', {'address': address, 'bytes': bytes, 'chunk': 256, 'delayMs': 20});
        lastReport = BluetoothPrintReport(
          transport: (r?['transport'] as String?) ?? 'classic',
          method: r?['method'] as String?,
          bytes: (r?['bytes'] as int?) ?? bytes.length,
          reused: r?['reused'] == true,
        );
      } on PlatformException catch (e) {
        throw _fromPlatform(e);
      }
      return;
    }
    // Windows : plugin print_bluetooth_thermal. Un seul envoi (le plugin ajoute un
    // octet au début de chaque envoi : découper corromprait les commandes ESC/POS).
    Future<bool> connect() async {
      if (_windowsConnected == address) return true;
      await PrintBluetoothThermal.disconnect;
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: address);
      _windowsConnected = ok ? address : null;
      return ok;
    }

    if (!await connect()) throw PrinterException('Imprimante Bluetooth injoignable ($address). Vérifiez qu\'elle est allumée et appairée dans Windows.');
    var ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      _windowsConnected = null;
      if (await connect()) ok = await PrintBluetoothThermal.writeBytes(bytes);
    }
    if (!ok) {
      _windowsConnected = null;
      throw PrinterException('Échec d\'envoi à l\'imprimante Bluetooth. Éteignez/rallumez-la puis réessayez.');
    }
    lastReport = BluetoothPrintReport(transport: 'classic', method: 'Windows', bytes: bytes.length, reused: false);
  }
}
