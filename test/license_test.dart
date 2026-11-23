import 'package:flutter_test/flutter_test.dart';

import 'package:hanna_fitness/services/license_service.dart';

// Test keys: device 'HF-TEST-ONLY' — 'O' Device ID ke huroof mein nahi, is liye kisi asli device par nahi chalti.
const _good = 'HF1.eyJ2IjoxLCJhcHAiOiJoYW5uYV9maXRuZXNzIiwiZGV2IjoiSEYtVEVTVC1PTkxZIiwiZ3ltIjoiVGVzdCBHeW0iLCJwbGFuIjoieWVhcmx5IiwiZXhwIjoiMjA5OS0xMi0zMSIsImlzcyI6IjIwMjYtMTEtMjMifQ.bOqJrzrO7Wx2T1hkFfPbmIFWdqRcMT0kfeW8WCHpmxPIp3wKd2eH2DAKGPUcXJ_V2jjGq_5gRRHFTn5ozt_1DA';
const _otherApp = 'HF1.eyJ2IjoxLCJhcHAiOiJoYW5uYV9wb3MiLCJkZXYiOiJIRi1URVNULU9OTFkiLCJneW0iOiJUZXN0IEd5bSIsInBsYW4iOiJ5ZWFybHkiLCJleHAiOiIyMDk5LTEyLTMxIiwiaXNzIjoiMjAyNi0xMS0yMyJ9.RKuY2WNJkjJSNgXmDzVFl-4xa8uUoMKK4EP9LOUIm9nGoEKQdnD-LPwuopXsLcyLXbgNlKIJpxn2qJ3GqVXhBQ';

LicensePayload _p(String plan, String exp) =>
    LicensePayload(app: 'hanna_fitness', device: '*', gym: 'G', plan: plan, expiry: exp, issued: '2026-01-01');

void main() {
  test('signed key verifies only on its own device and app', () async {
    LicenseService.deviceId = 'HF-TEST-ONLY';
    final p = await LicenseService.verify(_good);
    expect(p, isNotNull);
    expect(p!.plan, 'yearly');
    expect(p.gym, 'Test Gym');
    expect(await LicenseService.verify(_otherApp), isNull);

    LicenseService.deviceId = 'HF-ABCD-EFGH';
    expect(await LicenseService.verify(_good), isNull);
  });

  test('tampered key is rejected', () async {
    LicenseService.deviceId = 'HF-TEST-ONLY';
    final parts = _good.split('.');
    final body = parts[1];
    final tampered = '${parts[0]}.${body.substring(0, body.length - 4)}AAAA.${parts[2]}';
    expect(await LicenseService.verify(tampered), isNull);
    expect(await LicenseService.verify('garbage'), isNull);
  });

  test('status: active, expiring, grace, expired, lifetime', () {
    final today = DateTime.utc(2026, 11, 23);
    expect(LicenseService.statusFor(_p('yearly', '2027-11-22'), today).kind, LicenseKind.active);
    expect(LicenseService.statusFor(_p('monthly', '2026-11-28'), today).kind, LicenseKind.expiring);
    expect(LicenseService.statusFor(_p('monthly', '2026-11-21'), today).kind, LicenseKind.grace);
    expect(LicenseService.statusFor(_p('monthly', '2026-11-01'), today).kind, LicenseKind.expired);
    expect(LicenseService.statusFor(_p('monthly', '2026-11-01'), today).blocked, isTrue);
    expect(LicenseService.statusFor(_p('lifetime', '9999-12-31'), today).kind, LicenseKind.active);
  });

  test('trial lasts 14 days, then blocks', () {
    final start = DateTime.utc(2026, 11, 1);
    expect(LicenseService.trialStatus(start, DateTime.utc(2026, 11, 1)).kind, LicenseKind.trial);
    expect(LicenseService.trialStatus(start, DateTime.utc(2026, 11, 14)).kind, LicenseKind.trial);
    expect(LicenseService.trialStatus(start, DateTime.utc(2026, 11, 15)).kind, LicenseKind.expired);
  });
}
