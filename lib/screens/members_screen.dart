import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../db/user_repository.dart';
import '../models/models.dart';
import '../services/backup_service.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'member_form_screen.dart';
import 'member_profile_screen.dart';

enum MemberFilter { all, active, expiring, expired, dues, noPlan, inactive }

bool matchesFilter(MemberSummary s, MemberFilter f, int reminderDays) {
  final st = s.stateFor(reminderDays);
  return switch (f) {
    MemberFilter.all => st != MemberState.inactive,
    MemberFilter.active => st == MemberState.active || st == MemberState.expiring,
    MemberFilter.expiring => st == MemberState.expiring,
    MemberFilter.expired => st == MemberState.expired,
    MemberFilter.dues => s.dues > 0.5,
    MemberFilter.noPlan => st == MemberState.none,
    MemberFilter.inactive => st == MemberState.inactive,
  };
}

bool matchesText(MemberSummary s, String q) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return true;
  final m = s.member;
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  final phone = m.phone.replaceAll(RegExp(r'[^0-9]'), '');
  return m.name.toLowerCase().contains(t) ||
      m.code.toLowerCase().contains(t) ||
      (digits.length >= 3 && phone.contains(digits)) ||
      (digits.isNotEmpty && m.code.endsWith(digits.padLeft(4, '0'))) ||
      m.cnic.contains(t);
}

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> with AutoRefresh {
  List<MemberSummary>? _all;
  MemberFilter _filter = MemberFilter.all;
  String _q = '';
  bool _byExpiry = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final r = await MemberRepo.summaries();
    if (mounted) setState(() => _all = r);
  }

  List<MemberSummary> get _visible {
    final rd = GymSettings.reminderDays;
    final list = (_all ?? []).where((s) => matchesFilter(s, _filter, rd) && matchesText(s, _q)).toList();
    if (_byExpiry) {
      list.sort((a, b) => (a.endDate ?? '9999').compareTo(b.endDate ?? '9999'));
    }
    return list;
  }

  int _count(MemberFilter f) {
    final rd = GymSettings.reminderDays;
    return (_all ?? []).where((s) => matchesFilter(s, f, rd)).length;
  }

  Future<void> _exportCsv() async {
    final rows = _visible;
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final b = StringBuffer('Code,Name,Phone,CNIC,Gender,Joined,Plan,Valid Till,Days Left,Dues,Last Visit,Status\n');
    for (final s in rows) {
      final m = s.member;
      b.writeln([
        esc(m.code),
        esc(m.name),
        esc(m.phone),
        esc(m.cnic),
        esc(m.gender),
        esc(m.joinedOn ?? ''),
        esc(s.planName ?? ''),
        esc(s.endDate ?? ''),
        s.endDate == null ? '' : '${s.daysLeft}',
        s.dues.toStringAsFixed(0),
        esc(s.lastVisit ?? ''),
        esc(m.status),
      ].join(','));
    }
    final msg = await BackupService.shareText('members-${Fmt.todayYmd()}.csv', b.toString());
    if (mounted) toast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    final filters = <(MemberFilter, String)>[
      (MemberFilter.all, '${Loc.t('All', 'سب')} ${_count(MemberFilter.all)}'),
      (MemberFilter.active, '${Loc.t('Active', 'فعال')} ${_count(MemberFilter.active)}'),
      (MemberFilter.expiring, '${Loc.t('Expiring', 'ختم ہونے والے')} ${_count(MemberFilter.expiring)}'),
      (MemberFilter.expired, '${Loc.t('Expired', 'ختم شدہ')} ${_count(MemberFilter.expired)}'),
      (MemberFilter.dues, '${Loc.t('Dues', 'بقایا')} ${_count(MemberFilter.dues)}'),
      (MemberFilter.noPlan, '${Loc.t('No plan', 'بغیر پلان')} ${_count(MemberFilter.noPlan)}'),
      (MemberFilter.inactive, '${Loc.t('Inactive', 'غیر فعال')} ${_count(MemberFilter.inactive)}'),
    ];
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(
        Loc.t('Members', 'ممبرز'),
        subtitle: _all == null ? null : Loc.t('${list.length} shown', '${list.length} دکھائے گئے'),
        actions: [
          IconButton(
            tooltip: Loc.t('Sort by expiry', 'ختم ہونے کی ترتیب'),
            onPressed: () => setState(() => _byExpiry = !_byExpiry),
            icon: Icon(_byExpiry ? Icons.event_note : Icons.sort_by_alpha, color: pal.gold),
          ),
          if (Session.canManage)
            IconButton(
              tooltip: Loc.t('Export CSV (Excel)', 'CSV ایکسپورٹ'),
              onPressed: _exportCsv,
              icon: Icon(Icons.file_download_outlined, color: pal.muted),
            ),
          const SyncBadge(),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: pal.gold,
        foregroundColor: pal.onGold,
        onPressed: () => push(context, const MemberFormScreen()),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(Loc.t('New member', 'نیا ممبر'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v),
            decoration: ThemeManager.field(
              Loc.t('Search name, ID, phone, CNIC', 'نام، آئی ڈی، فون، شناختی کارڈ تلاش کریں'),
              icon: Icons.search,
              suffix: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, color: pal.muted),
                      onPressed: () => setState(() {
                        _search.clear();
                        _q = '';
                      }),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ChoiceChips<MemberFilter>(options: filters, value: _filter, onChanged: (f) => setState(() => _filter = f)),
        ),
        Expanded(
          child: _all == null
              ? Center(child: CircularProgressIndicator(color: pal.gold))
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.groups_outlined,
                      title: _all!.isEmpty ? Loc.t('No members yet', 'ابھی کوئی ممبر نہیں') : Loc.t('Nothing found', 'کچھ نہیں ملا'),
                      subtitle: _all!.isEmpty ? Loc.t('Add your first member to get started', 'پہلا ممبر شامل کریں') : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => MemberTile(s: list[i]),
                    ),
        ),
      ]),
    );
  }
}

