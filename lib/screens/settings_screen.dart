import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../db/user_repository.dart';
import '../services/app_lock.dart';
import '../services/backup_service.dart';
import '../services/biometric.dart';
import '../services/crash_handler.dart';
import '../services/photo_service.dart';
import '../services/session.dart';
import '../sync/gym_sync.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import '../widgets/watermark.dart';
import 'cloud_setup_screen.dart';
import 'login_screen.dart';
import 'users_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _loginMethod = 'password';
  bool _bio = false;
  bool _syncOn = false;
  String? _crash;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await UserRepository.instance.getSetting('login_method') ?? 'password';
    final bio = await Biometric.isAvailable();
    final on = await GymSync.isConfigured();
    final crash = await CrashHandler.getLastCrash();
    if (!mounted) return;
    setState(() {
      _loginMethod = m;
      _bio = bio;
      _syncOn = on;
      _crash = crash;
    });
  }

  Future<void> _editText(String key, String label, String current, {bool number = false, int lines = 1}) async {
    final c = TextEditingController(text: current);
    await showGymSheet<void>(
      context,
      title: label,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: c,
          autofocus: true,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 4,
          keyboardType: number ? TextInputType.number : (lines > 1 ? TextInputType.multiline : TextInputType.text),
          decoration: ThemeManager.field(label),
        ),
        if (key == 'reminder_template') ...[
          const SizedBox(height: 8),
          Text('{name} {gym} {plan} {date} {days} {dues}', style: TextStyle(color: pal.muted, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        GoldButton(
          label: Loc.t('SAVE', 'محفوظ کریں'),
          onPressed: () async {
            await GymSettings.set(key, c.text.trim());
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ]),
    );
    if (mounted) setState(() {});
  }

  Future<void> _watermark() async {
    var opacity = GymSettings.watermarkOpacity;
    await showGymSheet<void>(
      context,
      title: Loc.t('Dashboard watermark', 'ڈیش بورڈ واٹر مارک'),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final b = GymWatermark.bytes();
        Future<void> apply(String key, String value) async {
          await GymSettings.set(key, value);
          GymWatermark.changes.value++;
          setSheet(() {});
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            Loc.t('Your gym banner or logo shows lightly across the dashboard. It syncs to all devices.',
                'جم کا بینر یا لوگو ڈیش بورڈ پر ہلکا سا نظر آئے گا۔ سب ڈیوائسز پر سنک ہو گا۔'),
            style: TextStyle(color: pal.muted),
          ),
          const SizedBox(height: 14),
          Container(
            height: 170,
            decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.border)),
            clipBehavior: Clip.antiAlias,
            child: b == null
                ? Center(child: Icon(Icons.image_outlined, color: pal.muted, size: 40))
                : Opacity(
                    opacity: opacity < 0.25 ? 0.25 + opacity : opacity,
                    child: Image.memory(b, fit: GymSettings.watermarkFit == 'cover' ? BoxFit.cover : BoxFit.contain),
                  ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final img = await PhotoService.pick(ImageSource.gallery, maxSide: 1600, quality: 70);
              if (img == null) return;
              await apply('watermark', img);
            },
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(b == null ? Loc.t('Choose image', 'تصویر چنیں') : Loc.t('Change image', 'تصویر بدلیں')),
          ),
          if (b != null) ...[
            const SizedBox(height: 14),
            Text(Loc.t('Strength ${(opacity * 100).round()}%', 'شدت ${(opacity * 100).round()}%'),
                style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
            Slider(
              value: opacity,
              min: 0.03,
              max: 0.35,
              divisions: 32,
              onChanged: (v) => setSheet(() => opacity = v),
              onChangeEnd: (v) => apply('watermark_opacity', v.toStringAsFixed(2)),
            ),
            ChoiceChips<String>(
              options: [('contain', Loc.t('Full image', 'پوری تصویر')), ('cover', Loc.t('Fill screen', 'پوری اسکرین'))],
              value: GymSettings.watermarkFit,
              onChanged: (v) => apply('watermark_fit', v),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => apply('watermark', ''),
              icon: Icon(Icons.delete_outline, color: pal.red),
              label: Text(Loc.t('Remove watermark', 'واٹر مارک ہٹائیں'), style: TextStyle(color: pal.red)),
            ),
          ],
        ]);
      }),
    );
    if (mounted) setState(() {});
  }

  Future<void> _setLogin(String m) async {
    await UserRepository.instance.setSetting('login_method', m);
    AppLock.instance.updateCachedLoginMethod(m);
    setState(() => _loginMethod = m);
  }

  Future<void> _export() async {
    try {
      final msg = await BackupService.exportBackup();
      if (mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e');
    }
  }

  Future<void> _restore() async {
    final ok = await confirm(
      context,
      Loc.t('Restore from backup?', 'بیک اپ سے بحال کریں؟'),
      Loc.t('ALL current data on this device will be replaced by the backup file. A safety copy is kept first.',
          'اس ڈیوائس کا موجودہ سارا ڈیٹا بیک اپ فائل سے بدل جائے گا۔ پہلے ایک حفاظتی کاپی بن جائے گی۔'),
      yes: Loc.t('Choose file', 'فائل چنیں'),
      danger: true,
    );
    if (!ok) return;
    try {
      final msg = await BackupService.restoreBackup();
      if (msg == null || !mounted) return;
      toast(context, msg);
      if (msg.startsWith('Restore complete')) {
        await Session.clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      }
    } catch (e) {
      if (mounted) toast(context, 'Restore failed: $e');
    }
  }

  Future<void> _autoBackups() async {
    final files = await BackupService.autoBackups();
    if (!mounted) return;
    await showGymSheet<void>(
      context,
      title: Loc.t('Automatic backups (on this device)', 'خودکار بیک اپ (اس ڈیوائس پر)'),
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          Loc.t('One copy is saved every day (last 7 kept). Share one to keep it safe outside the phone.',
              'روز ایک کاپی بنتی ہے (آخری 7 رہتی ہیں)۔ فون سے باہر محفوظ رکھنے کے لیے شیئر کریں۔'),
          style: TextStyle(color: pal.muted),
        ),
        const SizedBox(height: 10),
        if (files.isEmpty) Text(Loc.t('None yet', 'ابھی کوئی نہیں'), style: TextStyle(color: pal.muted)),
        for (final f in files)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.inventory_2_outlined, color: pal.gold),
            title: Text(p.basename(f.path), style: TextStyle(color: pal.ink, fontSize: 13.5)),
            subtitle: Text('${(f.lengthSync() / 1024).toStringAsFixed(0)} KB', style: TextStyle(color: pal.muted, fontSize: 12)),
            trailing: IconButton(
              icon: Icon(Icons.share, color: pal.gold),
              onPressed: () => BackupService.shareFile(File(f.path)),
            ),
          ),
      ]),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, {VoidCallback? onTap, Widget? trailing, Color? color}) => ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: (color ?? pal.gold).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color ?? pal.gold, size: 20),
        ),
        title: Text(title, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12.5)),
        trailing: trailing ?? (onTap == null ? null : Icon(Icons.chevron_right, color: pal.muted)),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final canEdit = Session.canManage;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Settings', 'سیٹنگز')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
            SectionTitle(Loc.t('Gym profile', 'جم پروفائل')),
            PCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                _tile(Icons.fitness_center, Loc.t('Gym name', 'جم کا نام'), GymSettings.gymName,
                    onTap: canEdit ? () => _editText('gym_name', Loc.t('Gym name', 'جم کا نام'), GymSettings.gymName) : null),
                _tile(Icons.short_text, Loc.t('Tagline', 'ٹیگ لائن'), GymSettings.gymTagline,
                    onTap: canEdit ? () => _editText('gym_tagline', Loc.t('Tagline', 'ٹیگ لائن'), GymSettings.gymTagline) : null),
                _tile(Icons.phone_outlined, Loc.t('Gym phone', 'جم کا فون'), GymSettings.gymPhone,
                    onTap: canEdit ? () => _editText('gym_phone', Loc.t('Gym phone', 'جم کا فون'), GymSettings.gymPhone) : null),
                _tile(Icons.place_outlined, Loc.t('Address', 'پتہ'), GymSettings.gymAddress,
                    onTap: canEdit ? () => _editText('gym_address', Loc.t('Address', 'پتہ'), GymSettings.gymAddress) : null),
              ]),
            ),
            if (canEdit) ...[
              const SizedBox(height: 10),
              PCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _tile(
                  Icons.wallpaper,
                  Loc.t('Dashboard watermark', 'ڈیش بورڈ واٹر مارک'),
                  GymSettings.watermark.isEmpty
                      ? Loc.t('Put your gym banner / logo behind the dashboard', 'جم کا بینر / لوگو ڈیش بورڈ پر لگائیں')
                      : Loc.t('On · ${(GymSettings.watermarkOpacity * 100).round()}%', 'آن · ${(GymSettings.watermarkOpacity * 100).round()}%'),
                  onTap: _watermark,
                ),
              ),
            ],
            SectionTitle(Loc.t('Membership rules', 'ممبرشپ کے اصول')),
            PCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                _tile(Icons.badge_outlined, Loc.t('Member ID prefix', 'ممبر آئی ڈی کا شروع'), '${GymSettings.memberPrefix}-0001',
                    onTap: canEdit
                        ? () => _editText('member_prefix', Loc.t('Member ID prefix (e.g. GM)', 'آئی ڈی کا شروع (مثلاً GM)'), GymSettings.memberPrefix)
                        : null),
                _tile(Icons.how_to_reg_outlined, Loc.t('Default admission fee', 'داخلہ فیس'), Fmt.money(GymSettings.admissionFee),
                    onTap: canEdit
                        ? () => _editText('admission_fee', Loc.t('Default admission fee', 'داخلہ فیس'),
                            GymSettings.admissionFee.toStringAsFixed(0), number: true)
                        : null),
                _tile(Icons.notifications_active_outlined, Loc.t('Reminder before expiry', 'ختم ہونے سے پہلے یاد دہانی'),
                    Loc.t('${GymSettings.reminderDays} days', '${GymSettings.reminderDays} دن'),
                    onTap: canEdit
                        ? () => _editText('reminder_days', Loc.t('Days before expiry', 'ختم ہونے سے کتنے دن پہلے'), '${GymSettings.reminderDays}',
                            number: true)
                        : null),
                _tile(Icons.currency_rupee, Loc.t('Currency', 'کرنسی'), GymSettings.currency,
                    onTap: canEdit ? () => _editText('currency', Loc.t('Currency', 'کرنسی'), GymSettings.currency) : null),
                _tile(Icons.chat_outlined, Loc.t('WhatsApp reminder message', 'واٹس ایپ یاد دہانی پیغام'), GymSettings.reminderTemplate,
                    onTap: canEdit
                        ? () => _editText('reminder_template', Loc.t('Reminder message', 'یاد دہانی پیغام'), GymSettings.reminderTemplate, lines: 5)
                        : null),
                _tile(Icons.receipt_outlined, Loc.t('Receipt footer', 'رسید کا آخری پیغام'), GymSettings.receiptNote,
                    onTap: canEdit
                        ? () => _editText('receipt_note', Loc.t('Receipt footer', 'رسید کا آخری پیغام'), GymSettings.receiptNote, lines: 2)
                        : null),
              ]),
            ),
            SectionTitle(Loc.t('App', 'ایپ')),
            PCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                _tile(Icons.translate, Loc.t('Language', 'زبان'), Loc.isUrdu ? 'اردو' : 'English',
                    trailing: OutlinedButton(
                      onPressed: () => Loc.setLanguage(Loc.isUrdu ? 'en' : 'ur'),
                      child: Text(Loc.isUrdu ? 'English' : 'اردو'),
                    )),
                _tile(Icons.dark_mode_outlined, Loc.t('Dark mode (premium black)', 'ڈارک موڈ'), '',
                    trailing: Switch(value: ThemeManager.isDark.value, onChanged: (v) => ThemeManager.setDarkMode(v))),
              ]),
            ),
            SectionTitle(Loc.t('Security (this device)', 'سیکیورٹی (یہ ڈیوائس)')),
            PCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Loc.t('Login method', 'لاگ اِن کا طریقہ'), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ChoiceChips<String>(
                  options: [
                    ('password', Loc.t('Password', 'پاس ورڈ')),
                    if (_bio) ('fingerprint', Loc.t('Fingerprint', 'فنگر پرنٹ')),
                    if (_bio) ('both', Loc.t('Both', 'دونوں')),
                  ],
                  value: (_bio || _loginMethod == 'password') ? _loginMethod : 'password',
                  onChanged: _setLogin,
                ),
                const SizedBox(height: 8),
                Text(
                  Loc.t('With fingerprint, the app locks itself whenever it goes to the background.',
                      'فنگر پرنٹ کے ساتھ ایپ پیچھے جاتے ہی خود لاک ہو جاتی ہے۔'),
                  style: TextStyle(color: pal.muted, fontSize: 12),
                ),
              ]),
            ),
            if (Session.isAdmin) ...[
              SectionTitle(Loc.t('Staff', 'اسٹاف')),
              PCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _tile(Icons.manage_accounts_outlined, Loc.t('Staff logins & roles', 'اسٹاف لاگ اِن اور رولز'),
                    Loc.t('Owner, manager, reception', 'مالک، مینیجر، ریسپشن'),
                    onTap: () => push(context, const UsersScreen()), color: pal.blue),
              ),
            ],
            SectionTitle(Loc.t('Online sync', 'آن لائن سنک')),
            PCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                ValueListenableBuilder<SyncStatus>(
                  valueListenable: GymSync.instance.status,
                  builder: (context, s, _) => _tile(
                    _syncOn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    _syncOn ? Loc.t('Sync is ON — mobile + PC', 'سنک آن ہے — موبائل + کمپیوٹر') : Loc.t('Sync is OFF', 'سنک بند ہے'),
                    s.message.isEmpty
                        ? (s.lastOkMs > 0
                            ? '${Loc.t('Last sync', 'آخری سنک')}: ${Fmt.dateOf(DateTime.fromMillisecondsSinceEpoch(s.lastOkMs))} ${Fmt.time(s.lastOkMs)}'
                            : '')
                        : s.message,
                    color: _syncOn ? pal.green : pal.muted,
                    trailing: _syncOn
                        ? IconButton(
                            icon: Icon(Icons.sync, color: pal.gold),
                            onPressed: () async {
                              final m = await GymSync.instance.syncNow();
                              if (context.mounted) toast(context, m);
                            },
                          )
                        : null,
                  ),
                ),
                if (Session.isAdmin)
                  _tile(Icons.settings_ethernet, Loc.t('Cloud sync setup', 'کلاؤڈ سنک سیٹ اپ'),
                      Loc.t('Connect phones & PCs of this gym', 'اس جم کے فون اور کمپیوٹر جوڑیں'), onTap: () async {
                    await push(context, const CloudSetupScreen());
                    _load();
                  }),
              ]),
            ),
            SectionTitle(Loc.t('Backup', 'بیک اپ')),
            PCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                _tile(Icons.backup_outlined, Loc.t('Export backup', 'بیک اپ بنائیں'),
                    Loc.t('Save a full copy to Drive / WhatsApp / USB', 'مکمل کاپی ڈرائیو / واٹس ایپ / USB پر رکھیں'),
                    onTap: _export),
                _tile(Icons.history, Loc.t('Automatic daily backups', 'روزانہ خودکار بیک اپ'), Loc.t('Last 7 days on this device', 'اس ڈیوائس پر آخری 7 دن'),
                    onTap: _autoBackups),
                if (Session.isAdmin)
                  _tile(Icons.settings_backup_restore, Loc.t('Restore from backup', 'بیک اپ سے بحال کریں'),
                      Loc.t('Replace data on this device', 'اس ڈیوائس کا ڈیٹا بدلیں'),
                      onTap: _restore, color: pal.red),
              ]),
            ),
            SectionTitle(Loc.t('About', 'تعارف')),
            PCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const GymLogo(size: 54),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(AppInfo.appName, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900, fontSize: 17)),
                      Text('${AppInfo.tagline} · v1.0${AppInfo.build.isEmpty ? '' : ' (build ${AppInfo.build})'}',
                          style: TextStyle(color: pal.muted, fontSize: 12.5)),
                      Text('${AppInfo.business} · ${AppInfo.developer}', style: TextStyle(color: pal.gold, fontSize: 12.5)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://wa.me/${AppInfo.supportWhatsAppIntl}?text=${Uri.encodeComponent('Hanna Fitness support')}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: Icon(Icons.support_agent, color: pal.green),
                  label: Text(Loc.t('WhatsApp support ${AppInfo.supportPhone}', 'واٹس ایپ سپورٹ ${AppInfo.supportPhone}')),
                ),
                if (_crash != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _crash!));
                      await CrashHandler.clearLastCrash();
                      if (!mounted) return;
                      setState(() => _crash = null);
                      toast(context, Loc.t('Error report copied — send it to support', 'خرابی کی رپورٹ کاپی — سپورٹ کو بھیجیں'));
                    },
                    icon: Icon(Icons.bug_report_outlined, color: pal.amber),
                    label: Text(Loc.t('Copy last error report', 'آخری خرابی کی رپورٹ کاپی کریں'), style: TextStyle(color: pal.amber)),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
