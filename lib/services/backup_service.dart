import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/gym_db.dart';
import '../db/user_repository.dart';
import '../sync/gym_sync.dart';
import 'photo_service.dart';

/// Backup / Restore + roz ka khud-kaar (auto) backup (aakhri 7 din device par).
class BackupService {
  BackupService._();

  static bool get _desktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
  }

  /// DB ki taaza copy (WAL ka data bhi file mein aa jaye).
  static Future<File> _snapshot(String targetPath) async {
    final db = await GymDb.instance.database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
    final src = File(await GymDb.instance.path);
    return src.copy(targetPath);
  }

  /// Backup file bana kar share (phone) ya "Save as" (PC). Wapas: user ke liye message.
  static Future<String> exportBackup() async {
    final name = 'HannaFitness-backup-${_stamp()}.hfbackup';
    if (_desktop) {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Save backup', fileName: name);
      if (path == null || path.isEmpty) return 'Cancelled';
      await _snapshot(path);
      return 'Backup saved: $path';
    }
    final tmp = await getTemporaryDirectory();
    final f = await _snapshot(p.join(tmp.path, name));
    await Share.shareXFiles([XFile(f.path)], subject: 'Hanna Fitness backup ${_stamp()}');
    return 'Backup ready — save it to Google Drive / WhatsApp / USB';
  }

  /// File chun kar poora data us backup se badal do. Wapas: message (null = cancel).
  static Future<String?> restoreBackup() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    final path = res?.files.single.path;
    if (path == null) return null;
    final file = File(path);
    if (!await _looksValid(file)) {
      return 'This file is not a Hanna Fitness backup';
    }
    // Pehle maujooda data ki hifazati copy.
    try {
      final dir = await _autoDir();
      await _snapshot(p.join(dir.path, 'before-restore-${_stamp()}.hfbackup'));
    } catch (_) {}
    await GymDb.instance.close();
    await file.copy(await GymDb.instance.path);
    // Kisi purane WAL / journal ka asar na rahe.
    for (final ext in ['-wal', '-shm', '-journal']) {
      final f = File('${await GymDb.instance.path}$ext');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    await GymDb.instance.database; // dobara kholo
    await GymSettings.load();
    PhotoService.clearAll();
    await GymSync.resetMarkers();
    GymDb.instance.notifyChanged();
    return 'Restore complete ✓';
  }

  static Future<bool> _looksValid(File f) async {
    try {
      final raf = await f.open();
      final head = await raf.read(16);
      await raf.close();
      if (String.fromCharCodes(head.take(15)) != 'SQLite format 3') return false;
      final db = await openDatabase(f.path, readOnly: true, singleInstance: false);
      try {
        final r = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'members'");
        return r.isNotEmpty;
      } finally {
        await db.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<Directory> _autoDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'auto_backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// App khulne par din mein ek dafa. Aakhri 7 rakhta hai.
  static Future<void> autoBackupIfDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString('auto_backup_day') == today) return;
      final dir = await _autoDir();
      await _snapshot(p.join(dir.path, 'auto-$today.hfbackup'));
      await prefs.setString('auto_backup_day', today);
      final files = dir.listSync().whereType<File>().where((f) => p.basename(f.path).startsWith('auto-')).toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(7)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Device par rakhe auto backups (naya pehle).
  static Future<List<File>> autoBackups() async {
    try {
      final dir = await _autoDir();
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.hfbackup')).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// Auto backup ko share / save (agar phone hi badal raha ho).
  static Future<void> shareFile(File f) async {
    if (_desktop) {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Save backup', fileName: p.basename(f.path));
      if (path != null && path.isNotEmpty) await f.copy(path);
      return;
    }
    await Share.shareXFiles([XFile(f.path)], subject: 'Hanna Fitness backup');
  }

  /// Text (CSV) file share / save.
  static Future<String> shareText(String fileName, String content) async {
    if (_desktop) {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Save file', fileName: fileName);
      if (path == null || path.isEmpty) return 'Cancelled';
      await File(path).writeAsString(content);
      return 'Saved: $path';
    }
    final tmp = await getTemporaryDirectory();
    final f = File(p.join(tmp.path, fileName));
    await f.writeAsString(content);
    await Share.shareXFiles([XFile(f.path)], subject: fileName);
    return 'Ready to share';
  }
}