class MemberTile extends StatelessWidget {
  final MemberSummary s;
  final VoidCallback? onTap;
  const MemberTile({super.key, required this.s, this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = s.member;
    return PCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap ?? () => push(context, MemberProfileScreen(memberId: m.id)),
      child: Row(children: [
        MemberAvatar(memberId: m.id, name: m.name, hasPhoto: s.hasPhoto),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(
              [m.code, if (s.planName != null) s.planName!, if (m.phone.isNotEmpty) m.phone].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatePill(s),
              if (s.dues > 0.5)
                Pill('${Loc.t('Due', 'بقایا')} ${Fmt.money(s.dues)}', color: pal.purple, soft: pal.purpleSoft),
            ]),
          ]),
        ),
        Icon(Icons.chevron_right, color: pal.muted),
      ]),
    );
  }
}

/// Member chunne ka sheet (fees / check-in ke liye). Cancel => null.
Future<MemberSummary?> pickMember(BuildContext context) {
  return showGymSheet<MemberSummary>(
    context,
    title: Loc.t('Select member', 'ممبر چنیں'),
    builder: (ctx) => const _MemberPicker(),
  );
}

class _MemberPicker extends StatefulWidget {
  const _MemberPicker();

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  List<MemberSummary> _all = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    MemberRepo.summaries().then((r) {
      if (mounted) setState(() => _all = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _all.where((s) => s.member.status != 'inactive' && matchesText(s, _q)).take(40).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _q = v),
        decoration: ThemeManager.field(Loc.t('Name, ID or phone', 'نام، آئی ڈی یا فون'), icon: Icons.search),
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(Loc.t('No member found', 'کوئی ممبر نہیں ملا'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
        ),
      for (final s in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MemberTile(s: s, onTap: () => Navigator.pop(context, s)),
        ),
      if (_all.isEmpty)
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            HomeShell.tab.value = 1;
          },
          child: Text(Loc.t('Add members first', 'پہلے ممبر شامل کریں'), style: TextStyle(color: pal.gold)),
        ),
    ]);
  }
}
