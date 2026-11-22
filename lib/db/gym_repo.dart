import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/session.dart';
import '../sync/device_tag.dart';
import '../utils/fmt.dart';
import 'gym_db.dart';
import 'user_repository.dart';

GymDb get _db => GymDb.instance;

/// Members ki list query mein photo (bhari) nahi — sirf `has_photo`.
const String memberCols = 'm.id, m.code, m.name, m.phone, m.cnic, m.gender, m.dob, m.address, m.emergency_name, '
    'm.emergency_phone, m.blood_group, m.joined_on, m.trainer_id, m.timing, m.goal, m.height_cm, m.notes, m.status, '
    'm.created_at, CASE WHEN m.photo IS NOT NULL AND length(m.photo) > 0 THEN 1 ELSE 0 END AS has_photo';

const String _liveMs = "ms.member_id = m.id AND ms.deleted = 0 AND ms.status != 'cancelled'";

class MemberRepo {
  MemberRepo._();

  static String _summarySql(String where) => 'SELECT $memberCols, '
      '(SELECT ms.end_date FROM memberships ms WHERE $_liveMs ORDER BY ms.end_date DESC LIMIT 1) AS end_date, '
      '(SELECT ms.plan_name FROM memberships ms WHERE $_liveMs ORDER BY ms.end_date DESC LIMIT 1) AS plan_name, '
      '((SELECT COALESCE(SUM(ms.total), 0) FROM memberships ms WHERE $_liveMs) - '
      '(SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.member_id = m.id AND p.deleted = 0)) AS dues, '
      '(SELECT MAX(a.date) FROM attendance a WHERE a.member_id = m.id AND a.deleted = 0) AS last_visit '
      'FROM members m WHERE m.deleted = 0 $where';

  static Future<List<MemberSummary>> summaries() async {
    final r = await _db.rows('${_summarySql('')} ORDER BY m.name COLLATE NOCASE');
    return r.map(MemberSummary.fromMap).toList();
  }

  static Future<MemberSummary?> summary(String id) async {
    final r = await _db.rows(_summarySql('AND m.id = ?'), [id]);
    return r.isEmpty ? null : MemberSummary.fromMap(r.first);
  }

  /// Code (poora ya number), naam ya phone se dhoondo — check-in / scanner ke liye.
  static Future<List<MemberSummary>> search(String text, {int limit = 30}) async {
    final t = text.trim();
    if (t.isEmpty) return [];
    final like = '%$t%';
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    // "12" likha => GM-0012 bhi mile (code ka number hissa).
    final codeTail = digits.isEmpty ? t : (digits.length < 4 ? digits.padLeft(4, '0') : digits);
    final r = await _db.rows(
      '${_summarySql('AND (m.code = ? COLLATE NOCASE OR m.code LIKE ? OR m.name LIKE ? OR m.phone LIKE ? OR m.cnic LIKE ?)')} '
      'ORDER BY CASE WHEN m.code = ? COLLATE NOCASE THEN 0 ELSE 1 END, m.name COLLATE NOCASE LIMIT $limit',
      [t, '%-$codeTail', like, digits.isEmpty ? like : '%$digits%', like, t],
    );
    return r.map(MemberSummary.fromMap).toList();
  }

  static Future<Member?> get(String id) async {
    final r = await _db.byId('members', id);
    return r == null ? null : Member.fromMap(r);
  }

  /// Base64 JPEG (ya null).
  static Future<String?> photo(String id) async {
    final r = await _db.rows('SELECT photo FROM members WHERE id = ?', [id]);
    if (r.isEmpty) return null;
    final v = r.first['photo'];
    return (v == null || '$v'.isEmpty) ? null : '$v';
  }

  static Future<void> setPhoto(String id, String? base64Jpeg) =>
      _db.update('members', id, {'photo': base64Jpeg ?? ''});

