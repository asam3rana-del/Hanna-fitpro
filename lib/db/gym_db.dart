import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Hanna Fitness ki local SQLite database.
///
/// Har sync hone wali table ke 4 sync columns hain:
///  * `id` TEXT — UUID (do devices ki IDs kabhi nahi takratein)
///  * `updated_at` — aakhri tabdeeli (ms); do devices mein takrao par nayi tabdeeli jeetti hai
///  * `deleted` — 1 = mitaya gaya (row rehti hai taake delete doosre devices tak pohnche)
///  * `dirty` — 1 = abhi cloud par nahi gayi
class GymDb {
  GymDb._();
  static final GymDb instance = GymDb._();

  static const fileName = 'hanna_fitness.db';
  static const schemaVersion = 1;

  /// Cloud ke saath sync hone wali tables (is tarteeb mein push / pull).
  static const syncTables = <String>[
    'settings',
    'users',
    'plans',
    'trainers',
    'members',
    'memberships',
    'payments',
    'attendance',
    'expenses',
    'measurements',
  ];

  /// Har likhne par barhta hai — screens isay sun kar refresh hoti hain.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Local tabdeeli ke baad (sync worker yahan jurta hai).
  static void Function()? onLocalWrite;

  static const _uuid = Uuid();
  static String newId() => _uuid.v4();

  Database? _db;
  final Map<String, Set<String>> _columns = {};

  Future<Database> get database async => _db ??= await _open();

  Future<String> get path async => join(await getDatabasesPath(), fileName);

  Future<Database> _open() async {
    final p = await path;
    return openDatabase(
      p,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: (db, version) async {
        await createSchema(db);
      },
      onUpgrade: (db, oldV, newV) async {
        // Aainda schema badle to yahan ALTER TABLE (purana data kabhi na mitayein).
        await createSchema(db);
      },
    );
  }

  /// Restore ke liye: DB band karo (file badalne se pehle), phir agla call nayi file kholega.
  Future<void> close() async {
    final d = _db;
    _db = null;
    _columns.clear();
    if (d != null) await d.close();
  }

  static const _sync = 'created_at INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER NOT NULL DEFAULT 0, '
      'deleted INTEGER NOT NULL DEFAULT 0, '
      'dirty INTEGER NOT NULL DEFAULT 1';

  /// `IF NOT EXISTS` — dobara chalana mehfooz hai.
  static Future<void> createSchema(Database db) async {
    final stmts = <String>[
      'CREATE TABLE IF NOT EXISTS settings (id TEXT PRIMARY KEY, value TEXT, $_sync)',
      'CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, username TEXT NOT NULL, display_name TEXT, '
          'password_hash TEXT, role TEXT NOT NULL DEFAULT \'reception\', active INTEGER NOT NULL DEFAULT 1, $_sync)',
      'CREATE TABLE IF NOT EXISTS plans (id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT \'gym\', '
          'duration_value INTEGER NOT NULL DEFAULT 1, duration_unit TEXT NOT NULL DEFAULT \'month\', '
          'price REAL NOT NULL DEFAULT 0, description TEXT, active INTEGER NOT NULL DEFAULT 1, '
          'sort INTEGER NOT NULL DEFAULT 0, $_sync)',
      'CREATE TABLE IF NOT EXISTS trainers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, specialty TEXT, '
          'salary REAL NOT NULL DEFAULT 0, commission_pct REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, '
          'notes TEXT, $_sync)',
      'CREATE TABLE IF NOT EXISTS members (id TEXT PRIMARY KEY, code TEXT, name TEXT NOT NULL, phone TEXT, cnic TEXT, '
          'gender TEXT, dob TEXT, address TEXT, emergency_name TEXT, emergency_phone TEXT, blood_group TEXT, '
          'joined_on TEXT, trainer_id TEXT, timing TEXT, goal TEXT, height_cm REAL, notes TEXT, photo TEXT, '
          'status TEXT NOT NULL DEFAULT \'active\', $_sync)',
      'CREATE TABLE IF NOT EXISTS memberships (id TEXT PRIMARY KEY, member_id TEXT NOT NULL, plan_id TEXT, '
          'plan_name TEXT, kind TEXT NOT NULL DEFAULT \'gym\', trainer_id TEXT, start_date TEXT NOT NULL, '
          'end_date TEXT NOT NULL, price REAL NOT NULL DEFAULT 0, admission_fee REAL NOT NULL DEFAULT 0, '
          'discount REAL NOT NULL DEFAULT 0, total REAL NOT NULL DEFAULT 0, frozen_days INTEGER NOT NULL DEFAULT 0, '
          'note TEXT, status TEXT NOT NULL DEFAULT \'active\', $_sync)',
      'CREATE TABLE IF NOT EXISTS payments (id TEXT PRIMARY KEY, member_id TEXT NOT NULL, membership_id TEXT, '
          'amount REAL NOT NULL DEFAULT 0, method TEXT, paid_on TEXT NOT NULL, receipt_no TEXT, note TEXT, '
          'received_by TEXT, $_sync)',
      'CREATE TABLE IF NOT EXISTS attendance (id TEXT PRIMARY KEY, member_id TEXT NOT NULL, date TEXT NOT NULL, '
          'check_in INTEGER, check_out INTEGER, by_user TEXT, $_sync)',
      'CREATE TABLE IF NOT EXISTS expenses (id TEXT PRIMARY KEY, category TEXT NOT NULL, amount REAL NOT NULL DEFAULT 0, '
          'date TEXT NOT NULL, note TEXT, paid_to TEXT, method TEXT, $_sync)',
      'CREATE TABLE IF NOT EXISTS measurements (id TEXT PRIMARY KEY, member_id TEXT NOT NULL, date TEXT NOT NULL, '
          'weight REAL, body_fat REAL, chest REAL, waist REAL, arms REAL, thigh REAL, note TEXT, $_sync)',
      'CREATE INDEX IF NOT EXISTS ix_ms_member ON memberships(member_id, end_date)',
      'CREATE INDEX IF NOT EXISTS ix_pay_member ON payments(member_id)',
      'CREATE INDEX IF NOT EXISTS ix_pay_date ON payments(paid_on)',
      'CREATE INDEX IF NOT EXISTS ix_att_member ON attendance(member_id, date)',
      'CREATE INDEX IF NOT EXISTS ix_att_date ON attendance(date)',
      'CREATE INDEX IF NOT EXISTS ix_exp_date ON expenses(date)',
      'CREATE INDEX IF NOT EXISTS ix_meas_member ON measurements(member_id, date)',
      'CREATE INDEX IF NOT EXISTS ix_members_code ON members(code)',
    ];
    for (final s in stmts) {
      await db.execute(s);
    }
    for (final t in syncTables) {
      await db.execute('CREATE INDEX IF NOT EXISTS ix_${t}_dirty ON $t(dirty)');
    }
  }

