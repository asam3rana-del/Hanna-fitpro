import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/fmt.dart';

/// License ki haalat.
enum LicenseKind {
  /// Muft trial chal raha hai.
  trial,

  /// License theek hai.
  active,

  /// License 7 din ya kam mein khatam.
  expiring,

  /// License khatam — 3 din ki mohlat (app chalti hai, warning ke saath).
  grace,

  /// Trial / license khatam — app band (sirf license screen + backup).
  expired,

  /// Phone ki tareekh peeche ki gayi — app band jab tak tareekh theek na ho.
  clock,
}

@immutable
class LicenseStatus {
  final LicenseKind kind;
  final String plan; // trial / monthly / quarterly / half_yearly / yearly / lifetime
  final String gym; // license kis gym ke naam
  final String? expiry; // yyyy-MM-dd
  final int daysLeft;

  const LicenseStatus({required this.kind, this.plan = 'trial', this.gym = '', this.expiry, this.daysLeft = 0});

  bool get blocked => kind == LicenseKind.expired || kind == LicenseKind.clock;
  bool get needsAttention => kind != LicenseKind.active;
  bool get isLifetime => plan == 'lifetime';
}

/// License key ke andar ki maloomat (Hanna Solutions ke generator se signed).
@immutable
class LicensePayload {
  final String app;
  final String device; // device ID ya '*' (koi bhi device)
  final String gym;
  final String plan;
  final String expiry; // yyyy-MM-dd
  final String issued;

  const LicensePayload({
    required this.app,
    required this.device,
    required this.gym,
    required this.plan,
    required this.expiry,
    required this.issued,
  });
}

/// Offline license (internet ki zaroorat nahi).
///
/// * Har install ki apni **Device ID** (HF-XXXX-XXXX). Customer yeh Hanna Solutions ko bhejta hai.
/// * Hanna Solutions generator se key banata hai: `HF1.<payload>.<signature>` — Ed25519 se signed.
///   App mein sirf PUBLIC key hai: koi naqli key nahi bana sakta, aur key doosre phone par nahi chalti
///   (jab tak generator mein "Any device" na chuna ho).
/// * Pehli dafa [trialDays] din ka muft trial. Khatam hone ke baad [graceDays] din mohlat, phir app sirf
///   license screen par rukti hai (data mehfooz — backup wahan se bhi nikal sakte hain).
/// * Phone ki tareekh peeche karne se trial / license lamba nahi hota.
class LicenseService {
  LicenseService._();

  /// Hanna Solutions ki license PUBLIC key (private key sirf generator ke paas — app mein KABHI nahi).
  static const publicKeyB64 = 'OWkO9TJt7GArA9anuC/4lYAC7n59ot1QNOTdfPdZlUs=';
  static const appCode = 'hanna_fitness';
  static const keyPrefix = 'HF1';
  static const trialDays = 14;
  static const graceDays = 3;
  static const warnDays = 7;

  static const _kDevice = 'license_device_id';
  static const _kKey = 'license_key';
  static const _kTrial = 'license_trial_start';
  static const _kSeen = 'license_last_seen';

  static final ValueNotifier<LicenseStatus> status =
      ValueNotifier<LicenseStatus>(const LicenseStatus(kind: LicenseKind.trial, daysLeft: trialDays));

  static String deviceId = '';
  static Timer? _timer;