  /// Agla member code: GM-0001, GM-0002 ...
  static Future<String> nextCode() async {
    final prefix = GymSettings.memberPrefix;
    final r = await _db.rows('SELECT code FROM members WHERE code LIKE ?', ['$prefix-%']);
    var maxN = 0;
    for (final row in r) {
      final c = mStr(row, 'code');
      final n = int.tryParse(c.substring(c.lastIndexOf('-') + 1)) ?? 0;
      if (n > maxN) maxN = n;
    }
    return '$prefix-${(maxN + 1).toString().padLeft(4, '0')}';
  }

  static Future<bool> codeTaken(String code, {String? exceptId}) async {
    final n = await _db.count(
      'SELECT COUNT(*) FROM members WHERE deleted = 0 AND code = ? COLLATE NOCASE AND id != ?',
      [code.trim(), exceptId ?? ''],
    );
    return n > 0;
  }

  static Future<String> create(Member m, {String? photo}) async {
    final map = m.toMap();
    if (photo != null) map['photo'] = photo;
    return _db.insert('members', map);
  }

  static Future<void> save(Member m) => _db.update('members', m.id, m.toMap());

  /// Member + us ki saari memberships / payments / attendance / measurements (soft delete).
  static Future<void> delete(String id) async {
    for (final t in ['memberships', 'payments', 'attendance', 'measurements']) {
      final r = await _db.rows('SELECT id FROM $t WHERE member_id = ? AND deleted = 0', [id]);
      for (final row in r) {
        await _db.softDelete(t, mStr(row, 'id'));
      }
    }
    await _db.softDelete('members', id);
  }
}

class PlanRepo {
  PlanRepo._();

  static Future<List<Plan>> all({bool activeOnly = false}) async {
    final r = await _db.rows(
      'SELECT * FROM plans WHERE deleted = 0 ${activeOnly ? 'AND active = 1' : ''} '
      'ORDER BY sort, duration_unit, duration_value, name COLLATE NOCASE',
    );
    return r.map(Plan.fromMap).toList();
  }

  static Future<String> create(Plan p) => _db.insert('plans', p.toMap());
  static Future<void> save(Plan p) => _db.update('plans', p.id, p.toMap());
  static Future<void> delete(String id) => _db.softDelete('plans', id);

  /// Pehli dafa: aam Pakistani gym packages (baad mein badal sakte hain).
  static Future<void> seedDefaults() async {
    if (await _db.count('SELECT COUNT(*) FROM plans') > 0) return;
    final defaults = <Plan>[
      const Plan(id: '', name: 'Monthly', durationValue: 1, durationUnit: 'month', price: 3000, sort: 1),
      const Plan(id: '', name: 'Quarterly (3 Months)', durationValue: 3, durationUnit: 'month', price: 8000, sort: 2),
      const Plan(id: '', name: 'Half Year (6 Months)', durationValue: 6, durationUnit: 'month', price: 15000, sort: 3),
      const Plan(id: '', name: 'Yearly', durationValue: 1, durationUnit: 'year', price: 28000, sort: 4),
      const Plan(
          id: '', name: 'Personal Training (Monthly)', kind: 'pt', durationValue: 1, durationUnit: 'month', price: 10000, sort: 5),
      const Plan(id: '', name: 'Day Pass', durationValue: 1, durationUnit: 'day', price: 300, sort: 6),
    ];
    for (final p in defaults) {
      await create(p);
    }
  }
}

class MembershipRepo {
  MembershipRepo._();

  static Future<List<Membership>> forMember(String memberId) async {
    final r = await _db.rows(
      'SELECT * FROM memberships WHERE member_id = ? AND deleted = 0 ORDER BY end_date DESC, created_at DESC',
      [memberId],
    );
    return r.map(Membership.fromMap).toList();
  }

  static Future<Membership?> get(String id) async {
    final r = await _db.byId('memberships', id);
    return r == null ? null : Membership.fromMap(r);
  }

