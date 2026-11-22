import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../models/models.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';

String durationLabel(Plan p) {
  final v = p.durationValue;
  switch (p.durationUnit) {
    case 'day':
      return v == 1 ? Loc.t('1 day', '1 دن') : Loc.t('$v days', '$v دن');
    case 'week':
      return v == 1 ? Loc.t('1 week', '1 ہفتہ') : Loc.t('$v weeks', '$v ہفتے');
    case 'year':
      return v == 1 ? Loc.t('1 year', '1 سال') : Loc.t('$v years', '$v سال');
    default:
      return v == 1 ? Loc.t('1 month', '1 مہینہ') : Loc.t('$v months', '$v مہینے');
  }
}

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> with AutoRefresh {
  List<Plan>? _plans;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final p = await PlanRepo.all();
    if (mounted) setState(() => _plans = p);
  }

  Future<void> _edit([Plan? plan]) async {
    final name = TextEditingController(text: plan?.name ?? '');
    final value = TextEditingController(text: '${plan?.durationValue ?? 1}');
    final price = TextEditingController(text: plan == null ? '' : plan.price.toStringAsFixed(0));
    final desc = TextEditingController(text: plan?.description ?? '');
    var unit = plan?.durationUnit ?? 'month';
    var kind = plan?.kind ?? 'gym';
    var active = plan?.active ?? true;
    await showGymSheet<void>(
      context,
      title: plan == null ? Loc.t('New plan', 'نیا پلان') : Loc.t('Edit plan', 'پلان میں ترمیم'),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: ThemeManager.field(Loc.t('Plan name (e.g. Monthly)', 'پلان کا نام (مثلاً ماہانہ)'), icon: Icons.workspace_premium_outlined),
          ),
          const SizedBox(height: 12),
          ChoiceChips<String>(
            options: [('gym', Loc.t('Gym membership', 'جم ممبرشپ')), ('pt', Loc.t('Personal training', 'پرسنل ٹریننگ'))],
            value: kind,
            onChanged: (v) => setSheet(() => kind = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration: ThemeManager.field(Loc.t('Length', 'مدت')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChoiceChips<String>(
                options: [
                  ('day', Loc.t('Days', 'دن')),
                  ('week', Loc.t('Weeks', 'ہفتے')),
                  ('month', Loc.t('Months', 'مہینے')),
                  ('year', Loc.t('Years', 'سال')),
                ],
                value: unit,
                onChanged: (v) => setSheet(() => unit = v),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: ThemeManager.field(Loc.t('Price', 'قیمت'), icon: Icons.sell_outlined, prefixText: '${Fmt.currency} '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: desc,
            decoration: ThemeManager.field(Loc.t('Description (optional)', 'تفصیل (اختیاری)'), icon: Icons.notes),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: active,
            onChanged: (v) => setSheet(() => active = v),
            title: Text(Loc.t('Available for new members', 'نئے ممبرز کے لیے دستیاب'), style: TextStyle(color: pal.ink)),
          ),
          const SizedBox(height: 10),
          GoldButton(
            label: Loc.t('SAVE PLAN', 'پلان محفوظ کریں'),
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final p = Plan(
                id: plan?.id ?? '',
                name: name.text.trim(),
                kind: kind,
                durationValue: Fmt.toInt(value.text) < 1 ? 1 : Fmt.toInt(value.text),
                durationUnit: unit,
                price: Fmt.toDouble(price.text),
                description: desc.text.trim(),
                active: active,
                sort: plan?.sort ?? ((_plans?.length ?? 0) + 1),
              );
              if (plan == null) {
                await PlanRepo.create(p);
              } else {
                await PlanRepo.save(p);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          if (plan != null && Session.canManage) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final ok = await confirm(ctx, Loc.t('Delete plan?', 'پلان مٹائیں؟'),
                    Loc.t('Old memberships keep their plan name.', 'پرانی ممبرشپ میں پلان کا نام رہے گا۔'),
                    danger: true);
                if (!ok) return;
                await PlanRepo.delete(plan!.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: Icon(Icons.delete_outline, color: pal.red),
              label: Text(Loc.t('Delete plan', 'پلان مٹائیں'), style: TextStyle(color: pal.red)),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Plans & Packages', 'پلان اور پیکج')),
      floatingActionButton: Session.canManage
          ? FloatingActionButton.extended(
              backgroundColor: pal.gold,
              foregroundColor: pal.onGold,
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(Loc.t('New plan', 'نیا پلان'), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: plans == null
          ? Center(child: CircularProgressIndicator(color: pal.gold))
          : plans.isEmpty
              ? EmptyState(icon: Icons.workspace_premium_outlined, title: Loc.t('No plans yet', 'ابھی کوئی پلان نہیں'))
              : LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
                  final w = (c.maxWidth - 32 - (cols - 1) * 12) / cols;
                  return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final p in plans)
                        SizedBox(
                          width: w,
                          child: PCard(
                            onTap: Session.canManage ? () => _edit(p) : null,
                            borderColor: p.active ? pal.gold.withValues(alpha: 0.45) : pal.border,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(p.kind == 'pt' ? Icons.sports_gymnastics : Icons.workspace_premium,
                                    color: p.kind == 'pt' ? pal.purple : pal.gold),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(p.name,
                                      style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800, fontSize: 15.5)),
                                ),
                                if (!p.active) Pill(Loc.t('Hidden', 'چھپا'), color: pal.muted, soft: pal.cardAlt),
                              ]),
                              const SizedBox(height: 10),
                              Text(Fmt.money(p.price), style: TextStyle(color: pal.ink, fontSize: 24, fontWeight: FontWeight.w900)),
                              Text(durationLabel(p), style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700)),
                              if (p.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(p.description, style: TextStyle(color: pal.muted, fontSize: 12.5)),
                              ],
                            ]),
                          ),
                        ),
                    ]),
                  ]);
                }),
    );
  }
}
