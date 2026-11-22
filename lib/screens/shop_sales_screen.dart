import 'package:flutter/material.dart';

import '../db/shop_repo.dart';
import '../models/shop_models.dart';
import '../services/backup_service.dart';
import '../services/session.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'payments_screen.dart' show Period;
import 'shop_screen.dart';

/// Counter ki sale: din / hafta / mahina, munafa, sab se zyada bikne wali cheezein.
class ShopSalesScreen extends StatefulWidget {
  const ShopSalesScreen({super.key});

  @override
  State<ShopSalesScreen> createState() => _ShopSalesScreenState();
}

class _ShopSalesScreenState extends State<ShopSalesScreen> with AutoRefresh {
  Period _period = Period.today;
  DateTimeRange? _custom;
  List<Sale>? _list;
  ShopStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  (DateTime, DateTime) get _range {
    final t = Fmt.today();
    final c = _custom;
    return switch (_period) {
      Period.today => (t, t),
      Period.week => (t.subtract(Duration(days: t.weekday - 1)), t),
      Period.month => (DateTime.utc(t.year, t.month, 1), DateTime.utc(t.year, t.month + 1, 0)),
      Period.lastMonth => (DateTime.utc(t.year, t.month - 1, 1), DateTime.utc(t.year, t.month, 0)),
      Period.custom => c == null
          ? (t, t)
          : (DateTime.utc(c.start.year, c.start.month, c.start.day), DateTime.utc(c.end.year, c.end.month, c.end.day)),
    };
  }

  Future<void> _load() async {
    final (a, b) = _range;
    final l = await ShopRepo.salesBetween(Fmt.ymd(a), Fmt.ymd(b));
    final st = await ShopRepo.stats(Fmt.ymd(a), Fmt.ymd(b));
    if (!mounted) return;
    setState(() {
      _list = l;
      _stats = st;
    });
  }

  Future<void> _choose(Period p) async {
    if (p == Period.custom) {
      final r = await showDateRangePicker(context: context, firstDate: DateTime(2015), lastDate: DateTime.now(), initialDateRange: _custom);
      if (r == null) return;
      _custom = r;
    }
    setState(() {
      _period = p;
      _list = null;
    });
    _load();
  }

  Future<void> _export() async {
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final b = StringBuffer('Date,Bill,Customer,Member ID,Total,Discount,Paid,On Account,Method,Status,By\n');
    for (final s in _list ?? <Sale>[]) {
      b.writeln([
        s.date,
        esc(s.receiptNo),
        esc(s.buyer),
        esc(s.memberCode),
        s.total.toStringAsFixed(0),
        s.discount.toStringAsFixed(0),
        s.paid.toStringAsFixed(0),
        s.credit.toStringAsFixed(0),
        esc(s.method),
        s.status,
        esc(s.byUser),
      ].join(','));
    }
    final (a, z) = _range;
    final msg = await BackupService.shareText('counter-sales-${Fmt.ymd(a)}-to-${Fmt.ymd(z)}.csv', b.toString());
    if (mounted) toast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final st = _stats;
    final (from, to) = _range;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(
        Loc.t('Counter sales', 'کاؤنٹر سیل'),
        subtitle: from == to ? Fmt.dateOf(from) : '${Fmt.dateOf(from)} – ${Fmt.dateOf(to)}',
        actions: [
          if (Session.canManage)
            IconButton(onPressed: _export, icon: Icon(Icons.file_download_outlined, color: pal.muted)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            ChoiceChips<Period>(
              options: [
                (Period.today, Loc.t('Today', 'آج')),
                (Period.week, Loc.t('This week', 'اس ہفتے')),
                (Period.month, Loc.t('This month', 'اس مہینے')),
                (Period.lastMonth, Loc.t('Last month', 'پچھلا مہینہ')),
                (Period.custom, Loc.t('Custom…', 'تاریخیں…')),
              ],
              value: _period,
              onChanged: _choose,
            ),
            const SizedBox(height: 14),
            if (st != null)
              HeroHeader(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Loc.t('Total sale', 'کل سیل'), style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700)),
                  Text(Fmt.money(st.total), style: TextStyle(color: pal.onHeader, fontSize: 30, fontWeight: FontWeight.w900)),
                  Text(Loc.t('${st.count} bills', '${st.count} بل'), style: TextStyle(color: pal.onHeader.withValues(alpha: 0.6))),
                  const SizedBox(height: 12),
                  Row(children: [
                    _mini(Loc.t('Cash in', 'نقد'), Fmt.money(st.paid), pal.green),
                    _mini(Loc.t('On account', 'ادھار'), Fmt.money(st.credit), pal.purple),
                    if (Session.canManage) _mini(Loc.t('Gross profit', 'منافع'), Fmt.money(st.grossProfit), pal.gold),
                  ]),
                ]),
              ),
            if (st != null && st.best.isNotEmpty) ...[
              SectionTitle(Loc.t('Best sellers', 'سب سے زیادہ بکنے والی')),
              PCard(
                child: Column(children: [
                  for (final (name, qty, amt) in st.best)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700))),
                        Text('× ${Fmt.decimal(qty)}', style: TextStyle(color: pal.muted)),
                        const SizedBox(width: 12),
                        Text(Fmt.money(amt), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                ]),
              ),
            ],
            SectionTitle(Loc.t('Bills', 'بل')),
            if (list == null)
              Padding(padding: const EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: pal.gold)))
            else if (list.isEmpty)
              EmptyState(icon: Icons.receipt_long_outlined, title: Loc.t('No bills in this period', 'اس مدت میں کوئی بل نہیں'))
            else
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () => showSaleReceipt(context, s),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(color: s.isVoid ? pal.redSoft : pal.goldSoft, borderRadius: BorderRadius.circular(12)),
                        child: Icon(s.isVoid ? Icons.block : Icons.shopping_bag_outlined, color: s.isVoid ? pal.red : pal.gold, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.buyer, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                          Text('${s.receiptNo} · ${Fmt.date(s.date)} · ${s.method}', style: TextStyle(color: pal.muted, fontSize: 12)),
                          if (s.credit > 0 && !s.isVoid)
                            Text('${Loc.t('On account', 'ادھار')} ${Fmt.money(s.credit)}',
                                style: TextStyle(color: pal.purple, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      Text(Fmt.money(s.total),
                          style: TextStyle(
                              color: s.isVoid ? pal.muted : pal.ink,
                              fontWeight: FontWeight.w900,
                              decoration: s.isVoid ? TextDecoration.lineThrough : null)),
                    ]),
                  ),
                ),
          ]),
        ),
      ),
    );
  }

  Widget _mini(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: pal.onHeader.withValues(alpha: 0.6), fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15))),
        ]),
      );
}