  /// Nayi / renew membership. Wapas: membership id.
  static Future<String> create({
    required String memberId,
    Plan? plan,
    required String planName,
    required String kind,
    String? trainerId,
    required DateTime start,
    required DateTime end,
    required double price,
    double admissionFee = 0,
    double discount = 0,
    String note = '',
  }) {
    final total = (price + admissionFee - discount).clamp(0, double.infinity).toDouble();
    return _db.insert('memberships', {
      'member_id': memberId,
      'plan_id': plan?.id,
      'plan_name': planName,
      'kind': kind,
      'trainer_id': trainerId,
      'start_date': Fmt.ymd(start),
      'end_date': Fmt.ymd(end),
      'price': price,
      'admission_fee': admissionFee,
      'discount': discount,
      'total': total,
      'frozen_days': 0,
      'note': note,
      'status': 'active',
    });
  }

  /// Freeze / extend: aakhri tareekh [days] aage (member chhutti par tha, ya bonus din).
  static Future<void> extend(Membership m, int days, {String reason = ''}) async {
    final end = Fmt.parseYmd(m.endDate) ?? Fmt.today();
    final newEnd = end.add(Duration(days: days));
    final note = [m.note, if (reason.trim().isNotEmpty) 'Extended $days d: ${reason.trim()}']
        .where((e) => e.trim().isNotEmpty)
        .join(' | ');
    await _db.update('memberships', m.id, {
      'end_date': Fmt.ymd(newEnd),
      'frozen_days': m.frozenDays + days,
      'note': note,
    });
  }

  /// Cancel: bill (total) hisaab se nikal jata hai; payments wahi rehti hain.
  static Future<void> cancel(String id) => _db.update('memberships', id, {'status': 'cancelled'});

  static Future<void> delete(String id) => _db.softDelete('memberships', id);
}

class PaymentRepo {
  PaymentRepo._();

  static const _join = 'SELECT p.*, m.name AS member_name, m.code AS member_code FROM payments p '
      'LEFT JOIN members m ON m.id = p.member_id WHERE p.deleted = 0';

  /// Har device ka apna silsila: R-7F3A-0001 (do devices ke number kabhi nahi takrate).
  static Future<String> nextReceiptNo() async {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt('receipt_seq') ?? 0) + 1;
    await prefs.setInt('receipt_seq', n);
    return 'R-${DeviceTag.current}-${n.toString().padLeft(4, '0')}';
  }

  static Future<Payment> create({
    required String memberId,
    String? membershipId,
    required double amount,
    required String method,
    DateTime? date,
    String note = '',
  }) async {
    final receipt = await nextReceiptNo();
    final paidOn = Fmt.ymd(date ?? Fmt.today());
    final id = await _db.insert('payments', {
      'member_id': memberId,
      'membership_id': membershipId,
      'amount': amount,
      'method': method,
      'paid_on': paidOn,
      'receipt_no': receipt,
      'note': note,
      'received_by': Session.displayName.isEmpty ? (Session.username ?? '') : Session.displayName,
    });
    final p = await get(id);
    return p!;
  }

  static Future<Payment?> get(String id) async {
    final r = await _db.rows('$_join AND p.id = ?', [id]);
    return r.isEmpty ? null : Payment.fromMap(r.first);
  }

  static Future<List<Payment>> forMember(String memberId) async {
    final r = await _db.rows('$_join AND p.member_id = ? ORDER BY p.paid_on DESC, p.created_at DESC', [memberId]);
    return r.map(Payment.fromMap).toList();
  }

  static Future<List<Payment>> between(String fromYmd, String toYmd) async {
    final r = await _db.rows(
      '$_join AND p.paid_on >= ? AND p.paid_on <= ? ORDER BY p.paid_on DESC, p.created_at DESC',
      [fromYmd, toYmd],
    );
    return r.map(Payment.fromMap).toList();
  }

  static Future<double> total(String fromYmd, String toYmd) =>
      _db.sum('SELECT COALESCE(SUM(amount), 0) FROM payments WHERE deleted = 0 AND paid_on >= ? AND paid_on <= ?',
          [fromYmd, toYmd]);

  static Future<void> delete(String id) => _db.softDelete('payments', id);

  /// Member ka kul baqaya (bill - payments).
  static Future<double> duesOf(String memberId) async {
    final billed = await _db.sum(
      "SELECT COALESCE(SUM(total), 0) FROM memberships WHERE member_id = ? AND deleted = 0 AND status != 'cancelled'",
      [memberId],
    );
    final paid = await _db.sum('SELECT COALESCE(SUM(amount), 0) FROM payments WHERE member_id = ? AND deleted = 0',
        [memberId]);
    return billed - paid;
  }
}

