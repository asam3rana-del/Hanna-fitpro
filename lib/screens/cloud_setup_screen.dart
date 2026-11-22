import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/user_repository.dart';
import '../sync/cloud_config_store.dart';
import '../sync/gym_sync.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import '../widgets/ui.dart';

/// Online sync (mobile + PC, kai devices) ka setup: Firebase project + Gym Code.
class CloudSetupScreen extends StatefulWidget {
  /// true = login screen se "maujooda gym jorein" (sync ke baad wapas login par).
  final bool joining;
  const CloudSetupScreen({super.key, this.joining = false});

  @override
  State<CloudSetupScreen> createState() => _CloudSetupScreenState();
}

class _CloudSetupScreenState extends State<CloudSetupScreen> {
  final _json = TextEditingController();
  final _project = TextEditingController();
  final _apiKey = TextEditingController();
  final _appId = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _configured = false;
  String _savedCode = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_json, _project, _apiKey, _appId, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final c = await CloudConfigStore.get();
    final code = await GymSync.gymCode();
    if (!mounted) return;
    setState(() {
      if (c != null) {
        _project.text = c.projectId;
        _apiKey.text = c.apiKey;
        _appId.text = c.appId;
      }
      _code.text = code;
      _savedCode = code;
      _configured = c != null && code.isNotEmpty;
    });
  }

  void _parseJson() {
    final c = parseGoogleServicesJson(_json.text);
    if (c == null) {
      toast(context, Loc.t('Could not read this JSON — paste the full google-services.json', 'یہ JSON نہیں پڑھا جا سکا — پوری google-services.json پیسٹ کریں'));
      return;
    }
    setState(() {
      _project.text = c.projectId;
      _apiKey.text = c.apiKey;
      _appId.text = c.appId;
    });
    toast(context, Loc.t('Filled from JSON ✓', 'JSON سے بھر دیا ✓'));
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text ?? '';
    if (t.isEmpty) return;
    _json.text = t;
    _parseJson();
  }

  Future<void> _saveAndSync() async {
    final code = GymSync.cleanCode(_code.text);
    if (_project.text.trim().isEmpty || _apiKey.text.trim().isEmpty || _appId.text.trim().isEmpty) {
      toast(context, Loc.t('Fill Project ID, API Key and App ID', 'Project ID، API Key اور App ID بھریں'));
      return;
    }
    if (code.length < 4) {
      toast(context, Loc.t('Gym Code must be at least 4 letters (e.g. GYM-BHIKHI)', 'جم کوڈ کم از کم 4 حروف (مثلاً GYM-BHIKHI)'));
      return;
    }
    setState(() => _busy = true);
    await CloudConfigStore.save(CloudConfig(
      projectId: _project.text.trim(),
      apiKey: _apiKey.text.trim(),
      appId: _appId.text.trim(),
    ));
    if (code != _savedCode) {
      await GymSync.setGymCode(code);
      await GymSync.resetMarkers();
    }
    final msg = await GymSync.instance.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _savedCode = code;
      _code.text = code;
      _configured = true;
    });
    toast(context, msg);
    if (widget.joining && GymSync.instance.status.value.ok && await UserRepository.instance.hasAnyUser()) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirm(
      context,
      Loc.t('Turn off cloud sync?', 'کلاؤڈ سنک بند کریں؟'),
      Loc.t('Data on this device stays safe. Other devices will stop receiving updates from this one.',
          'اس ڈیوائس کا ڈیٹا محفوظ رہے گا۔ دوسرے ڈیوائسز کو اس سے اپڈیٹ نہیں ملے گی۔'),
      danger: true,
    );
    if (!ok) return;
    await CloudConfigStore.clear();
    await GymSync.setGymCode('');
    await _load();
    GymSync.instance.status.value = const SyncStatus(message: 'Off');
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pal.goldSoft, shape: BoxShape.circle),
            child: Text(n, style: TextStyle(color: pal.gold, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: pal.ink, height: 1.35))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Online Sync', 'آن لائن سنک'),
          subtitle: Loc.t('Mobile + PC · multiple devices', 'موبائل + کمپیوٹر · کئی ڈیوائسز')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            ValueListenableBuilder<SyncStatus>(
              valueListenable: GymSync.instance.status,
              builder: (context, s, _) => PCard(
                borderColor: _configured ? (s.ok ? pal.green : pal.red) : pal.border,
                child: Row(children: [
                  Icon(
                    !_configured ? Icons.cloud_off_outlined : (s.running ? Icons.sync : (s.ok ? Icons.cloud_done_outlined : Icons.error_outline)),
                    color: !_configured ? pal.muted : (s.ok ? pal.green : pal.red),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _configured
                            ? Loc.t('Connected · Gym Code: $_savedCode', 'جڑا ہوا · جم کوڈ: $_savedCode')
                            : Loc.t('Not connected (app works fully offline)', 'جڑا نہیں (ایپ آف لائن مکمل چلتی ہے)'),
                        style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700),
                      ),
                      if (s.message.isNotEmpty) Text(s.message, style: TextStyle(color: pal.muted, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
            ),
            SectionTitle(Loc.t('How it works', 'طریقہ')),
            PCard(
              child: Column(children: [
                _step('1', Loc.t('Create a free Firebase project (console.firebase.google.com).', 'مفت Firebase پراجیکٹ بنائیں (console.firebase.google.com)۔')),
                _step('2', Loc.t('Build > Firestore Database > Create. Then Rules: paste firebase/firestore.rules and Publish.', 'Firestore Database بنائیں، پھر Rules میں firebase/firestore.rules پیسٹ کر کے Publish کریں۔')),
                _step('3', Loc.t('Authentication > Sign-in method > turn ON "Anonymous".', 'Authentication > Sign-in method میں "Anonymous" آن کریں۔')),
                _step('4', Loc.t('Project settings > Add Android app (com.hannasolutions.fitness) > download google-services.json and paste it below.', 'Project settings میں Android ایپ (com.hannasolutions.fitness) شامل کریں، google-services.json نیچے پیسٹ کریں۔')),
                _step('5', Loc.t('Use the SAME Gym Code on every phone and PC of this gym.', 'اس جم کے ہر فون اور کمپیوٹر پر ایک ہی جم کوڈ لکھیں۔')),
              ]),
            ),
            SectionTitle(Loc.t('Firebase project', 'Firebase پراجیکٹ')),
            PCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _json,
                  minLines: 3,
                  maxLines: 6,
                  style: TextStyle(color: pal.ink, fontFamily: 'monospace', fontSize: 12),
                  decoration: ThemeManager.field(Loc.t('Paste google-services.json here', 'google-services.json یہاں پیسٹ کریں')),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _paste, icon: const Icon(Icons.content_paste), label: Text(Loc.t('Paste', 'پیسٹ'))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _parseJson, icon: const Icon(Icons.auto_fix_high), label: Text(Loc.t('Read JSON', 'JSON پڑھیں'))),
                  ),
                ]),
                const SizedBox(height: 14),
                TextField(controller: _project, decoration: ThemeManager.field('Project ID', icon: Icons.folder_outlined)),
                const SizedBox(height: 10),
                TextField(controller: _apiKey, decoration: ThemeManager.field('API Key', icon: Icons.key_outlined)),
                const SizedBox(height: 10),
                TextField(controller: _appId, decoration: ThemeManager.field('App ID', icon: Icons.apps_outlined)),
              ]),
            ),
            SectionTitle(Loc.t('Gym Code', 'جم کوڈ')),
            PCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: ThemeManager.field(Loc.t('Gym Code (e.g. GYM-BHIKHI)', 'جم کوڈ (مثلاً GYM-BHIKHI)'), icon: Icons.tag),
                ),
                const SizedBox(height: 6),
                Text(
                  Loc.t('Keep it private — anyone with your Firebase file and this code can open your data.',
                      'اسے راز رکھیں — Firebase فائل اور یہ کوڈ جس کے پاس ہو وہ ڈیٹا کھول سکتا ہے۔'),
                  style: TextStyle(color: pal.muted, fontSize: 12),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            GoldButton(
              label: Loc.t('SAVE & SYNC NOW', 'محفوظ کریں اور سنک کریں'),
              icon: Icons.cloud_sync,
              busy: _busy,
              onPressed: _saveAndSync,
            ),
            if (_configured && !widget.joining) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _disconnect,
                icon: Icon(Icons.link_off, color: pal.red),
                label: Text(Loc.t('Turn off cloud sync on this device', 'اس ڈیوائس پر کلاؤڈ سنک بند کریں'), style: TextStyle(color: pal.red)),
              ),
            ],
            const SizedBox(height: 30),
          ]),
        ),
      ),
    );
  }
}