  /// Table ke column names (cloud se aaye anjaan fields chhorne ke liye).
  Future<Set<String>> columnsOf(String table) async {
    final cached = _columns[table];
    if (cached != null) return cached;
    final db = await database;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final set = rows.map((r) => (r['name'] ?? '').toString()).where((e) => e.isNotEmpty).toSet();
    _columns[table] = set;
    return set;
  }

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;

  void notifyChanged({bool local = true}) {
    changes.value++;
    if (local) onLocalWrite?.call();
  }

  /// Nayi row. [values] mein `id` ho to wahi (warna naya UUID). Wapas: id.
  Future<String> insert(String table, Map<String, Object?> values) async {
    final db = await database;
    final now = nowMs();
    final row = Map<String, Object?>.from(values);
    final given = row['id'];
    final id = (given is String && given.isNotEmpty) ? given : newId();
    row['id'] = id;
    row['created_at'] = now;
    row['updated_at'] = now;
    row['deleted'] = 0;
    row['dirty'] = 1;
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyChanged();
    return id;
  }

  /// Maujooda row ke kuch fields badlo.
  Future<void> update(String table, String id, Map<String, Object?> values) async {
    final db = await database;
    final row = Map<String, Object?>.from(values)
      ..remove('id')
      ..remove('created_at');
    row['updated_at'] = nowMs();
    row['dirty'] = 1;
    await db.update(table, row, where: 'id = ?', whereArgs: [id]);
    notifyChanged();
  }

  /// Delete = `deleted = 1` (row cloud par bhi "mitayi gayi" ke taur par jati hai).
  Future<void> softDelete(String table, String id) => update(table, id, {'deleted': 1});

  Future<Map<String, Object?>?> byId(String table, String id) async {
    final db = await database;
    final rows = await db.query(table, where: 'id = ? AND deleted = 0', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> rows(String sql, [List<Object?> args = const []]) async {
    final db = await database;
    return db.rawQuery(sql, args);
  }

  Future<double> sum(String sql, [List<Object?> args = const []]) async {
    final r = await rows(sql, args);
    if (r.isEmpty) return 0;
    final v = r.first.values.first;
    return v is num ? v.toDouble() : 0;
  }

  Future<int> count(String sql, [List<Object?> args = const []]) async {
    final r = await rows(sql, args);
    if (r.isEmpty) return 0;
    final v = r.first.values.first;
    return v is num ? v.toInt() : 0;
  }
}

/// Map se mehfooz parhne ke helpers (DB / cloud dono ke liye).
String mStr(Map<String, Object?> m, String k) => (m[k] ?? '').toString();
String? mStrN(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

double mDbl(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

int mInt(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

int? mIntN(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

bool mBool(Map<String, Object?> m, String k) => mInt(m, k) != 0;
