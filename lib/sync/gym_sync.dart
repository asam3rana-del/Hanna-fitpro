import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sql;

import '../db/gym_db.dart';
import '../db/user_repository.dart';
import '../utils/loc.dart';
import 'cloud_config_store.dart';

/// Sync ki haalat (Settings > Cloud Sync aur header ka chhota sa nishan).
@immutable
class SyncStatus {
  final bool running;
  final bool ok;
  final String message;
  final int lastOkMs;

  const SyncStatus({this.running = false, this.ok = true, this.message = '', this.lastOkMs = 0});

  SyncStatus copyWith({bool? running, bool? ok, String? message, int? lastOkMs}) => SyncStatus(
        running: running ?? this.running,
        ok: ok ?? this.ok,
        message: message ?? this.message,
        lastOkMs: lastOkMs ?? this.lastOkMs,
      );
}

/// Online sync — mobile aur PC, ek gym ke kai devices.
///
/// Firestore mein: `gyms/<GYM-CODE>/<table>/<row id>`. Har row ke saath `server_at` (server ka waqt):
///  * PUSH: `dirty = 1` wali rows (400 ki batch) upar; kamyabi par `dirty = 0`.
///  * PULL: har table se sirf wo docs jin ka `server_at` pichhli pull ke baad ka hai (device ki ghari
///    ghalat ho tab bhi kuch miss nahi hota). Takrao: jis ka `updated_at` naya, wahi jeetta hai.
///  * Delete: row `deleted = 1` ke saath jati hai — doosre devices par bhi chhup jati hai.
/// Internet na ho to app poori tarah offline chalti hai; net aate hi sab khud sync.
class GymSync {
  GymSync._();
  static final GymSync instance = GymSync._();

  static const _kCode = 'sync_gym_code';
  static const _kLastOk = 'sync_last_ok';
  static const _pushBatch = 400;
  static const _pullPage = 300;

  final ValueNotifier<SyncStatus> status = ValueNotifier<SyncStatus>(const SyncStatus());

  bool _running = false;
  bool _again = false;
  Timer? _debounce;
  Timer? _periodic;

  // ---------------- config ----------------

