import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

bool get cameraPhotoSupported => Platform.isAndroid || Platform.isIOS;

/// Choisit une photo (galerie, fichier sous Windows, ou appareil photo), la
/// réduit et la copie dans le dossier de l'application. Renvoie `file:<chemin>`.
Future<String?> pickProductPhoto({bool camera = false}) async {
  final picked = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 82);
  if (picked == null) return null;
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'product_photos'));
  await dir.create(recursive: true);
  final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
  final target = p.join(dir.path, '${const Uuid().v4()}$ext');
  await File(picked.path).copy(target);
  return 'file:$target';
}
