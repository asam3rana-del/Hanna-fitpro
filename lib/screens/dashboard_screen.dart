import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../db/user_repository.dart';
import '../models/models.dart';
import '../services/messaging.dart';
import '../services/session.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import '../widgets/watermark.dart';
import 'home_shell.dart';
import 'member_form_screen.dart';
import 'member_profile_screen.dart';
import 'members_screen.dart';
import 'products_screen.dart';
import 'membership_sheets.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with AutoRefresh {
  DashboardStats? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final s = await DashboardStats.load();
    if (mounted) setState(() => _s = s);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return Loc.t('Good morning', 'صبح بخیر');
    if (h < 17) return Loc.t('Good afternoon', 'سلام');
    return Loc.t('Good evening', 'شام بخیر');
  }

  Future<void> _collectFee() async {
    final m = await pickMember(context);
    if (m == null || !mounted) return;
    await showCollectPaymentSheet(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Stack(children: [
        SafeArea(
        child: s == null
            ? Center(child: CircularProgressIndicator(color: pal.gold))
            : RefreshIndicator(
                color: pal.gold,
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                  _hero(s),
                  SectionTitle(Loc.t('Today & this month', 'آج اور اس مہینے')),
                  _stats(s),
                  if (s.lowStock > 0 || s.expiringStock > 0) ...[
                    const SizedBox(height: 12),
                    PCard(
                      borderColor: pal.red.withValues(alpha: 0.5),
                      onTap: () => push(context, const ProductsScreen(alertsFirst: true)),
                      child: Row(children: [
                        Icon(Icons.inventory_2_outlined, color: pal.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            Loc.t('Counter stock: ${s.lowStock} low · ${s.expiringStock} expiring within 30 days',
                                'کاؤنٹر اسٹاک: ${s.lowStock} کم · ${s.expiringStock} کی ایکسپائری 30 دن میں'),
                            style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: pal.muted),
                      ]),
                    ),
                  ],
                  if (s.expiringList.isNotEmpty) ...[
                    SectionTitle(
                      Loc.t('Expiring soon', 'جلد ختم ہونے والی'),
                      trailing: TextButton(
                        onPressed: () => push(context, const RemindersScreen()),
                        child: Text(Loc.t('See all', 'سب دیکھیں'), style: TextStyle(color: pal.gold)),
                      ),
                    ),
                    PCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [for (final m in s.expiringList.take(6)) _memberRow(m, reminder: true)]),
                    ),
                  ],
                  SectionTitle(Loc.t("Today's check-ins (${s.todayCheckins})", 'آج کی حاضری (${s.todayCheckins})'),
                      trailing: TextButton(
                        onPressed: () => HomeShell.tab.value = 2,
                        child: Text(Loc.t('Check-in', 'حاضری'), style: TextStyle(color: pal.gold)),
                      )),
                  if (s.todayVisits.isEmpty)
                    PCard(
                      child: Row(children: [
                        Icon(Icons.door_front_door_outlined, color: pal.muted),
                        const SizedBox(width: 12),
                        Expanded(child: Text(Loc.t('No one has checked in yet today', 'آج ابھی کسی کی حاضری نہیں لگی'), style: TextStyle(color: pal.muted))),
                      ]),
                    )
                  else
                    PCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final a in s.todayVisits.take(8))
                          ListTile(
                            dense: true,
                            leading: MemberAvatar(memberId: a.memberId, name: a.memberName, hasPhoto: a.hasPhoto, size: 38),
                            title: Text(a.memberName, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                            subtitle: Text('${a.memberCode} · ${Fmt.time(a.checkIn)}${a.checkOut != null ? ' → ${Fmt.time(a.checkOut)}' : ''}',
                                style: TextStyle(color: pal.muted, fontSize: 12)),
                            trailing: a.checkOut == null
                                ? Pill(Loc.t('In gym', 'جم میں'), color: pal.green, soft: pal.greenSoft)
                                : Pill(Loc.t('Left', 'چلے گئے'), color: pal.muted, soft: pal.cardAlt),
                            onTap: () => push(context, MemberProfileScreen(memberId: a.memberId)),
                          ),
                      ]),
                    ),
                  if (s.duesList.isNotEmpty) ...[
                    SectionTitle(Loc.t('Pending dues', 'بقایا جات')),
                    PCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [for (final m in s.duesList.take(5)) _memberRow(m, dues: true)]),
                    ),
                  ],
                ]),
              ),
      ),
        // Gym ka banner halka sa poori screen par (Settings > Gym profile > Dashboard watermark).
        const Positioned.fill(child: GymWatermark()),
      ]),
    );
  }

  Widget _hero(DashboardStats s) => HeroHeader(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_greeting()}, ${Session.displayName.isEmpty ? '' : Session.displayName.split(' ').first}',
                    style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(GymSettings.gymName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.onHeader, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 2),
                Text(Fmt.dateOf(DateTime.now()), style: TextStyle(color: pal.onHeader.withValues(alpha: 0.6), fontSize: 12.5)),
              ]),
            ),
            const SyncBadge(),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            _heroNumber(Fmt.number(s.active), Loc.t('Active members', 'فعال ممبرز')),
            _heroNumber('${s.todayCheckins}', Loc.t('In today', 'آج آئے')),
            _heroNumber(Fmt.number(s.todayCash), Loc.t("Today's cash", 'آج کی آمدنی')),
          ]),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _heroAction(Icons.person_add_alt_1, Loc.t('New member', 'نیا ممبر'), () => push(context, const MemberFormScreen())),
            _heroAction(Icons.how_to_reg, Loc.t('Check-in', 'حاضری'), () => HomeShell.tab.value = 2),
            _heroAction(Icons.payments_outlined, Loc.t('Collect fee', 'فیس وصول'), _collectFee),
            _heroAction(Icons.storefront, Loc.t('Counter sale', 'کاؤنٹر سیل'), () => HomeShell.tab.value = 3),
          ]),
        ]),
      );

  Widget _heroNumber(String v, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v, style: TextStyle(color: pal.onHeader, fontSize: 26, fontWeight: FontWeight.w900)),
          ),
          Text(label, style: TextStyle(color: pal.onHeader.withValues(alpha: 0.6), fontSize: 12)),
        ]),
      );

  Widget _heroAction(IconData icon, String label, VoidCallback onTap) => Material(
        color: pal.gold,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: pal.onGold),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: pal.onGold, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );

  Widget _stats(DashboardStats s) {
    final cards = <Widget>[
      StatCard(
        icon: Icons.groups,
        label: Loc.t('Total members', 'کل ممبرز'),
        value: Fmt.number(s.totalMembers),
        hint: Loc.t('+${s.newThisMonth} new this month', 'اس مہینے +${s.newThisMonth} نئے'),
        color: pal.blue,
        soft: pal.blueSoft,
        onTap: () => HomeShell.tab.value = 1,
      ),
      StatCard(
        icon: Icons.timelapse,
        label: Loc.t('Expiring in ${GymSettings.reminderDays} days', '${GymSettings.reminderDays} دن میں ختم'),
        value: '${s.expiring}',
        color: pal.amber,
        soft: pal.amberSoft,
        onTap: () => push(context, const RemindersScreen()),
      ),
      StatCard(
        icon: Icons.event_busy,
        label: Loc.t('Expired', 'ختم شدہ'),
        value: '${s.expired}',
        color: pal.red,
        soft: pal.redSoft,
        onTap: () => push(context, const RemindersScreen(initialTab: 1)),
      ),
      StatCard(
        icon: Icons.account_balance_wallet_outlined,
        label: Loc.t('Pending dues', 'بقایا'),
        value: Fmt.money(s.totalDues),
        color: pal.purple,
        soft: pal.purpleSoft,
        onTap: () => push(context, const RemindersScreen(initialTab: 2)),
      ),
      StatCard(
        icon: Icons.storefront,
        label: Loc.t('Counter sale today', 'آج کاؤنٹر سیل'),
        value: Fmt.money(s.shopToday),
        hint: Loc.t('This month ${Fmt.money(s.shopMonth)}', 'اس مہینے ${Fmt.money(s.shopMonth)}'),
        color: pal.blue,
        soft: pal.blueSoft,
        onTap: () => HomeShell.tab.value = 3,
      ),
      StatCard(
        icon: Icons.payments,
        label: Loc.t('Fees collected this month', 'اس مہینے فیس وصولی'),
        value: Fmt.money(s.monthCollection),
        color: pal.green,
        soft: pal.greenSoft,
        onTap: () => HomeShell.tab.value = 4,
      ),
      if (Session.canManage)
        StatCard(
          icon: Icons.trending_up,
          label: Loc.t('Profit this month', 'اس مہینے منافع'),
          value: Fmt.money(s.monthProfit),
          hint: Loc.t('Fees + counter − expenses − stock', 'فیس + کاؤنٹر − اخراجات − اسٹاک'),
          color: pal.gold,
          soft: pal.goldSoft,
          onTap: () => push(context, const ReportsScreen()),
        ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final card in cards) SizedBox(width: w, child: card)]);
    });
  }

  Widget _memberRow(MemberSummary m, {bool reminder = false, bool dues = false}) => ListTile(
        leading: MemberAvatar(memberId: m.member.id, name: m.member.name, hasPhoto: m.hasPhoto, size: 40),
        title: Text(m.member.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
        subtitle: Text(
          dues ? '${m.member.code} · ${Loc.t('Due', 'بقایا')} ${Fmt.money(m.dues)}' : '${m.member.code} · ${m.planName ?? ''} · ${Fmt.date(m.endDate)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: pal.muted, fontSize: 12),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!dues) StatePill(m),
          IconButton(
            tooltip: 'WhatsApp',
            icon: Icon(Icons.chat_outlined, color: pal.green),
            onPressed: () => Messaging.whatsApp(context, m.member.phone, dues ? Messaging.duesText(m) : Messaging.reminderText(m)),
          ),
        ]),
        onTap: () => push(context, MemberProfileScreen(memberId: m.member.id)),
      );
}