class AttendanceRepo {
  AttendanceRepo._();

  static const _join = 'SELECT a.*, m.name AS member_name, m.code AS member_code, '
      'CASE WHEN m.photo IS NOT NULL AND length(m.photo) > 0 THEN 1 ELSE 0 END AS has_photo '
      'FROM attendance a LEFT JOIN members m ON m.id = a.member_id WHERE a.deleted = 0';

  static Future<Attendance?> todayFor(String memberId) async {
    final r = await _db.rows('$_join AND a.member_id = ? AND a.date = ? ORDER BY a.check_in DESC LIMIT 1',
        [memberId, Fmt.todayYmd()]);
    return r.isEmpty ? null : Attendance.fromMap(r.first);
  }

  /// Aaj pehli dafa = check-in. Andar hai = check-out. Wapas: true => check-in hua, false => check-out.
  static Future<bool> toggle(String memberId) async {
    final t = await todayFor(memberId);
    if (t != null && t.checkOut == null) {
      await _db.update('attendance', t.id, {'check_out': GymDb.nowMs()});
      return false;
    }
    await _db.insert('attendance', {
      'member_id': memberId,
      'date': Fmt.todayYmd(),
      'check_in': GymDb.nowMs(),
      'check_out': null,
      'by_user': Session.username ?? '',
    });
    return true;
  }

  static Future<List<Attendance>> onDate(String ymd) async {
    final r = await _db.rows('$_join AND a.date = ? ORDER BY a.check_in DESC', [ymd]);
    return r.map(Attendance.fromMap).toList();
  }

  static Future<List<Attendance>> forMember(String memberId, {int limit = 120}) async {
    final r = await _db.rows('$_join AND a.member_id = ? ORDER BY a.date DESC, a.check_in DESC LIMIT $limit', [memberId]);
    return r.map(Attendance.fromMap).toList();
  }

  static Future<int> countOn(String ymd) =>
      _db.count('SELECT COUNT(DISTINCT member_id) FROM attendance WHERE deleted = 0 AND date = ?', [ymd]);

  static Future<void> delete(String id) => _db.softDelete('attendance', id);
}

class TrainerRepo {
  TrainerRepo._();

  static Future<List<Trainer>> all({bool activeOnly = false}) async {
    final r = await _db.rows(
      'SELECT t.*, (SELECT COUNT(*) FROM members m WHERE m.trainer_id = t.id AND m.deleted = 0) AS member_count '
      'FROM trainers t WHERE t.deleted = 0 ${activeOnly ? 'AND t.active = 1' : ''} ORDER BY t.name COLLATE NOCASE',
    );
    return r.map(Trainer.fromMap).toList();
  }

  static Future<String> create(Trainer t) => _db.insert('trainers', t.toMap());
  static Future<void> save(Trainer t) => _db.update('trainers', t.id, t.toMap());
  static Future<void> delete(String id) => _db.softDelete('trainers', id);

  /// Is mahine trainer ke PT memberships ka kul (commission ke liye).
  static Future<double> ptRevenue(String trainerId, String fromYmd, String toYmd) => _db.sum(
        "SELECT COALESCE(SUM(total), 0) FROM memberships WHERE deleted = 0 AND status != 'cancelled' "
        'AND trainer_id = ? AND start_date >= ? AND start_date <= ?',
        [trainerId, fromYmd, toYmd],
      );
}

