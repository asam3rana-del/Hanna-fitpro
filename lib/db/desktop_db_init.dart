import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Windows / Linux par sqflite ki jagah FFI SQLite. Android / iOS par kuch nahi karta.
///
/// DB user ke AppData mein: `%APPDATA%\Hanna Solutions\Hanna Fitness\databases` (Windows par
/// `<company>\<app>` exe ke Runner.rc se aata hai — CI isay "Hanna Solutions" / "Hanna Fitness" likhta hai.
/// KABHI na badlein, warna data "gum" lagega).
Future<void> initDesktopDatabase() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'databases'));
  if (!await dir.exists()) await dir.create(recursive: true);
  await databaseFactory.setDatabasesPath(dir.path);
}
