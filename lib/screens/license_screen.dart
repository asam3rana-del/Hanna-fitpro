import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../db/user_repository.dart';
import '../services/backup_service.dart';
import '../services/license_service.dart';
import '../services/messaging.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/ui.dart';
import 'login_screen.dart';

/// Haalat ka rang, icon aur jumla (screen aur dashboard banner dono ke liye).
(Color, IconData, String, String) licenseLook(LicenseStatus s) {
  final d = s.daysLeft;
  return switch (s.kind) {
    LicenseKind.active => (
        pal.green,
        Icons.verified,
        Loc.t('Licensed', 'لائسنس یافتہ'),
        s.isLifetime
            ? Loc.t('Lifetime license', 'تاحیات لائسنس')
            : Loc.t('${LicenseService.planLabel(s.plan)} · valid till ${Fmt.date(s.expiry)}',
                '${LicenseService.planLabel(s.plan)} · ${Fmt.date(s.expiry)} تک'),
      ),
    LicenseKind.expiring => (
        pal.amber,
        Icons.schedule,
        Loc.t('License ends in $d days', 'لائسنس $d دن میں ختم'),
        Loc.t('Renew before ${Fmt.date(s.expiry)} to keep working', '${Fmt.date(s.expiry)} سے پہلے تجدید کریں'),
      ),
    LicenseKind.grace => (
        pal.red,
        Icons.warning_amber,
        Loc.t('License expired', 'لائسنس ختم'),
        Loc.t('App will stop in ${LicenseService.graceDays + d + 1} day(s) — renew now', '${LicenseService.graceDays + d + 1} دن میں ایپ بند — ابھی تجدید کریں'),
      ),
    LicenseKind.trial => (
        pal.blue,
        Icons.hourglass_bottom,
        Loc.t('Free trial · ${d + 1} days left', 'مفت ٹرائل · ${d + 1} دن باقی'),
        Loc.t('Activate a license to keep using Hanna Fitness', 'استعمال جاری رکھنے کے لیے لائسنس لگائیں'),
      ),
    LicenseKind.expired => (
        pal.red,
        Icons.lock_outline,
        s.plan == 'trial' ? Loc.t('Free trial ended', 'مفت ٹرائل ختم') : Loc.t('License expired', 'لائسنس ختم'),
        Loc.t('Your data is safe. Enter a license key to continue.', 'آپ کا ڈیٹا محفوظ ہے۔ جاری رکھنے کے لیے لائسنس کی ڈالیں۔'),
      ),
    LicenseKind.clock => (
        pal.red,
        Icons.event_busy,
        Loc.t('Phone date is wrong', 'فون کی تاریخ غلط ہے'),
        Loc.t('Set the correct date & time (automatic) in phone settings, then reopen the app.',
            'فون کی سیٹنگز میں درست تاریخ اور وقت (خودکار) لگائیں، پھر ایپ دوبارہ کھولیں۔'),
      ),
  };
}