class ExpenseRepo {
  ExpenseRepo._();

  static const categories = <String>[
    'Rent',
    'Electricity',
    'Gas / Water',
    'Salaries',
    'Trainer Commission',
    'Equipment',
    'Maintenance',
    'Cleaning',
    'Marketing',
    'Internet / Phone',
    'Supplements',
    'Other',
  ];

  static Future<List<Expense>> between(String fromYmd, String toYmd) async {
    final r = await _db.rows(
      'SELECT * FROM expenses WHERE deleted = 0 AND date >= ? AND date <= ? ORDER BY date DESC, created_at DESC',
      [fromYmd, toYmd],
    );
    return r.map(Expense.fromMap).toList();
  }

  static Future<double> total(String fromYmd, String toYmd) => _db.sum(
      'SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE deleted = 0 AND date >= ? AND date <= ?',
      [fromYmd, toYmd]);

  static Future<String> create(Expense e) => _db.insert('expenses', e.toMap());
  static Future<void> save(Expense e) => _db.update('expenses', e.id, e.toMap());
  static Future<void> delete(String id) => _db.softDelete('expenses', id);
}

class MeasurementRepo {
  MeasurementRepo._();

  static Future<List<Measurement>> forMember(String memberId) async {
    final r = await _db.rows(
        'SELECT * FROM measurements WHERE member_id = ? AND deleted = 0 ORDER BY date DESC, created_at DESC', [memberId]);
    return r.map(Measurement.fromMap).toList();
  }

  static Future<String> create(Measurement m) => _db.insert('measurements', m.toMap());
  static Future<void> delete(String id) => _db.softDelete('measurements', id);
}

/// Dashboard ke numbers.
class DashboardStats {
  final int totalMembers;
  final int active;
  final int expiring;
  final int expired;
  final int todayCheckins;
  final double todayCollection;
  final double monthCollection;
  final double monthExpenses;
  final double totalDues;
  final int newThisMonth;
  final List<MemberSummary> expiringList;
  final List<MemberSummary> duesList;
  final List<Attendance> todayVisits;

  const DashboardStats({
    required this.totalMembers,
    required this.active,
    required this.expiring,
    required this.expired,
    required this.todayCheckins,
    required this.todayCollection,
    required this.monthCollection,
    required this.monthExpenses,
    required this.totalDues,
    required this.newThisMonth,
    required this.expiringList,
    required this.duesList,
    required this.todayVisits,
  });

  static Future<DashboardStats> load() async {
    final today = Fmt.today();
    final todayYmd = Fmt.ymd(today);
    final monthStart = Fmt.ymd(DateTime.utc(today.year, today.month, 1));
    final monthEnd = Fmt.ymd(DateTime.utc(today.year, today.month + 1, 0));
    final rd = GymSettings.reminderDays;

    final all = await MemberRepo.summaries();
    var active = 0, expiring = 0, expired = 0, newThisMonth = 0;
    var dues = 0.0;
    final expList = <MemberSummary>[];
    final duesList = <MemberSummary>[];
    for (final s in all) {
      final st = s.stateFor(rd);
      if (st == MemberState.active) active++;
      if (st == MemberState.expiring) {
        active++;
        expiring++;
        expList.add(s);
      }
      if (st == MemberState.expired) expired++;
      if (s.dues > 0.5) {
        dues += s.dues;
        duesList.add(s);
      }
      final j = s.member.joinedOn ?? '';
      if (j.compareTo(monthStart) >= 0 && j.compareTo(monthEnd) <= 0) newThisMonth++;
    }
    expList.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    duesList.sort((a, b) => b.dues.compareTo(a.dues));

    final visits = await AttendanceRepo.onDate(todayYmd);
    final visitors = visits.map((e) => e.memberId).toSet().length;

    return DashboardStats(
      totalMembers: all.where((e) => e.member.status != 'inactive').length,
      active: active,
      expiring: expiring,
      expired: expired,
      todayCheckins: visitors,
      todayCollection: await PaymentRepo.total(todayYmd, todayYmd),
      monthCollection: await PaymentRepo.total(monthStart, monthEnd),
      monthExpenses: await ExpenseRepo.total(monthStart, monthEnd),
      totalDues: dues,
      newThisMonth: newThisMonth,
      expiringList: expList,
      duesList: duesList,
      todayVisits: visits,
    );
  }
}

