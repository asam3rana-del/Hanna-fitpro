import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../models/models.dart';
import '../services/messaging.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';

class TrainersScreen extends StatefulWidget {
  const TrainersScreen({super.key});

  @override
  State<TrainersScreen> createState() => _TrainersScreenState();
}

class _TrainersScreenState extends State<TrainersScreen> with AutoRefresh {
  List<Trainer>? _list;
  final Map<String, double> _ptThisMonth = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final l = await TrainerRepo.all();
    final t = Fmt.today();
    final from = Fmt.ymd(DateTime.utc(t.year, t.month, 1));
    final to = Fmt.ymd(DateTime.utc(t.year, t.month + 1, 0));
    final pt = <String, double>{};
    for (final tr in l) {
      pt[tr.id] = await TrainerRepo.ptRevenue(tr.id, from, to);
    }
    if (!mounted) return;
    setState(() {
      _list = l;
      _ptThisMonth
        ..clear()
        ..addAll(pt);
    });
  }

  Future<void> _edit([Trainer? t]) async {
    final name = TextEditingController(text: t?.name ?? '');
    final phone = TextEditingController(text: t?.phone ?? '');
    final spec = TextEditingController(text: t?.specialty ?? '');
    final salary = TextEditingController(text: (t == null || t.salary == 0) ? '' : t.salary.toStringAsFixed(0));
    final comm = TextEditingController(text: (t == null || t.commissionPct == 0) ? '' : Fmt.decimal(t.commissionPct));
    final notes = TextEditingController(text: t?.notes ?? '');
    var active = t?.active ?? true;
    await showGymSheet<void>(
      context,
      title: t == null ? Loc.t('New trainer', 'نیا ٹرینر') : Loc.t('Edit trainer', 'ٹرینر میں ترمیم'),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: ThemeManager.field(Loc.t('Name', 'نام'), icon: Icons.person_outline),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: ThemeManager.field(Loc.t('Phone', 'فون'), icon: Icons.phone_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: spec,
            decoration: ThemeManager.field(Loc.t('Speciality (e.g. Strength, Cardio, Ladies)', 'مہارت (مثلاً طاقت، کارڈیو)'),
                icon: Icons.star_outline),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: salary,
                keyboardType: TextInputType.number,
                decoration: ThemeManager.field(Loc.t('Monthly salary', 'ماہانہ تنخواہ'), icon: Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: comm,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: ThemeManager.field(Loc.t('PT commission %', 'PT کمیشن %'), icon: Icons.percent),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: notes, decoration: ThemeManager.field(Loc.t('Notes', 'نوٹس'), icon: Icons.notes)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: active,
            onChanged: (v) => setSheet(() => active = v),
            title: Text(Loc.t('Active', 'فعال'), style: TextStyle(color: pal.ink)),
          ),
          const SizedBox(height: 10),
          GoldButton(
            label: Loc.t('SAVE', 'محفوظ کریں'),
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final tr = Trainer(
                id: t?.id ?? '',
                name: name.text.trim(),
                phone: phone.text.trim(),
                specialty: spec.text.trim(),
                salary: Fmt.toDouble(salary.text),
                commissionPct: Fmt.toDouble(comm.text),
                active: active,
                notes: notes.text.trim(),
              );
              if (t == null) {
                await TrainerRepo.create(tr);
              } else {
                await TrainerRepo.save(tr);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          if (t != null && Session.canManage) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final ok = await confirm(ctx, Loc.t('Delete trainer?', 'ٹرینر مٹائیں؟'), t!.name, danger: true);
                if (!ok) return;
                await TrainerRepo.delete(t!.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: Icon(Icons.delete_outline, color: pal.red),
              label: Text(Loc.t('Delete', 'مٹائیں'), style: TextStyle(color: pal.red)),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Trainers', 'ٹرینرز')),
      floatingActionButton: Session.canManage
          ? FloatingActionButton.extended(
              backgroundColor: pal.gold,
              foregroundColor: pal.onGold,
              onPressed: () => _edit(),
              icon: const Icon(Icons.person_add_alt),
              label: Text(Loc.t('Add trainer', 'ٹرینر شامل کریں'), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: list == null
          ? Center(child: CircularProgressIndicator(color: pal.gold))
          : list.isEmpty
              ? EmptyState(
                  icon: Icons.sports_gymnastics,
                  title: Loc.t('No trainers yet', 'ابھی کوئی ٹرینر نہیں'),
                  subtitle: Loc.t('Add trainers to assign members and track PT commission', 'ممبرز دینے اور PT کمیشن کے لیے ٹرینر شامل کریں'),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  for (final t in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: PCard(
                        onTap: Session.canManage ? () => _edit(t) : null,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: pal.purpleSoft, shape: BoxShape.circle),
                            child: Text(Fmt.initials(t.name), style: TextStyle(color: pal.purple, fontWeight: FontWeight.w900)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text(t.name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800, fontSize: 15.5)),
                                ),
                                if (!t.active) Pill(Loc.t('Inactive', 'غیر فعال'), color: pal.muted, soft: pal.cardAlt),
                              ]),
                              if (t.specialty.isNotEmpty) Text(t.specialty, style: TextStyle(color: pal.gold, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                Pill(Loc.t('${t.memberCount} members', '${t.memberCount} ممبرز'), color: pal.blue, soft: pal.blueSoft),
                                if (Session.canManage && t.salary > 0)
                                  Pill('${Loc.t('Salary', 'تنخواہ')} ${Fmt.money(t.salary)}', color: pal.ink, soft: pal.cardAlt),
                                if (Session.canManage && t.commissionPct > 0)
                                  Pill(
                                    '${Loc.t('PT commission', 'PT کمیشن')} ${Fmt.money((_ptThisMonth[t.id] ?? 0) * t.commissionPct / 100)}',
                                    color: pal.purple,
                                    soft: pal.purpleSoft,
                                  ),
                              ]),
                            ]),
                          ),
                          if (t.phone.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.call_outlined, color: pal.green),
                              onPressed: () => Messaging.call(context, t.phone),
                            ),
                        ]),
                      ),
                    ),
                ]),
    );
  }
}