/// License: haalat, Device ID, key lagana. [blocking] = trial / license khatam (wapas nahi ja sakte).
class LicenseScreen extends StatefulWidget {
  final bool blocking;
  const LicenseScreen({super.key, this.blocking = false});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  String _errorText(String code) => switch (code) {
        'empty' => Loc.t('Paste the license key first', 'پہلے لائسنس کی پیسٹ کریں'),
        'expired_key' => Loc.t('This key has already expired', 'یہ کی پہلے ہی ختم ہو چکی ہے'),
        'invalid_or_other_device' => Loc.t(
            'Key not valid for this device (Device ID ${LicenseService.deviceId}). Check you sent the right Device ID.',
            'یہ کی اس ڈیوائس (${LicenseService.deviceId}) کے لیے نہیں۔ درست ڈیوائس آئی ڈی بھیجیں۔'),
        _ => Loc.t('Invalid license key', 'غلط لائسنس کی'),
      };

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await LicenseService.activate(_key.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : _errorText(err);
    });
    if (err == null) {
      _key.clear();
      toast(context, Loc.t('License activated ✓', 'لائسنس لگ گیا ✓'));
      if (!widget.blocking && Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (d?.text ?? '').trim();
    if (t.isNotEmpty) setState(() => _key.text = t);
  }

  void _request() {
    final text = 'Assalam o Alaikum, Hanna Solutions!\n'
        'Hanna Fitness license chahiye.\n'
        'Gym: ${GymSettings.gymName}\n'
        'Phone: ${GymSettings.gymPhone}\n'
        'Device ID: ${LicenseService.deviceId}';
    Messaging.whatsApp(context, AppInfo.supportPhone, text);
  }

  Future<void> _backup() async {
    try {
      final m = await BackupService.exportBackup();
      if (mounted) toast(context, m);
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e');
    }
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.blocking,
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: widget.blocking ? null : gymAppBar(Loc.t('License', 'لائسنس')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ValueListenableBuilder<LicenseStatus>(
                valueListenable: LicenseService.status,
                builder: (context, s, _) {
                  final (color, icon, title, sub) = licenseLook(s);
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    if (widget.blocking) ...[
                      const SizedBox(height: 10),
                      const Center(child: GymLogo(size: 78)),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(AppInfo.appName.toUpperCase(),
                            style: TextStyle(color: pal.ink, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    HeroHeader(
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                          child: Icon(icon, color: color, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, style: TextStyle(color: pal.onHeader, fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(sub, style: TextStyle(color: pal.onHeader.withValues(alpha: 0.7))),
                            if (s.gym.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(Loc.t('Licensed to: ${s.gym}', 'لائسنس: ${s.gym}'),
                                  style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700)),
                            ],
                          ]),
                        ),
                      ]),
                    ),
                    SectionTitle(Loc.t('Your Device ID', 'آپ کی ڈیوائس آئی ڈی')),
                    PCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SelectableText(
                          LicenseService.deviceId,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: pal.ink, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Loc.t('Send this ID to Hanna Solutions to get your license key.',
                              'لائسنس کی لینے کے لیے یہ آئی ڈی حنا سلوشنز کو بھیجیں۔'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: pal.muted, fontSize: 12.5),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: LicenseService.deviceId));
                                if (context.mounted) toast(context, Loc.t('Copied', 'کاپی ہو گیا'));
                              },
                              icon: Icon(Icons.copy, color: pal.gold),
                              label: Text(Loc.t('Copy', 'کاپی')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _request,
                              icon: const Icon(Icons.chat),
                              label: Text(Loc.t('Request', 'درخواست')),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    SectionTitle(Loc.t('Enter license key', 'لائسنس کی ڈالیں')),
                    PCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        TextField(
                          controller: _key,
                          minLines: 3,
                          maxLines: 5,
                          style: TextStyle(color: pal.ink, fontFamily: 'monospace', fontSize: 12.5),
                          decoration: ThemeManager.field(Loc.t('Paste key (starts with HF1.)', 'کی پیسٹ کریں (HF1. سے شروع)')),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: TextStyle(color: pal.red, fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _paste,
                              icon: Icon(Icons.content_paste, color: pal.gold),
                              label: Text(Loc.t('Paste', 'پیسٹ')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: GoldButton(
                              label: Loc.t('ACTIVATE', 'لائسنس لگائیں'),
                              icon: Icons.vpn_key,
                              busy: _busy,
                              onPressed: _activate,
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text('${AppInfo.business} · ${AppInfo.supportPhone} · ${AppInfo.supportEmail}',
                          textAlign: TextAlign.center, style: TextStyle(color: pal.muted, fontSize: 12)),
                    ),
                    if (widget.blocking) ...[
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _backup,
                            icon: Icon(Icons.backup_outlined, color: pal.muted),
                            label: Text(Loc.t('Backup my data', 'ڈیٹا کا بیک اپ'), style: TextStyle(color: pal.muted)),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _logout,
                            icon: Icon(Icons.logout, color: pal.muted),
                            label: Text(Loc.t('Logout', 'لاگ آؤٹ'), style: TextStyle(color: pal.muted)),
                          ),
                        ),
                      ]),
                    ],
                  ]);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashboard par chhota license banner (trial / khatam hone wala). Active par kuch nahi.
class LicenseBanner extends StatelessWidget {
  const LicenseBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LicenseStatus>(
        valueListenable: LicenseService.status,
        builder: (context, s, _) {
          if (!s.needsAttention) return const SizedBox.shrink();
          final (color, icon, title, _) = licenseLook(s);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PCard(
              borderColor: color.withValues(alpha: 0.6),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
              child: Row(children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800))),
                Text(Loc.t('Activate', 'لائسنس'), style: TextStyle(color: pal.gold, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right, color: pal.muted),
              ]),
            ),
          );
        },
      );
}
