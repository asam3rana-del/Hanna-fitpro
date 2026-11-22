import 'dart:async';

import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../db/user_repository.dart';
import '../models/models.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'member_profile_screen.dart';
import 'membership_sheets.dart';

/// Reception: member ID / naam / phone likho (ya QR / barcode scanner se card scan karo) => check-in / check-out.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> with AutoRefresh {
  final _input = TextEditingController();
  final _focus = FocusNode();
  List<MemberSummary> _results = [];
  List<Attendance> _list = [];
  DateTime _day = Fmt.today();
  _Last? _last;
  Timer? _clearTimer;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final l = await AttendanceRepo.onDate(Fmt.ymd(_day));
    if (mounted) setState(() => _list = l);
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final r = await MemberRepo.search(v, limit: 8);
      if (mounted) setState(() => _results = r);
    });
  }

  /// Enter / scanner: code bilkul mile to seedha check-in.
  Future<void> _submit(String v) async {
    final t = v.trim();
    if (t.isEmpty) return;
    final r = await MemberRepo.search(t, limit: 8);
    if (!mounted) return;
    final exact = r.where((s) => s.member.code.toLowerCase() == t.toLowerCase()).toList();
    if (exact.length == 1) {
      await _mark(exact.first);
    } else if (r.length == 1) {
      await _mark(r.first);
    } else {
      setState(() => _results = r);
      if (r.isEmpty) toast(context, Loc.t('No member found for "$t"', '"$t" کا کوئی ممبر نہیں ملا'));
    }
  }

  Future<void> _mark(MemberSummary s) async {
    final inNow = await AttendanceRepo.toggle(s.member.id);
    _clearTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _last = _Last(s, inNow);
      _results = [];
      _input.clear();
      _day = Fmt.today();
    });
    _focus.requestFocus();
    _clearTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _last = null);
    });
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2015), lastDate: DateTime.now());
    if (d == null) return;
    setState(() => _day = DateTime.utc(d.year, d.month, d.day));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final inside = _list.where((a) => a.checkOut == null).length;
    final isToday = Fmt.ymd(_day) == Fmt.todayYmd();
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(
        Loc.t('Check-in', 'حاضری'),
        subtitle: isToday
            ? Loc.t('Today · ${_list.length} visits · $inside in gym', 'آج · ${_list.length} حاضریاں · $inside جم میں')
            : '${Fmt.dateOf(_day)} · ${_list.length}',
        actions: [
          IconButton(onPressed: _pickDay, icon: Icon(Icons.calendar_month_outlined, color: pal.gold)),
          const SyncBadge(),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            PCard(
              borderColor: pal.gold.withValues(alpha: 0.5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.qr_code_scanner, color: pal.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Loc.t('Type member ID / name / phone — or scan the member card', 'ممبر آئی ڈی / نام / فون لکھیں — یا کارڈ اسکین کریں'),
                      style: TextStyle(color: pal.muted, fontSize: 12.5),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _input,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                  style: TextStyle(color: pal.ink, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1),
                  decoration: ThemeManager.field(
                    Loc.t('Member ID e.g. ${GymSettings.memberPrefix}-0012 or 12', 'ممبر آئی ڈی مثلاً 12'),
                    icon: Icons.badge_outlined,
                    suffix: IconButton(
                      icon: Icon(Icons.arrow_forward, color: pal.gold),
                      onPressed: () => _submit(_input.text),
                    ),
                  ),
                ),
                for (final s in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: MemberAvatar(memberId: s.member.id, name: s.member.name, hasPhoto: s.hasPhoto, size: 40),
                    title: Text(s.member.name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                    subtitle: Text(s.member.code, style: TextStyle(color: pal.muted, fontSize: 12)),
                    trailing: StatePill(s),
                    onTap: () => _mark(s),
                  ),
              ]),
            ),
            if (_last != null) ...[const SizedBox(height: 14), _resultCard(_last!)],
            SectionTitle(isToday ? Loc.t("Today's attendance", 'آج کی حاضری') : Loc.t('Attendance', 'حاضری')),
            if (_list.isEmpty)
              EmptyState(icon: Icons.door_front_door_outlined, title: Loc.t('No check-ins', 'کوئی حاضری نہیں'))
            else
              PCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (final a in _list)
                    ListTile(
                      leading: MemberAvatar(memberId: a.memberId, name: a.memberName, hasPhoto: a.hasPhoto, size: 40),
                      title: Text(a.memberName, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${a.memberCode} · ${Loc.t('In', 'آمد')} ${Fmt.time(a.checkIn)}'
                        '${a.checkOut != null ? ' · ${Loc.t('Out', 'روانگی')} ${Fmt.time(a.checkOut)}' : ''}',
                        style: TextStyle(color: pal.muted, fontSize: 12),
                      ),
                      trailing: a.checkOut == null && isToday
                          ? TextButton(
                              onPressed: () => AttendanceRepo.toggle(a.memberId),
                              child: Text(Loc.t('Check out', 'چیک آؤٹ'), style: TextStyle(color: pal.gold)),
                            )
                          : Icon(Icons.check, color: pal.muted, size: 18),
                      onTap: () => push(context, MemberProfileScreen(memberId: a.memberId)),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _resultCard(_Last l) {
    final s = l.summary;
    final st = s.stateFor(GymSettings.reminderDays);
    final bad = st == MemberState.expired || st == MemberState.none || st == MemberState.inactive;
    final warnDues = s.dues > 0.5;
    final color = !l.checkedIn ? pal.blue : (bad ? pal.red : (warnDues || st == MemberState.expiring ? pal.amber : pal.green));
    return HeroHeader(
      child: Row(children: [
        MemberAvatar(memberId: s.member.id, name: s.member.name, hasPhoto: s.hasPhoto, size: 82),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(l.checkedIn ? Icons.login : Icons.logout, color: color),
              const SizedBox(width: 6),
              Text(
                l.checkedIn ? Loc.t('CHECKED IN', 'حاضری لگ گئی') : Loc.t('CHECKED OUT', 'چیک آؤٹ'),
                style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ]),
            const SizedBox(height: 4),
            Text(s.member.name, style: TextStyle(color: pal.onHeader, fontSize: 20, fontWeight: FontWeight.w900)),
            Text('${s.member.code} · ${s.planName ?? Loc.t('No plan', 'کوئی پلان نہیں')}',
                style: TextStyle(color: pal.onHeader.withValues(alpha: 0.65))),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatePill(s),
              if (warnDues) Pill('${Loc.t('Due', 'بقایا')} ${Fmt.money(s.dues)}', color: pal.amber, soft: pal.amberSoft),
            ]),
            if (bad || warnDues || st == MemberState.expiring) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => showNewMembershipSheet(context, s.member.id),
                  icon: const Icon(Icons.workspace_premium, size: 18),
                  label: Text(Loc.t('Renew', 'تجدید')),
                ),
                if (warnDues)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: pal.onHeader),
                    onPressed: () => showCollectPaymentSheet(context, s),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(Loc.t('Collect', 'وصول')),
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Last {
  final MemberSummary summary;
  final bool checkedIn;
  const _Last(this.summary, this.checkedIn);
}
