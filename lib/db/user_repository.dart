import '../models/models.dart';
import '../utils/fmt.dart';
import '../utils/password_hasher.dart';
import 'gym_db.dart';

/// Settings jo sirf ISI device ke liye hain (cloud par nahi jaate).
const Set<String> localOnlySettings = {'login_method', 'last_user'};

/// Users (login) + settings table. AppLock isi ka `getSetting('login_method')` parhta hai.
class UserRepository {
  UserRepository._();
  static final UserRepository instance = UserRepository._();

  final GymDb _db = GymDb.instance;

  // ---------------- settings ----------------

  Future<String?> getSetting(String key) async {
    final r = await _db.rows('SELECT value FROM settings WHERE id = ? AND deleted = 0', [key]);
    if (r.isEmpty) return null;
    final v = r.first['value'];
    return v?.toString();
  }

  Future<void> setSetting(String key, String value) async {
    final existing = await _db.rows('SELECT id FROM settings WHERE id = ?', [key]);
    if (existing.isEmpty) {
      await _db.insert('settings', {'id': key, 'value': value});
    } else {
      await _db.update('settings', key, {'value': value, 'deleted': 0});
    }
  }

  // ---------------- users ----------------

  static String idFor(String username) => username.trim().toLowerCase();

  Future<bool> hasAnyUser() async =>
      await _db.count('SELECT COUNT(*) FROM users WHERE deleted = 0') > 0;

  Future<List<AppUser>> all() async {
    final r = await _db.rows('SELECT * FROM users WHERE deleted = 0 ORDER BY role, username COLLATE NOCASE');
    return r.map(AppUser.fromMap).toList();
  }

  Future<AppUser?> find(String username) async {
    final r = await _db.rows('SELECT * FROM users WHERE id = ? AND deleted = 0 LIMIT 1', [idFor(username)]);
    return r.isEmpty ? null : AppUser.fromMap(r.first);
  }

  /// Sahi username + password + active => user; warna null.
  Future<AppUser?> authenticate(String username, String password) async {
    final u = await find(username);
    if (u == null || !u.active) return null;
    final ok = await PasswordHasher.verify(password, u.passwordHash);
    return ok ? u : null;
  }

  Future<void> create({
    required String username,
    required String displayName,
    required String password,
    required String role,
  }) async {
    final hash = await PasswordHasher.hash(password);
    await _db.insert('users', {
      'id': idFor(username),
      'username': username.trim(),
      'display_name': displayName.trim().isEmpty ? username.trim() : displayName.trim(),
      'password_hash': hash,
      'role': role,
      'active': 1,
    });
  }

  Future<void> setPassword(String username, String password) async {
    final hash = await PasswordHasher.hash(password);
    await _db.update('users', idFor(username), {'password_hash': hash});
  }

  Future<void> setRole(String username, String role) => _db.update('users', idFor(username), {'role': role});

  Future<void> setActive(String username, bool active) =>
      _db.update('users', idFor(username), {'active': active ? 1 : 0});

  Future<void> rename(String username, String displayName) =>
      _db.update('users', idFor(username), {'display_name': displayName.trim()});

  Future<int> activeAdminCount() =>
      _db.count("SELECT COUNT(*) FROM users WHERE deleted = 0 AND active = 1 AND role = 'admin'");
}

/// Gym ki settings ka cache (startup aur sync ke baad load). Saari screens yahin se parhti hain.
class GymSettings {
  GymSettings._();

  static final Map<String, String> _cache = {};

  static Future<void> load() async {
    final r = await GymDb.instance.rows('SELECT id, value FROM settings WHERE deleted = 0');
    _cache
      ..clear()
      ..addEntries(r.map((e) => MapEntry(mStr(e, 'id'), mStr(e, 'value'))));
    Fmt.currency = currency;
  }

  static String get(String key, [String fallback = '']) {
    final v = _cache[key];
    return (v == null || v.isEmpty) ? fallback : v;
  }

  static Future<void> set(String key, String value) async {
    await UserRepository.instance.setSetting(key, value);
    _cache[key] = value;
    if (key == 'currency') Fmt.currency = currency;
  }

  static String get gymName => get('gym_name', 'My Gym');
  static String get gymPhone => get('gym_phone');
  static String get gymAddress => get('gym_address');
  static String get gymTagline => get('gym_tagline', 'Fitness  •  Strength  •  Lifestyle');
  static String get currency => get('currency', 'Rs');
  static String get receiptNote => get('receipt_note', 'Fee is non-refundable. Thank you for training with us!');
  static String get memberPrefix => get('member_prefix', 'GM');
  static int get reminderDays => int.tryParse(get('reminder_days', '5')) ?? 5;
  static double get admissionFee => double.tryParse(get('admission_fee', '0')) ?? 0;

  /// WhatsApp reminder ka template. {name} {gym} {date} {days} {dues} {plan} badal jaate hain.
  static String get reminderTemplate => get(
        'reminder_template',
        'Assalam o Alaikum {name}!\n'
            'Your {plan} membership at {gym} expires on {date}.\n'
            'Please renew to keep training without a break. 💪\n'
            '{dues}'
            '— {gym}',
      );
}
