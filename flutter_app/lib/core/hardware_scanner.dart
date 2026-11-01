import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Lecteur de codes intégré des terminaux de caisse Android (Sunmi, iMin, Urovo,
/// Newland, Zebra, Honeywell…). Côté natif : HardwareScannerChannel.kt.
class HardwareScanner {
  HardwareScanner._();

  static const _methods = MethodChannel('bf.omzakrevo/hw_scanner');
  static const _events = EventChannel('bf.omzakrevo/hw_scanner/events');
  static Stream<String>? _stream;
  static HardwareScannerInfo? _info;

  /// Vrai pendant qu'un écran de scan attend un code : les autres écrans ignorent alors les lectures.
  static bool exclusive = false;

  static bool get platformSupported => Platform.isAndroid;

  /// Codes lus et transmis par diffusion (le mode « clavier » est géré par un champ texte).
  static Stream<String> get results {
    if (!platformSupported) return const Stream.empty();
    return _stream ??= _events.receiveBroadcastStream().map((e) => '$e'.trim()).where((e) => e.isNotEmpty).handleError((_) {}).asBroadcastStream();
  }

  static Future<HardwareScannerInfo> info() async {
    if (_info != null) return _info!;
    if (!platformSupported) return _info = const HardwareScannerInfo('other', '', false);
    try {
      final m = await _methods.invokeMapMethod<String, dynamic>('info');
      return _info = HardwareScannerInfo(m?['brand'] as String? ?? 'other', m?['model'] as String? ?? '', m?['softTrigger'] as bool? ?? false);
    } catch (_) {
      return _info = const HardwareScannerInfo('other', '', false);
    }
  }

  /// Allume la tête de lecture et dit comment (ou pourquoi ce n'est pas possible).
  static Future<ScannerStart> start() async {
    if (!platformSupported) return const ScannerStart(false, 'Lecteur intégré : Android uniquement', null);
    try {
      final m = await _methods.invokeMapMethod<String, dynamic>('start');
      return ScannerStart(m?['triggered'] as bool? ?? false, m?['method'] as String? ?? '', m?['error'] as String?);
    } catch (e) {
      return ScannerStart(false, 'Erreur du module de scan', '$e');
    }
  }

  /// Ce que l'application voit du terminal (marque, service de scan, modèle de tête de lecture…).
  static Future<Map<String, dynamic>> diagnose() async {
    if (!platformSupported) return {'android': 'non'};
    try {
      return await _methods.invokeMapMethod<String, dynamic>('diagnose') ?? {};
    } catch (e) {
      return {'erreur': '$e'};
    }
  }

  static Future<void> stop() async {
    if (!platformSupported) return;
    try {
      await _methods.invokeMethod<void>('stop');
    } catch (_) {}
  }
}

class ScannerStart {
  const ScannerStart(this.triggered, this.method, this.error);
  final bool triggered;
  final String method;
  final String? error;
}

class HardwareScannerInfo {
  const HardwareScannerInfo(this.brand, this.model, this.softTrigger);
  final String brand;
  final String model;
  final bool softTrigger;

  /// Marque de terminal de caisse reconnue (lecteur intégré probable).
  bool get knownPos => brand != 'other';

  String get brandLabel => switch (brand) {
    'sunmi' => 'Sunmi',
    'zebra' => 'Zebra',
    'honeywell' => 'Honeywell',
    'newland' => 'Newland',
    'imin' => 'iMin',
    'urovo' => 'Urovo',
    _ => 'Autre marque',
  };
}

/// Source de lecture choisie dans Paramètres : « camera » ou « builtin ».
/// Par défaut : le lecteur intégré si l'appareil est un terminal de caisse reconnu.
Future<bool> useBuiltinScanner(String? setting) async {
  if (!HardwareScanner.platformSupported) return false;
  if (setting == 'builtin') return true;
  if (setting == 'camera') return false;
  return (await HardwareScanner.info()).knownPos;
}
