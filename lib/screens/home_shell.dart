import 'package:flutter/material.dart';

import '../app_info.dart';
import '../db/user_repository.dart';
import '../services/session.dart';
import '../sync/gym_sync.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'checkin_screen.dart';
import 'cloud_setup_screen.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'login_screen.dart';
import 'members_screen.dart';
import 'payments_screen.dart';
import 'plans_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'trainers_screen.dart';
import 'users_screen.dart';

/// Main dhancha: phone par neeche tabs, PC / tablet par baayen taraf sidebar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Kisi bhi screen se tab badalne ke liye (0 dashboard, 1 members, 2 check-in, 3 fees, 4 more).
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    HomeShell.tab.value = 0;
  }

  List<(IconData, IconData, String)> get _items => [
        (Icons.space_dashboard_outlined, Icons.space_dashboard, Loc.t('Dashboard', 'ڈیش بورڈ')),
        (Icons.groups_outlined, Icons.groups, Loc.t('Members', 'ممبرز')),
        (Icons.how_to_reg_outlined, Icons.how_to_reg, Loc.t('Check-in', 'حاضری')),
        (Icons.payments_outlined, Icons.payments, Loc.t('Fees', 'فیس')),
        (Icons.grid_view_outlined, Icons.grid_view, Loc.t('More', 'مزید')),
      ];

  Widget _page(int i) {
    switch (i) {
      case 1:
        return const MembersScreen();
      case 2:
        return const CheckInScreen();
      case 3:
        return const PaymentsScreen();
      case 4:
        return const MoreScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HomeShell.tab,
      builder: (context, index, _) {
        final body = KeyedSubtree(key: ValueKey(index), child: _page(index));
        if (isWide(context)) {
          return Scaffold(
            backgroundColor: pal.bg,
            body: Row(children: [
              _SideBar(index: index, items: _items),
              VerticalDivider(width: 1, color: pal.border),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          backgroundColor: pal.bg,
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            backgroundColor: pal.card,
            indicatorColor: pal.goldSoft,
            surfaceTintColor: Colors.transparent,
            height: 66,
            onDestinationSelected: (i) => HomeShell.tab.value = i,
            destinations: [
              for (final it in _items)
                NavigationDestination(
                  icon: Icon(it.$1, color: pal.muted),
                  selectedIcon: Icon(it.$2, color: pal.gold),
                  label: it.$3,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SideBar extends StatelessWidget {
  final int index;
  final List<(IconData, IconData, String)> items;
  const _SideBar({required this.index, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: pal.card,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Row(children: [
              const GymLogo(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(GymSettings.gymName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900, fontSize: 15.5)),
                  Text(AppInfo.tagline, style: TextStyle(color: pal.gold, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: pal.border),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Material(
                color: i == index ? pal.goldSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => HomeShell.tab.value = i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(children: [
                      Icon(i == index ? items[i].$2 : items[i].$1, color: i == index ? pal.gold : pal.muted, size: 22),
                      const SizedBox(width: 14),
                      Text(items[i].$3,
                          style: TextStyle(
                              color: i == index ? pal.ink : pal.muted,
                              fontWeight: i == index ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ),
          const Spacer(),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SyncBadge(expanded: true)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Row(children: [
              Icon(Icons.account_circle_outlined, color: pal.muted, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${Session.displayName} · ${Session.roleLabel(Session.role)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Sync ka chhota nishan (tap = abhi sync).
class SyncBadge extends StatelessWidget {
  final bool expanded;
  const SyncBadge({super.key, this.expanded = false});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncStatus>(
        valueListenable: GymSync.instance.status,
        builder: (context, s, _) {
          final color = s.running ? pal.blue : (s.ok ? pal.green : pal.red);
          final icon = s.running ? Icons.sync : (s.ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined);
          Future<void> tap() async {
            final configured = await GymSync.isConfigured();
            if (!context.mounted) return;
            if (!configured) {
              if (Session.isAdmin) push(context, const CloudSetupScreen());
              return;
            }
            final m = await GymSync.instance.syncNow();
            if (context.mounted) toast(context, m);
          }

          if (!expanded) {
            return IconButton(tooltip: s.message, onPressed: tap, icon: Icon(icon, color: color));
          }
          return Material(
            color: pal.cardAlt,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: tap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.message.isEmpty ? Loc.t('Online sync', 'آن لائن سنک') : s.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.muted, fontSize: 11.5),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

/// "More" — baqi saare hisse.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await confirm(context, Loc.t('Logout?', 'لاگ آؤٹ؟'), Loc.t('You will need your password to log in again.', 'دوبارہ لاگ اِن کے لیے پاس ورڈ چاہیے ہو گا۔'));
    if (!ok) return;
    await Session.clear();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <(IconData, String, String, Color, Color, VoidCallback)>[
      (Icons.notifications_active_outlined, Loc.t('Reminders', 'یاد دہانی'), Loc.t('Expiring · expired · dues', 'ختم ہونے والے · بقایا'),
          pal.amber, pal.amberSoft, () => push(context, const RemindersScreen())),
      (Icons.workspace_premium_outlined, Loc.t('Plans & Packages', 'پلان اور پیکج'), Loc.t('Monthly, yearly, PT…', 'ماہانہ، سالانہ، PT…'),
          pal.gold, pal.goldSoft, () => push(context, const PlansScreen())),
      (Icons.sports_gymnastics, Loc.t('Trainers', 'ٹرینرز'), Loc.t('Staff, PT, commission', 'اسٹاف، PT، کمیشن'),
          pal.purple, pal.purpleSoft, () => push(context, const TrainersScreen())),
      if (Session.canManage)
        (Icons.receipt_long_outlined, Loc.t('Expenses', 'اخراجات'), Loc.t('Rent, bills, salaries', 'کرایہ، بل، تنخواہ'),
            pal.red, pal.redSoft, () => push(context, const ExpensesScreen())),
      if (Session.canManage)
        (Icons.insights_outlined, Loc.t('Reports', 'رپورٹس'), Loc.t('Revenue, profit, trends', 'آمدنی، منافع، رجحان'),
            pal.green, pal.greenSoft, () => push(context, const ReportsScreen())),
      if (Session.isAdmin)
        (Icons.manage_accounts_outlined, Loc.t('Staff Logins', 'اسٹاف لاگ اِن'), Loc.t('Users & roles', 'یوزرز اور رولز'),
            pal.blue, pal.blueSoft, () => push(context, const UsersScreen())),
      (Icons.settings_outlined, Loc.t('Settings', 'سیٹنگز'), Loc.t('Gym profile, backup, sync', 'جم پروفائل، بیک اپ، سنک'),
          pal.muted, pal.cardAlt, () => push(context, const SettingsScreen())),
    ];
    final cols = MediaQuery.sizeOf(context).width >= 1100 ? 3 : (MediaQuery.sizeOf(context).width >= 600 ? 2 : 1);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('More', 'مزید'), actions: const [SyncBadge(), SizedBox(width: 6)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 1 ? 4.2 : 3.2,
          children: [
            for (final t in tiles)
              PCard(
                onTap: t.$6,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: t.$5, borderRadius: BorderRadius.circular(14)),
                    child: Icon(t.$1, color: t.$4),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                      Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: pal.muted),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 18),
        PCard(
          child: Row(children: [
            Icon(Icons.account_circle, color: pal.gold, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Session.displayName, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                Text(Session.roleLabel(Session.role), style: TextStyle(color: pal.muted, fontSize: 12)),
              ]),
            ),
            OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: Icon(Icons.logout, color: pal.red),
              label: Text(Loc.t('Logout', 'لاگ آؤٹ'), style: TextStyle(color: pal.red)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text('${AppInfo.appName} · ${AppInfo.business}',
              style: TextStyle(color: pal.muted, fontSize: 12)),
        ),
      ]),
    );
  }
}
