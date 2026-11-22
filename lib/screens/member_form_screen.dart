import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/gym_repo.dart';
import '../models/models.dart';
import '../services/photo_service.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/contact_pick_button.dart';
import '../widgets/ui.dart';
import 'member_profile_screen.dart';

/// Naya member / member ki tafseel badlo.
class MemberFormScreen extends StatefulWidget {
  final Member? member;
  const MemberFormScreen({super.key, this.member});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _cnic = TextEditingController();
  final _address = TextEditingController();
  final _emName = TextEditingController();
  final _emPhone = TextEditingController();
  final _height = TextEditingController();
  final _notes = TextEditingController();

  String _gender = 'male';
  String _blood = '';
  String _timing = '';
  String _goal = '';
  String? _trainerId;
  String _status = 'active';
  DateTime _joined = Fmt.today();
  DateTime? _dob;
  String? _photoB64; // nayi chuni hui
  bool _photoRemoved = false;
  bool _busy = false;
  List<Trainer> _trainers = [];

  bool get _editing => widget.member != null;

  static const _bloods = ['', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const _goals = ['', 'Weight loss', 'Muscle gain', 'General fitness', 'Strength', 'Body building', 'Rehab / Medical'];

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    if (m != null) {
      _name.text = m.name;
      _phone.text = m.phone;
      _code.text = m.code;
      _cnic.text = m.cnic;
      _address.text = m.address;
      _emName.text = m.emergencyName;
      _emPhone.text = m.emergencyPhone;
      _height.text = m.heightCm > 0 ? Fmt.decimal(m.heightCm) : '';
      _notes.text = m.notes;
      _gender = m.gender.isEmpty ? 'male' : m.gender;
      _blood = _bloods.contains(m.bloodGroup) ? m.bloodGroup : '';
      _timing = m.timing;
      _goal = _goals.contains(m.goal) ? m.goal : '';
      _trainerId = m.trainerId;
      _status = m.status;
      _joined = Fmt.parseYmd(m.joinedOn) ?? Fmt.today();
      _dob = Fmt.parseYmd(m.dob);
    } else {
      MemberRepo.nextCode().then((c) {
        if (mounted && _code.text.isEmpty) setState(() => _code.text = c);
      });
    }
    TrainerRepo.all(activeOnly: true).then((t) {
      if (mounted) setState(() => _trainers = t);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _code, _cnic, _address, _emName, _emPhone, _height, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _pickPhoto() async {
    final source = !_mobile
        ? ImageSource.gallery
        : await showModalBottomSheet<ImageSource>(
            context: context,
            backgroundColor: pal.card,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  leading: Icon(Icons.photo_camera_outlined, color: pal.gold),
                  title: Text(Loc.t('Take photo', 'تصویر لیں')),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: pal.gold),
                  title: Text(Loc.t('Choose from gallery', 'گیلری سے چنیں')),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ]),
            ),
          );
    if (source == null) return;
    final b64 = await PhotoService.pick(source);
    if (b64 != null && mounted) {
      setState(() {
        _photoB64 = b64;
        _photoRemoved = false;
      });
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, Loc.t('Enter member name', 'ممبر کا نام لکھیں'));
      return;
    }
    final code = _code.text.trim().isEmpty ? await MemberRepo.nextCode() : _code.text.trim().toUpperCase();
    if (await MemberRepo.codeTaken(code, exceptId: widget.member?.id)) {
      if (mounted) toast(context, Loc.t('Member ID $code is already used', 'ممبر آئی ڈی $code پہلے سے موجود ہے'));
      return;
    }
    setState(() => _busy = true);
    final m = Member(
      id: widget.member?.id ?? '',
      code: code,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      cnic: _cnic.text.trim(),
      gender: _gender,
      dob: _dob == null ? null : Fmt.ymd(_dob!),
      address: _address.text.trim(),
      emergencyName: _emName.text.trim(),
      emergencyPhone: _emPhone.text.trim(),
      bloodGroup: _blood,
      joinedOn: Fmt.ymd(_joined),
      trainerId: _trainerId,
      timing: _timing,
      goal: _goal,
      heightCm: Fmt.toDouble(_height.text),
      notes: _notes.text.trim(),
      status: _status,
    );
    if (_editing) {
      await MemberRepo.save(m);
      if (_photoB64 != null || _photoRemoved) {
        await MemberRepo.setPhoto(m.id, _photoRemoved ? null : _photoB64);
        PhotoService.invalidate(m.id);
      }
      if (mounted) Navigator.pop(context, true);
    } else {
      final id = await MemberRepo.create(m, photo: _photoB64);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MemberProfileScreen(memberId: id, openNewMembership: true),
      ));
    }
  }

  Widget _photo() {
    Widget inner;
    if (_photoB64 != null) {
      inner = ClipOval(child: Image.memory(base64Decode(_photoB64!), width: 104, height: 104, fit: BoxFit.cover));
    } else if (_editing && !_photoRemoved) {
      inner = MemberAvatar(memberId: widget.member!.id, name: widget.member!.name, hasPhoto: true, size: 104);
    } else {
      inner = Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(shape: BoxShape.circle, color: pal.goldSoft),
        child: Icon(Icons.person, size: 54, color: pal.gold),
      );
    }
    return Center(
      child: Stack(children: [
        GestureDetector(onTap: _pickPhoto, child: inner),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: pal.gold,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _pickPhoto,
              child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.photo_camera, size: 18, color: pal.onGold)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chips(List<(String, String)> options, String value, ValueChanged<String> onChanged) =>
      ChoiceChips<String>(options: options, value: value, onChanged: onChanged);

  Widget _gap() => const SizedBox(height: 12);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(_editing ? Loc.t('Edit member', 'ممبر میں ترمیم') : Loc.t('New member', 'نیا ممبر')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            _photo(),
            if (_editing && (_photoB64 != null || !_photoRemoved))
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _photoB64 = null;
                    _photoRemoved = true;
                  }),
                  child: Text(Loc.t('Remove photo', 'تصویر ہٹائیں'), style: TextStyle(color: pal.muted, fontSize: 12)),
                ),
              ),
            SectionTitle(Loc.t('Basic info', 'بنیادی معلومات')),
            PCard(
              child: Column(children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: ThemeManager.field(Loc.t('Full name *', 'پورا نام *'), icon: Icons.person_outline),
                ),
                _gap(),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: ThemeManager.field(
                    Loc.t('Mobile / WhatsApp', 'موبائل / واٹس ایپ'),
                    icon: Icons.phone_outlined,
                    hint: '03001234567',
                    suffix: _mobile ? ContactPickButton(phone: _phone, name: _name, color: pal.gold) : null,
                  ),
                ),
                _gap(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: ThemeManager.field(Loc.t('Member ID', 'ممبر آئی ڈی'), icon: Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DateField(
                      label: Loc.t('Joining date', 'شمولیت کی تاریخ'),
                      value: _joined,
                      onChanged: (d) => setState(() => _joined = d),
                    ),
                  ),
                ]),
                _gap(),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _chips([
                    ('male', Loc.t('Male', 'مرد')),
                    ('female', Loc.t('Female', 'خاتون')),
                    ('other', Loc.t('Other', 'دیگر')),
                  ], _gender, (v) => setState(() => _gender = v)),
                ),
              ]),
            ),
            SectionTitle(Loc.t('Training', 'ٹریننگ')),
            PCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(Loc.t('Timing', 'وقت'), style: TextStyle(color: pal.muted, fontSize: 12.5)),
                const SizedBox(height: 6),
                _chips([
                  ('', Loc.t('Any', 'کوئی بھی')),
                  ('morning', Loc.t('Morning', 'صبح')),
                  ('evening', Loc.t('Evening', 'شام')),
                  ('ladies', Loc.t('Ladies time', 'خواتین کا وقت')),
                ], _timing, (v) => setState(() => _timing = v)),
                _gap(),
                DropdownButtonFormField<String>(
                  value: _goal,
                  isExpanded: true,
                  dropdownColor: pal.card,
                  decoration: ThemeManager.field(Loc.t('Goal', 'مقصد'), icon: Icons.flag_outlined),
                  items: [
                    for (final g in _goals)
                      DropdownMenuItem(value: g, child: Text(g.isEmpty ? Loc.t('Not set', 'نہیں بتایا') : g)),
                  ],
                  onChanged: (v) => setState(() => _goal = v ?? ''),
                ),
                _gap(),
                DropdownButtonFormField<String?>(
                  value: _trainers.any((t) => t.id == _trainerId) ? _trainerId : null,
                  isExpanded: true,
                  dropdownColor: pal.card,
                  decoration: ThemeManager.field(Loc.t('Trainer', 'ٹرینر'), icon: Icons.sports_gymnastics),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(Loc.t('No trainer', 'کوئی ٹرینر نہیں'))),
                    for (final t in _trainers) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() => _trainerId = v),
                ),
                _gap(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _height,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: ThemeManager.field(Loc.t('Height (cm)', 'قد (سینٹی میٹر)'), icon: Icons.height),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _blood,
                      isExpanded: true,
                      dropdownColor: pal.card,
                      decoration: ThemeManager.field(Loc.t('Blood group', 'بلڈ گروپ'), icon: Icons.bloodtype_outlined),
                      items: [for (final b in _bloods) DropdownMenuItem(value: b, child: Text(b.isEmpty ? '-' : b))],
                      onChanged: (v) => setState(() => _blood = v ?? ''),
                    ),
                  ),
                ]),
              ]),
            ),
            SectionTitle(Loc.t('More details (optional)', 'مزید تفصیل (اختیاری)')),
            PCard(
              child: Column(children: [
                TextField(
                  controller: _cnic,
                  keyboardType: TextInputType.number,
                  decoration: ThemeManager.field(Loc.t('CNIC', 'شناختی کارڈ'), icon: Icons.credit_card, hint: '35401-1234567-1'),
                ),
                _gap(),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dob ?? DateTime(2000, 1, 1),
                      firstDate: DateTime(1930),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _dob = DateTime.utc(d.year, d.month, d.day));
                  },
                  child: InputDecorator(
                    decoration: ThemeManager.field(Loc.t('Date of birth', 'تاریخ پیدائش'), icon: Icons.cake_outlined),
                    child: Text(_dob == null ? '-' : Fmt.dateOf(_dob!), style: TextStyle(color: pal.ink)),
                  ),
                ),
                _gap(),
                TextField(
                  controller: _address,
                  decoration: ThemeManager.field(Loc.t('Address', 'پتہ'), icon: Icons.home_outlined),
                ),
                _gap(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _emName,
                      decoration: ThemeManager.field(Loc.t('Emergency contact', 'ہنگامی رابطہ'), icon: Icons.emergency_outlined),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _emPhone,
                      keyboardType: TextInputType.phone,
                      decoration: ThemeManager.field(Loc.t('Their phone', 'ان کا فون'), icon: Icons.phone_in_talk_outlined),
                    ),
                  ),
                ]),
                _gap(),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: ThemeManager.field(Loc.t('Notes (injury, medical, etc.)', 'نوٹس (چوٹ، بیماری وغیرہ)'), icon: Icons.notes),
                ),
                if (_editing) ...[
                  _gap(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _status == 'active',
                    onChanged: (v) => setState(() => _status = v ? 'active' : 'inactive'),
                    title: Text(Loc.t('Active member', 'فعال ممبر'), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                    subtitle: Text(Loc.t('Turn off if the member left the gym', 'اگر ممبر جم چھوڑ گیا ہو تو بند کریں'),
                        style: TextStyle(color: pal.muted, fontSize: 12)),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 20),
            GoldButton(
              label: _editing ? Loc.t('SAVE CHANGES', 'تبدیلیاں محفوظ کریں') : Loc.t('SAVE & ADD MEMBERSHIP', 'محفوظ کریں اور ممبرشپ'),
              icon: Icons.check,
              busy: _busy,
              onPressed: _save,
            ),
          ]),
        ),
      ),
    );
  }
}