/// Mahine ki report.
class MonthReport {
  final DateTime month;
  final double revenue;
  final double expenses;
  final int newMembers;
  final int renewals;
  final int visits;
  final int uniqueVisitors;
  final Map<String, double> byMethod;
  final Map<String, double> byCategory;
  final Map<String, double> byPlan;

  /// Pichhle 6 mahine (purana pehle): (mahina, aamdani, kharcha).
  final List<(DateTime, double, double)> trend;

  const MonthReport({
    required this.month,
    required this.revenue,
    required this.expenses,
    required this.newMembers,
    required this.renewals,
    required this.visits,
    required this.uniqueVisitors,
    required this.byMethod,
    required this.byCategory,
    required this.byPlan,
    required this.trend,
  });

  double get profit => revenue - expenses;

  static Future<MonthReport> load(DateTime month) async {
    final from = Fmt.ymd(DateTime.utc(month.year, month.month, 1));
    final to = Fmt.ymd(DateTime.utc(month.year, month.month + 1, 0));

    Future<Map<String, double>> grouped(String sql) async {
      final r = await _db.rows(sql, [from, to]);
      final out = <String, double>{};
      for (final row in r) {
        final k = mStr(row, 'k').isEmpty ? 'Other' : mStr(row, 'k');
        out[k] = (out[k] ?? 0) + mDbl(row, 'v');
      }
      return out;
    }

    final trend = <(DateTime, double, double)>[];
    for (var i = 5; i >= 0; i--) {
      final m = Fmt.addMonths(DateTime.utc(month.year, month.month, 1), -i);
      final f = Fmt.ymd(m);
      final t = Fmt.ymd(DateTime.utc(m.year, m.month + 1, 0));
      trend.add((m, await PaymentRepo.total(f, t), await ExpenseRepo.total(f, t)));
    }

    return MonthReport(
      month: DateTime.utc(month.year, month.month, 1),
      revenue: await PaymentRepo.total(from, to),
      expenses: await ExpenseRepo.total(from, to),
      newMembers: await _db.count(
          'SELECT COUNT(*) FROM members WHERE deleted = 0 AND joined_on >= ? AND joined_on <= ?', [from, to]),
      renewals: await _db.count(
          "SELECT COUNT(*) FROM memberships WHERE deleted = 0 AND status != 'cancelled' AND start_date >= ? AND start_date <= ?",
          [from, to]),
      visits: await _db.count('SELECT COUNT(*) FROM attendance WHERE deleted = 0 AND date >= ? AND date <= ?', [from, to]),
      uniqueVisitors: await _db.count(
          'SELECT COUNT(DISTINCT member_id) FROM attendance WHERE deleted = 0 AND date >= ? AND date <= ?', [from, to]),
      byMethod: await grouped(
          'SELECT method AS k, SUM(amount) AS v FROM payments WHERE deleted = 0 AND paid_on >= ? AND paid_on <= ? GROUP BY method'),
      byCategory: await grouped(
          'SELECT category AS k, SUM(amount) AS v FROM expenses WHERE deleted = 0 AND date >= ? AND date <= ? GROUP BY category'),
      byPlan: await grouped("SELECT plan_name AS k, SUM(total) AS v FROM memberships WHERE deleted = 0 "
          "AND status != 'cancelled' AND start_date >= ? AND start_date <= ? GROUP BY plan_name"),
      trend: trend,
    );
  }
}
