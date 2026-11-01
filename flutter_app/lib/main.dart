import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'ui/theme.dart';
import 'data/database.dart';
import 'data/pos_repository.dart';

const dbFileName = 'maquis_resto_v1.db'; // nom conservé depuis la V0.1

Future<String> _databasePath(DatabaseFactory factory) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return p.join(await factory.getDatabasesPath(), dbFileName);
  }
  // Bureau (Windows) : dossier applicatif de l'utilisateur, indépendant du
  // dossier depuis lequel l'exe est lancé (ex. %APPDATA%\bf.omzakrevo\...).
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final target = p.join(dir.path, dbFileName);
  // Reprise d'une base V0.1, qui était créée dans le dossier courant.
  final legacy = File(p.join(await factory.getDatabasesPath(), dbFileName));
  if (!File(target).existsSync() && legacy.existsSync()) {
    await legacy.copy(target);
  }
  return target;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final DatabaseFactory factory;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  } else {
    factory = mobile.databaseFactory;
  }
  final path = await _databasePath(factory);
  await Directory(p.dirname(path)).create(recursive: true);
  final db = await openPosDatabase(factory, path); // migrations v1 → v2 automatiques
  final repo = PosRepository(db);
  final mode = await repo.businessMode();
  AppColors.apply(mode); // bonnes couleurs dès le premier écran
  runApp(PosApp(repo: repo));
}