  /// App start par (main). Har ghante dobara hisaab (raat 12 baje ke baad bhi sahi rahe).
  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_kDevice) ?? '';
    if (id.isEmpty) {
      id = _newDeviceId();
      await p.setString(_kDevice, id);
    }
    deviceId = id;
    if ((p.getString(_kTrial) ?? '').isEmpty) await p.setString(_kTrial, Fmt.todayYmd());
    await refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => refresh());
  }

  static String _newDeviceId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 0/O/1/I nahi — phone par parhne mein ghalti na ho
    final r = Random.secure();
    String part() => List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'HF-${part()}-${part()}';
  }

  /// Haalat dobara nikalo (aur [status] update).
  static Future<LicenseStatus> refresh() async {
    final p = await SharedPreferences.getInstance();
    final today = Fmt.todayYmd();

    // Tareekh peeche to nahi ki?
    final seen = p.getString(_kSeen) ?? '';
    final seenDate = Fmt.parseYmd(seen);
    if (seenDate != null && Fmt.today().isBefore(seenDate.subtract(const Duration(days: 1)))) {
      final s = LicenseStatus(kind: LicenseKind.clock, expiry: seen);
      status.value = s;
      return s;
    }
    if (seen.isEmpty || today.compareTo(seen) > 0) await p.setString(_kSeen, today);

    final key = p.getString(_kKey) ?? '';
    if (key.isNotEmpty) {
      final payload = await verify(key);
      if (payload != null) {
        final s = statusFor(payload, Fmt.today());
        status.value = s;
        return s;
      }
    }
    final start = Fmt.parseYmd(p.getString(_kTrial)) ?? Fmt.today();
    final s = trialStatus(start, Fmt.today());
    status.value = s;
    return s;
  }

  /// Trial ka hisaab (test ke liye alag).
  static LicenseStatus trialStatus(DateTime start, DateTime today) {
    final end = start.add(const Duration(days: trialDays - 1));
    final left = end.difference(today).inDays;
    return LicenseStatus(
      kind: left >= 0 ? LicenseKind.trial : LicenseKind.expired,
      plan: 'trial',
      expiry: Fmt.ymd(end),
      daysLeft: left,
    );
  }

  /// Sahi key ka hisaab (test ke liye alag).
  static LicenseStatus statusFor(LicensePayload p, DateTime today) {
    final end = Fmt.parseYmd(p.expiry) ?? today;
    final left = end.difference(today).inDays;
    final LicenseKind kind;
    if (p.plan == 'lifetime' || left > warnDays) {
      kind = LicenseKind.active;
    } else if (left >= 0) {
      kind = LicenseKind.expiring;
    } else if (left >= -graceDays) {
      kind = LicenseKind.grace;
    } else {
      kind = LicenseKind.expired;
    }
    return LicenseStatus(kind: kind, plan: p.plan, gym: p.gym, expiry: p.expiry, daysLeft: left);
  }

  /// Key ka signature, app aur device check. Ghalat => null.
  static Future<LicensePayload?> verify(String rawKey) async {
    final key = rawKey.replaceAll(RegExp(r'\s+'), '');
    final parts = key.split('.');
    if (parts.length != 3 || parts[0] != keyPrefix) return null;
    try {
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
      final sigBytes = base64Url.decode(base64Url.normalize(parts[2]));
      final ok = await Ed25519().verify(
        payloadBytes,
        signature: Signature(
          sigBytes,
          publicKey: SimplePublicKey(base64.decode(publicKeyB64), type: KeyPairType.ed25519),
        ),
      );
      if (!ok) return null;
      final m = json.decode(utf8.decode(payloadBytes));
      if (m is! Map) return null;
      final p = LicensePayload(
        app: '${m['app'] ?? ''}',
        device: '${m['dev'] ?? ''}',
        gym: '${m['gym'] ?? ''}',
        plan: '${m['plan'] ?? ''}',
        expiry: '${m['exp'] ?? ''}',
        issued: '${m['iss'] ?? ''}',
      );
      if (p.app != appCode) return null;
      if (p.device != '*' && p.device.toUpperCase() != deviceId.toUpperCase()) return null;
      if (Fmt.parseYmd(p.expiry) == null) return null;
      return p;
    } catch (_) {
      return null;
    }
  }

  /// License key lagao. Wapas: null = kamyab, warna wajah (user ke liye).
  static Future<String?> activate(String rawKey) async {
    final key = rawKey.replaceAll(RegExp(r'\s+'), '');
    if (key.isEmpty) return 'empty';
    final payload = await verify(key);
    if (payload == null) {
      // Wajah behtar batao: sahi key magar doosre device ki?
      return key.startsWith('$keyPrefix.') ? 'invalid_or_other_device' : 'invalid';
    }
    final s = statusFor(payload, Fmt.today());
    if (s.kind == LicenseKind.expired) return 'expired_key';
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, key);
    await refresh();
    return null;
  }

  /// Settings > License: lagi hui key hatao (trial / expired par wapas).
  static Future<void> removeKey() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    await refresh();
  }

  static String planLabel(String plan) => switch (plan) {
        'monthly' => 'Monthly',
        'quarterly' => '3 Months',
        'half_yearly' => '6 Months',
        'yearly' => 'Yearly',
        'lifetime' => 'Lifetime',
        _ => 'Free trial',
      };
}