  /// Gym code = cloud par is gym ka folder. Har device par BILKUL ek jaisa likhein.
  static Future<String> gymCode() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_kCode) ?? '').trim();
  }

  static String cleanCode(String raw) => raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_-]'), '');

  static Future<void> setGymCode(String code) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCode, cleanCode(code));
  }

  static Future<bool> isConfigured() async =>
      (await gymCode()).isNotEmpty && await CloudConfigStore.isConfigured();

  // ---------------- triggers ----------------

  /// main() se: har 3 minute, local tabdeeli ke 6 second baad, aur internet wapas aane par.
  Future<void> start() async {
    final p = await SharedPreferences.getInstance();
    status.value = status.value.copyWith(lastOkMs: p.getInt(_kLastOk) ?? 0);
    GymDb.onLocalWrite = schedule;
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 3), (_) => syncNow());
    Timer(const Duration(seconds: 4), () => syncNow());
  }

  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 6), () => syncNow());
  }

  // ---------------- sync ----------------

  /// Wapas: user ke liye ek line ka natija.
  Future<String> syncNow() async {
    if (_running) {
      _again = true;
      return Loc.t('Sync already running…', 'سنک پہلے سے چل رہا ہے…');
    }
    final code = await gymCode();
    if (code.isEmpty || !await CloudConfigStore.isConfigured()) {
      final m = Loc.t('Cloud sync is not set up (works offline)', 'کلاؤڈ سنک سیٹ نہیں (آف لائن چل رہا ہے)');
      status.value = status.value.copyWith(running: false, ok: true, message: m);
      return m;
    }
    try {
      final c = await Connectivity().checkConnectivity();
      if (c.every((e) => e == ConnectivityResult.none)) {
        final m = Loc.t('Offline — will sync when internet is back', 'آف لائن — انٹرنیٹ آنے پر سنک ہو گا');
        status.value = status.value.copyWith(running: false, ok: true, message: m);
        return m;
      }
    } catch (_) {}

    _running = true;
    status.value = status.value.copyWith(running: true, message: Loc.t('Syncing…', 'سنک ہو رہا ہے…'));
    try {
      final app = await CloudConfigStore.firebaseApp();
      if (app == null) throw StateError('Firebase project not set');
      final auth = FirebaseAuth.instanceFor(app: app);
      if (auth.currentUser == null) {
        await auth.signInAnonymously().timeout(const Duration(seconds: 25));
      }
      final fs = FirebaseFirestore.instanceFor(app: app);
      final root = fs.collection('gyms').doc(code);

      var pushed = 0;
      for (final t in GymDb.syncTables) {
        pushed += await _push(root, t);
      }
      var pulled = 0;
      for (final t in GymDb.syncTables) {
        pulled += await _pull(root, code, t);
      }
      if (pulled > 0) {
        await GymSettings.load();
        GymDb.instance.notifyChanged(local: false);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kLastOk, now);
      final m = Loc.t('Synced ✓  (sent $pushed, received $pulled)', 'سنک مکمل ✓  (بھیجے $pushed، ملے $pulled)');
      status.value = SyncStatus(running: false, ok: true, message: m, lastOkMs: now);
      return m;
    } catch (e) {
      final m = _explain(e);
      status.value = status.value.copyWith(running: false, ok: false, message: m);
      return m;
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        schedule();
      }
    }
  }

  String _explain(Object e) {
    final code = e is FirebaseException ? e.code : '';
    if (code == 'permission-denied') {
      return Loc.t('Cloud refused (permission denied) — publish the Firestore rules from firebase/firestore.rules.',
          'کلاؤڈ نے انکار کیا — firebase/firestore.rules والے Rules شائع کریں۔');
    }
    if (code == 'operation-not-allowed' || code == 'admin-restricted-operation') {
      return Loc.t('Turn ON Anonymous sign-in in Firebase Console > Authentication.',
          'Firebase Console > Authentication میں Anonymous سائن اِن آن کریں۔');
    }
    if (e is TimeoutException || code == 'unavailable' || code == 'network-request-failed') {
      return Loc.t('Internet too slow — will retry automatically.', 'انٹرنیٹ سست ہے — خود دوبارہ کوشش ہو گی۔');
    }
    return Loc.t('Sync failed: $e', 'سنک ناکام: $e');
  }

  Future<int> _push(DocumentReference<Map<String, dynamic>> root, String table) async {
    final db = await GymDb.instance.database;
    var total = 0;
    for (var round = 0; round < 100; round++) {
      final rows = await db.query(table, where: 'dirty = 1', limit: _pushBatch);
      if (rows.isEmpty) break;
      final batch = root.firestore.batch();
      final sent = <Map<String, Object?>>[];
      for (final r in rows) {
        final id = (r['id'] ?? '').toString();
        if (id.isEmpty) continue;
        if (table == 'settings' && localOnlySettings.contains(id)) {
          await db.update(table, {'dirty': 0}, where: 'id = ?', whereArgs: [id]);
          continue;
        }
        final data = <String, dynamic>{};
        r.forEach((k, v) {
          if (k != 'dirty') data[k] = v;
        });
        data['server_at'] = FieldValue.serverTimestamp();
        batch.set(root.collection(table).doc(id), data);
        sent.add(r);
      }
      if (sent.isNotEmpty) {
        await batch.commit().timeout(const Duration(seconds: 90));
        for (final r in sent) {
          // Push ke dauran dobara badli ho to dirty rehne do (agli baar phir jayegi).
          await db.update(table, {'dirty': 0},
              where: 'id = ? AND updated_at = ?', whereArgs: [r['id'], r['updated_at']]);
        }
      }
      total += sent.length;
      if (rows.length < _pushBatch) break;
    }
    return total;
  }

  Future<int> _pull(DocumentReference<Map<String, dynamic>> root, String code, String table) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'sync_pull_${code}_$table';
    var since = prefs.getInt(key) ?? 0; // microseconds (server waqt)
    final cols = await GymDb.instance.columnsOf(table);
    final db = await GymDb.instance.database;
    var applied = 0;
    for (var round = 0; round < 200; round++) {
      final after = Timestamp(since ~/ 1000000, (since % 1000000) * 1000);
      final snap = await root
          .collection(table)
          .where('server_at', isGreaterThan: after)
          .orderBy('server_at')
          .limit(_pullPage)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 90));
      if (snap.docs.isEmpty) break;
      var maxSeen = since;
      await db.transaction((txn) async {
        for (final d in snap.docs) {
          final data = d.data();
          final ts = data['server_at'];
          if (ts is Timestamp) {
            final micros = ts.seconds * 1000000 + ts.nanoseconds ~/ 1000;
            if (micros > maxSeen) maxSeen = micros;
          }
          if (await _apply(txn, table, d.id, data, cols)) applied++;
        }
      });
      if (maxSeen <= since) break;
      since = maxSeen;
      await prefs.setInt(key, since);
      if (snap.docs.length < _pullPage) break;
    }
    return applied;
  }

  /// Ek cloud doc local table mein (sirf jab woh local se naya ho). true = laga diya.
  Future<bool> _apply(
    sql.DatabaseExecutor txn,
    String table,
    String id,
    Map<String, dynamic> data,
    Set<String> cols,
  ) async {
    if (table == 'settings' && localOnlySettings.contains(id)) return false;
    final remoteUpdated = _asInt(data['updated_at']);
    final local = await txn.query(table, columns: ['updated_at'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (local.isNotEmpty && _asInt(local.first['updated_at']) >= remoteUpdated) return false;
    final row = <String, Object?>{};
    data.forEach((k, v) {
      if (cols.contains(k) && k != 'dirty') row[k] = _toSql(v);
    });
    row['id'] = id;
    row['dirty'] = 0;
    if (local.isEmpty) {
      await txn.insert(table, row, conflictAlgorithm: sql.ConflictAlgorithm.replace);
    } else {
      await txn.update(table, row, where: 'id = ?', whereArgs: [id]);
    }
    return true;
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  static Object? _toSql(Object? v) {
    if (v == null || v is num || v is String) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    return v.toString();
  }

  /// Gym code badalne / naye gym se jurne par: is device ka sab data dobara upar bhejo aur neeche se sab lo.
  static Future<void> resetMarkers() async {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().toList()) {
      if (k.startsWith('sync_pull_')) await p.remove(k);
    }
    final db = await GymDb.instance.database;
    for (final t in GymDb.syncTables) {
      await db.update(t, {'dirty': 1});
    }
  }
}
