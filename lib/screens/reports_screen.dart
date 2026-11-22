import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';

/// Mahine ki report: aamdani, kharcha, munafa, 6 mahine ka rujhan, plan / tareeqa / kharche ki tafseel.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with AutoRefresh {
  DateTime _month = DateTime.utc(Fmt.today().year, Fmt.today().month, 1);
  MonthReport? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final r = await MonthReport.load(_month);
    if (mounted) setState(() => _r = r);
  }

  void _shift(int m) {
    setState(() {
      _month = Fmt.addMonths(_month, m);
      _r = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Reports', 'رپورٹس')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: Icon(Icons.chevron_left, color: pal.ink)),
              Expanded(
                child: Text(Fmt.monthLabel(_month),
                    textAlign: TextAlign.center, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              IconButton(onPressed: () => _shift(1), icon: Icon(Icons.chevron_right, color: pal.ink)),
            ]),
            const SizedBox(height: 8),
            if (r == null)
              Padding(padding: const EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: pal.gold)))
            else ...[
              HeroHeader(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Loc.t('Net profit', 'خالص منافع'), style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(Fmt.money(r.profit),
                      style: TextStyle(color: r.profit >= 0 ? pal.onHeader : pal.red, fontSize: 32, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  Row(children: [
                    _mini(Loc.t('Revenue', 'آمدنی'), Fmt.money(r.revenue), pal.green),
                    _mini(Loc.t('Expenses', 'اخراجات'), Fmt.money(r.expenses), pal.red),
                    _mini(Loc.t('Margin', 'مارجن'),
                        r.revenue <= 0 ? '-' : '${(r.profit / r.revenue * 100).toStringAsFixed(0)}%', pal.gold),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 800 ? 4 : 2;
                final w = (c.maxWidth - (cols - 1) * 12) / cols;
                final cards = [
                  StatCard(icon: Icons.person_add_alt_1, label: Loc.t('New members', 'نئے ممبرز'), value: '${r.newMembers}', color: pal.blue, soft: pal.blueSoft),
                  StatCard(icon: Icons.autorenew, label: Loc.t('Memberships sold', 'فروخت شدہ ممبرشپ'), value: '${r.renewals}', color: pal.gold, soft: pal.goldSoft),
                  StatCard(icon: Icons.how_to_reg, label: Loc.t('Total visits', 'کل حاضری'), value: Fmt.number(r.visits), color: pal.green, soft: pal.greenSoft),
                  StatCard(icon: Icons.people_alt_outlined, label: Loc.t('Unique visitors', 'مختلف ممبرز'), value: '${r.uniqueVisitors}', color: pal.purple, soft: pal.purpleSoft),
                ];
                return Wrap(spacing: 12, runSpacing: 12, children: [for (final x in cards) SizedBox(width: w, child: x)]);
              }),
              SectionTitle(Loc.t('Last 6 months', 'پچھلے 6 مہینے')),
              PCard(child: _TrendChart(trend: r.trend)),
              SectionTitle(Loc.t('Sales by plan', 'پلان کے حساب سے')),
              _breakdown(r.byPlan, pal.gold),
              SectionTitle(Loc.t('Collection by method', 'وصولی کا طریقہ')),
              _breakdown(r.byMethod, pal.green),
              SectionTitle(Loc.t('Expenses by category', 'اخراجات کی تفصیل')),
              _breakdown(r.byCategory, pal.red),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _mini(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: pal.onHeader.withValues(alpha: 0.6), fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ]),
      );

  Widget _breakdown(Map<String, double> data, Color color) {
    if (data.isEmpty) {
      return PCard(child: Text(Loc.t('Nothing this month', 'اس مہینے کچھ نہیں'), style: TextStyle(color: pal.muted)));
    }
    final total = data.values.fold<double>(0, (a, b) => a + b);
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return PCard(
      child: Column(children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.key, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700))),
                Text(Fmt.money(e.value), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(total <= 0 ? '' : '${(e.value / total * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.end, style: TextStyle(color: pal.muted, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total <= 0 ? 0 : e.value / total,
                  minHeight: 8,
                  color: color,
                  backgroundColor: pal.cardAlt,
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Saada bar chart: har mahine aamdani (sabz) aur kharcha (laal).
class _TrendChart extends StatelessWidget {
  final List<(DateTime, double, double)> trend;
  const _TrendChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    var maxV = 1.0;
    for (final t in trend) {
      if (t.$2 > maxV) maxV = t.$2;
      if (t.$3 > maxV) maxV = t.$3;
    }
    const h = 150.0;
    return Column(children: [
      SizedBox(
        height: h + 54,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final t in trend)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(Fmt.number(t.$2 - t.$3),
                    style: TextStyle(color: (t.$2 - t.$3) >= 0 ? pal.muted : pal.red, fontSize: 10)),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _bar(t.$2 / maxV * h, pal.green),
                  const SizedBox(width: 3),
                  _bar(t.$3 / maxV * h, pal.red),
                ]),
                const SizedBox(height: 6),
                Text(Fmt.monthLabel(t.$1).split(' ').first, style: TextStyle(color: pal.muted, fontSize: 11)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _legend(pal.green, Loc.t('Revenue', 'آمدنی')),
        const SizedBox(width: 18),
        _legend(pal.red, Loc.t('Expenses', 'اخراجات')),
      ]),
    ]);
  }

  Widget _bar(double height, Color color) => Container(
        width: 14,
        height: height < 2 ? 2 : height,
        decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
      );

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(color: pal.muted, fontSize: 12)),
      ]);
}
