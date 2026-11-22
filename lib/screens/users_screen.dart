import 'package:flutter/material.dart';

import '../db/user_repository.dart';
import '../models/models.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';

/// Staff logins: Owner / Manager / Reception.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with AutoRefresh {
  List<AppUser>? _users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final u = await UserRepository.instance.all();
    if (mounted) setState(() => _users = u);
  }

  List<(String, String)> get _roles => [
        ('admin', Loc.t('Owner / Admin', 'مالک / ایڈمن')),
        ('manager', Loc.t('Manager', 'مینیجر')),
        ('reception', Loc.t('Reception', 'ریسپشن')),
      ];

  Future<void> _add() async {
    final user = TextEditingController();
    final name = TextEditingController();
    final pass = TextEditingController();
    var role = 'reception';
    await showGymSheet<void>(
      context,
      title: Loc.t('New staff login', 'نیا اسٹاف لاگ اِن'),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, decoration: ThemeManager.field(Loc.t('Full name', 'پورا نام'), icon: Icons.badge_outlined)),
          const SizedBox(height: 10),
          TextField(controller: user, decoration: ThemeManager.field(Loc.t('Username', 'یوزر نیم'), icon: Icons.person_outline)),
          const SizedBox(height: 10),
          TextField(
            controller: pass,
            obscureText: true,
            decoration: ThemeManager.field(Loc.t('Password (min 4)', 'پاس ورڈ (کم از کم 4)'), icon: Icons.lock_outline),
          ),
          const SizedBox(height: 12),
          ChoiceChips<String>(options: _roles, value: role, onChanged: (v) => setSheet(() => role = v)),
          const SizedBox(height: 8),
          Text(
            Loc.t('Reception: members, check-in, fees. Manager: + reports & expenses. Owner: everything.',
                'ریسپشن: ممبرز، حاضری، فیس۔ مینیجر: + رپورٹس اور اخراجات۔ مالک: سب کچھ۔'),
            style: TextStyle(color: pal.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: Loc.t('CREATE LOGIN', 'لاگ اِن بنائیں'),
            onPressed: () async {
              final u = user.text.trim();
              if (u.isEmpty || pass.text.length < 4) {
                toast(ctx, Loc.t('Username and 4+ character password needed', 'یوزر نیم اور 4+ حروف کا پاس ورڈ چاہیے'));
                return;
              }
              if (await UserRepository.instance.find(u) != null) {
                if (ctx.mounted) toast(ctx, Loc.t('Username already exists', 'یہ یوزر نیم پہلے سے موجود ہے'));
                return;
              }
              await UserRepository.instance.create(username: u, displayName: name.text, password: pass.text, role: role);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _changePassword(AppUser u) async {
    final pass = TextEditingController();
    await showGymSheet<void>(
      context,
      title: Loc.t('New password for ${u.username}', '${u.username} کا نیا پاس ورڈ'),
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: pass,
          obscureText: true,
          autofocus: true,
          decoration: ThemeManager.field(Loc.t('New password', 'نیا پاس ورڈ'), icon: Icons.lock_reset),
        ),
        const SizedBox(height: 16),
        GoldButton(
          label: Loc.t('SAVE', 'محفوظ کریں'),
          onPressed: () async {
            if (pass.text.length < 4) return;
            await UserRepository.instance.setPassword(u.username, pass.text);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ]),
    );
  }

  Future<void> _toggleActive(AppUser u) async {
    if (u.active && u.role == 'admin' && await UserRepository.instance.activeAdminCount() <= 1) {
      if (mounted) toast(context, Loc.t('At least one owner/admin must stay active', 'کم از کم ایک مالک/ایڈمن فعال رہنا چاہیے'));
      return;
    }
    if (u.username.toLowerCase() == (Session.username ?? '').toLowerCase()) {
      if (mounted) toast(context, Loc.t("You can't disable yourself", 'آپ خود کو بند نہیں کر سکتے'));
      return;
    }
    await UserRepository.instance.setActive(u.username, !u.active);
  }

  Future<void> _setRole(AppUser u, String role) async {
    if (u.role == 'admin' && role != 'admin' && await UserRepository.instance.activeAdminCount() <= 1) {
      if (mounted) toast(context, Loc.t('At least one owner/admin is needed', 'کم از کم ایک مالک/ایڈمن ضروری ہے'));
      return;
    }
    await UserRepository.instance.setRole(u.username, role);
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Staff Logins', 'اسٹاف لاگ اِن')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: pal.gold,
        foregroundColor: pal.onGold,
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: Text(Loc.t('Add login', 'لاگ اِن شامل کریں'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: users == null
          ? Center(child: CircularProgressIndicator(color: pal.gold))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              for (final u in users)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PCard(
                    child: Row(children: [
                      Icon(
                        u.role == 'admin' ? Icons.workspace_premium : (u.role == 'manager' ? Icons.manage_accounts : Icons.person),
                        color: u.active ? pal.gold : pal.muted,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(u.displayName,
                              style: TextStyle(
                                  color: u.active ? pal.ink : pal.muted,
                                  fontWeight: FontWeight.w800,
                                  decoration: u.active ? null : TextDecoration.lineThrough)),
                          Text('@${u.username} · ${Session.roleLabel(u.role)}', style: TextStyle(color: pal.muted, fontSize: 12.5)),
                        ]),
                      ),
                      PopupMenuButton<String>(
                        color: pal.card,
                        icon: Icon(Icons.more_vert, color: pal.muted),
                        onSelected: (v) {
                          if (v == 'pass') _changePassword(u);
                          if (v == 'active') _toggleActive(u);
                          if (v.startsWith('role:')) _setRole(u, v.substring(5));
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'pass', child: Text(Loc.t('Change password', 'پاس ورڈ بدلیں'))),
                          for (final r in _roles)
                            if (r.$1 != u.role) PopupMenuItem(value: 'role:${r.$1}', child: Text('${Loc.t('Make', 'بنائیں')}: ${r.$2}')),
                          PopupMenuItem(
                            value: 'active',
                            child: Text(u.active ? Loc.t('Disable login', 'لاگ اِن بند کریں') : Loc.t('Enable login', 'لاگ اِن کھولیں')),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
