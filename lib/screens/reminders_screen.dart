import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../db/user_repository.dart';
import '../models/models.dart';
import '../services/messaging.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'member_profile_screen.dart';
import 'membership_sheets.dart';

/// WhatsApp reminders: jald khatam hone wali, khatam ho chuki, aur baqaya wali memberships.
class RemindersScreen extends StatefulWidget {
  final int initialTab;
  const RemindersScreen({super.key, this.initialTab = 0});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> with AutoRefresh {
  /// Is session mein jinhein message bhej diya (nishan ke liye).
  static final Set<String> _sent = {};

  List<MemberSummary>? _all;
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final r = await MemberRepo.summaries();
    if (mounted) setState(() => _all = r);
  }

  List<MemberSummary> _items() {
    final rd = GymSettings.reminderDays;
    final all = (_all ?? []).where((s) => s.member.status != 'inactive').toList();
    switch (_tab) {
      case 1:
        // Pichhle 60 din mein khatam hui (purane chhor gaye members se pareshani na ho).
        final l = all.where((s) => s.stateFor(rd) == MemberState.expired && s.daysLeft >= -60).toList()
          ..sort((a, b) => b.daysLeft.compareTo(a.daysLeft));
        return l;
      case 2:
        final l = all.where((s) => s.dues > 0.5).toList()..sort((a, b) => b.dues.compareTo(a.dues));
        return l;
      default:
        final l = all.where((s) => s.stateFor(rd) == MemberState.expiring).toList()
          ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
        return l;
    }
  }

  Future<void> _send(MemberSummary s) async {
    final text = _tab == 2 ? Messaging.duesText(s) : Messaging.reminderText(s);
    await Messaging.whatsApp(context, s.member.phone, text);
    if (mounted) setState(() => _sent.add('${_tab}_${s.member.id}'));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final rd = GymSettings.reminderDays;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Reminders', 'یاد دہانی'),
          subtitle: Loc.t('Tap WhatsApp to send a ready message', 'تیار پیغام بھیجنے کے لیے واٹس ایپ دبائیں')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: ChoiceChips<int>(
                options: [
                  (0, Loc.t('Expiring ($rd days)', 'ختم ہونے والی ($rd دن)')),
                  (1, Loc.t('Expired', 'ختم شدہ')),
                  (2, Loc.t('Dues', 'بقایا')),
                ],
                value: _tab,
                onChanged: (v) => setState(() => _tab = v),
              ),
            ),
            Expanded(
              child: _all == null
                  ? Center(child: CircularProgressIndicator(color: pal.gold))
                  : items.isEmpty
                      ? EmptyState(icon: Icons.verified_outlined, title: Loc.t('All clear 🎉', 'سب ٹھیک ہے 🎉'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final s = items[i];
                            final sent = _sent.contains('${_tab}_${s.member.id}');
                            return PCard(
                              padding: const EdgeInsets.all(12),
                              onTap: () => push(context, MemberProfileScreen(memberId: s.member.id)),
                              child: Row(children: [
                                MemberAvatar(memberId: s.member.id, name: s.member.name, hasPhoto: s.hasPhoto, size: 44),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(s.member.name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                                    Text(
                                      _tab == 2
                                          ? '${s.member.code} · ${Loc.t('Due', 'بقایا')} ${Fmt.money(s.dues)}'
                                          : '${s.member.code} · ${s.planName ?? ''} · ${Fmt.date(s.endDate)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: pal.muted, fontSize: 12),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(spacing: 6, children: [
                                      if (_tab != 2) StatePill(s),
                                      if (sent) Pill(Loc.t('Sent', 'بھیج دیا'), color: pal.green, soft: pal.greenSoft, icon: Icons.done_all),
                                      if (s.member.phone.isEmpty) Pill(Loc.t('No phone', 'فون نہیں'), color: pal.red, soft: pal.redSoft),
                                    ]),
                                  ]),
                                ),
                                if (_tab != 2)
                                  IconButton(
                                    tooltip: Loc.t('Renew', 'تجدید'),
                                    icon: Icon(Icons.workspace_premium_outlined, color: pal.gold),
                                    onPressed: () => showNewMembershipSheet(context, s.member.id),
                                  ),
                                if (s.member.phone.isNotEmpty) ...[
                                  IconButton(
                                    tooltip: Loc.t('Call', 'کال'),
                                    icon: Icon(Icons.call_outlined, color: pal.blue),
                                    onPressed: () => Messaging.call(context, s.member.phone),
                                  ),
                                  IconButton(
                                    tooltip: 'WhatsApp',
                                    icon: Icon(Icons.chat, color: pal.green),
                                    onPressed: () => _send(s),
                                  ),
                                ],
                              ]),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ),
    );
  }
}
