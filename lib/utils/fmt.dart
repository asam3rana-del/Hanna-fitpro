import 'package:intl/intl.dart';

/// Tareekh, raqam aur phone ke chhote helpers. Saari tareekhein DB mein `yyyy-MM-dd` (text) hain —
/// is tarah sort / compare seedha string se ho jata hai aur timezone ka masla nahi aata.
class Fmt {
  Fmt._();

  static String currency = 'Rs';

  static final NumberFormat _n0 = NumberFormat('#,##0');
  static final NumberFormat _n1 = NumberFormat('#,##0.#');

  /// `Rs 12,500`
  static String money(num v) => '$currency ${_n0.format(v.round())}';

  /// 12,500 (bina currency).
  static String number(num v) => _n0.format(v.round());

  /// 72.5 / 72
  static String decimal(num v) => _n1.format(v);

  /// Aaj ki tareekh (sirf din, UTC — din ginne mein DST ka farq na aaye).
  static DateTime today() {
    final n = DateTime.now();
    return DateTime.utc(n.year, n.month, n.day);
  }

  static String todayYmd() => ymd(today());

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// `yyyy-MM-dd` -> DateTime (UTC midnight). Ghalat text => null.
  static DateTime? parseYmd(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s.trim());
    if (m == null) return null;
    return DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// `12 Nov 2026`
  static String date(String? ymdText) {
    final d = parseYmd(ymdText);
    if (d == null) return '-';
    return DateFormat('d MMM yyyy').format(d);
  }

  static String dateOf(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// `Nov 2026`
  static String monthLabel(DateTime d) => DateFormat('MMM yyyy').format(d);

  /// `7:45 PM`
  static String time(int? epochMs) {
    if (epochMs == null || epochMs <= 0) return '-';
    return DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(epochMs));
  }

  /// [months] mahine aage — mahine ka din agar chhota ho (31 Jan + 1 = 28/29 Feb) to aakhri din par rukta hai.
  static DateTime addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final y = d.year + (total >= 0 ? total ~/ 12 : ((total + 1) ~/ 12) - 1);
    final m = ((total % 12) + 12) % 12 + 1;
    final last = DateTime.utc(y, m + 1, 0).day;
    final day = d.day > last ? last : d.day;
    return DateTime.utc(y, m, day);
  }

  /// Plan ki muddat se aakhri din (shamil): 1 Jan + 1 month => 31 Jan. [unit]: day / week / month / year.
  static DateTime planEnd(DateTime start, int value, String unit) {
    final v = value < 1 ? 1 : value;
    DateTime next;
    switch (unit) {
      case 'day':
        next = start.add(Duration(days: v));
        break;
      case 'week':
        next = start.add(Duration(days: v * 7));
        break;
      case 'year':
        next = addMonths(start, v * 12);
        break;
      default:
        next = addMonths(start, v);
    }
    return next.subtract(const Duration(days: 1));
  }

  /// Aaj se [endYmd] tak kitne din baqi (aaj khatam ho rahi ho to 0, guzar chuki ho to manfi).
  static int daysLeft(String? endYmd) {
    final e = parseYmd(endYmd);
    if (e == null) return -99999;
    return e.difference(today()).inDays;
  }

  /// Pakistani number ko WhatsApp (wa.me) wale digits mein: 0300-1234567 => 923001234567.
  static String whatsAppDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0') && d.length == 11) return '92${d.substring(1)}';
    if (d.startsWith('3') && d.length == 10) return '92$d';
    return d;
  }

  /// Text ko double mein (comma / khali => 0).
  static double toDouble(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  static int toInt(String s) => int.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters1;
    return '${parts.first.characters1}${parts.last.characters1}';
  }
}

extension _FirstChar on String {
  /// Pehla huroof (UPPERCASE) — emoji / Urdu par bhi crash nahi.
  String get characters1 {
    if (isEmpty) return '';
    final r = runes.first;
    return String.fromCharCode(r).toUpperCase();
  }
}
