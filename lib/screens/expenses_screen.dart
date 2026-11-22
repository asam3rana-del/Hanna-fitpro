import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../models/models.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';

/// Mahine ke kharche (kiraya, bijli, tankhwah, saman…).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> with AutoRefresh {
  DateTime _month = DateTime.utc(Fmt.today().year, Fmt.today().month, 1);
  List<Expense>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final from = Fmt.ymd(_month);
    final to = Fmt.ymd(DateTime.utc(_month.year, _month.month + 1, 0));
    final l = await ExpenseRepo.between(from, to);
    if (mounted) setState(() => _list = l);
  }

  void _shift(int months) {
    setState(() {
      _month = Fmt.addMonths(_month, months);
      _list = null;
    });
    _load();
  }

  Future<void> _edit([Expense? e]) async {
    final amount = TextEditingController(text: e == null ? '' : e.amount.toStringAsFixed(0));
    final paidTo = TextEditingController(text: e?.paidTo ?? '');
    final note = TextEditingController(text: e?.note ?? '');
    var category = e?.category ?? ExpenseRepo.categories.first;
    var method = e?.method ?? 'Cash';
    var date = Fmt.parseYmd(e?.date) ?? Fmt.today();
    final cats = [...ExpenseRepo.categories];
    if (!cats.contains(category)) cats.add(category);
    await showGymSheet<void>(
      context,
      title: e == null ? Loc.t('Add expense', 'خرچہ شامل کریں') : Loc.t('Edit expense', 'خرچہ میں ترمیم'),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in cats)
              GestureDetector(
                onTap: () => setSheet(() => category = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: c == category ? pal.gold : pal.cardAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c == category ? pal.gold : pal.border),
                  ),
                  child: Text(c,
                      style: TextStyle(color: c == category ? pal.onGold : pal.ink, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: amount,
            autofocus: e == null,
            keyboardType: TextInputType.number,
            style: TextStyle(color: pal.ink, fontSize: 20, fontWeight: FontWeight.w800),
            decoration: ThemeManager.field(Loc.t('Amount', 'رقم'), icon: Icons.payments_outlined),
          ),
          const SizedBox(height: 10),
          DateField(label: Loc.t('Date', 'تاریخ'), value: date, onChanged: (d) => setSheet(() => date = d)),
          const SizedBox(height: 10),
          TextField(
            controller: paidTo,
            decoration: ThemeManager.field(Loc.t('Paid to (optional)', 'کس کو دیا (اختیاری)'), icon: Icons.person_outline),
          ),
          const SizedBox(height: 10),
          ChoiceChips<String>(
            options: [for (final m in paymentMethods) (m, m)],
            value: method,
            onChanged: (v) => setSheet(() => method = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: ThemeManager.field(Loc.t('Note', 'نوٹ'), icon: Icons.notes)),
          const SizedBox(height: 18),
          GoldButton(
            label: Loc.t('SAVE', 'محفوظ کریں'),
            onPressed: () async {
              final amt = Fmt.toDouble(amount.text);
              if (amt <= 0) return;
              final x = Expense(
                id: e?.id ?? '',
                category: category,
                amount: amt,
                date: Fmt.ymd(date),
                note: note.text.trim(),
                paidTo: paidTo.text.trim(),
                method: method,
              );
              if (e == null) {
                await ExpenseRepo.create(x);
              } else {
                await ExpenseRepo.save(x);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          if (e != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final ok = await confirm(ctx, Loc.t('Delete expense?', 'خرچہ مٹائیں؟'), '${e!.category} · ${Fmt.money(e!.amount)}',
                    danger: true);
                if (!ok) return;
                await ExpenseRepo.delete(e!.id);
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
    final total = (list ?? []).fold<double>(0, (a, e) => a + e.amount);
    final byCat = <String, double>{};
    for (final e in list ?? <Expense>[]) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(Loc.t('Expenses', 'اخراجات')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: pal.gold,
        foregroundColor: pal.onGold,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(Loc.t('Add expense', 'خرچہ شامل کریں'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: Icon(Icons.chevron_left, color: pal.ink)),
              Expanded(
                child: Text(Fmt.monthLabel(_month),
                    textAlign: TextAlign.center, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              IconButton(onPressed: () => _shift(1), icon: Icon(Icons.chevron_right, color: pal.ink)),
            ]),
            const SizedBox(height: 8),
            HeroHeader(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Loc.t('Total expenses', 'کل اخراجات'), style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(Fmt.money(total), style: TextStyle(color: pal.onHeader, fontSize: 30, fontWeight: FontWeight.w900)),
                if (cats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final c in cats.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 120,
                          child: Text(c.key, style: TextStyle(color: pal.onHeader.withValues(alpha: 0.75), fontSize: 12.5)),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: total <= 0 ? 0 : c.value / total,
                              minHeight: 8,
                              color: pal.gold,
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(Fmt.number(c.value), style: TextStyle(color: pal.onHeader, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ]),
                    ),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            if (list == null)
              Padding(padding: const EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: pal.gold)))
            else if (list.isEmpty)
              EmptyState(icon: Icons.receipt_long_outlined, title: Loc.t('No expenses this month', 'اس مہینے کوئی خرچہ نہیں'))
            else
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () => _edit(e),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(color: pal.redSoft, borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.north_east, color: pal.red, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.category, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                          Text(
                            [Fmt.date(e.date), e.method, if (e.paidTo.isNotEmpty) e.paidTo].join(' · '),
                            style: TextStyle(color: pal.muted, fontSize: 12),
                          ),
                          if (e.note.isNotEmpty) Text(e.note, style: TextStyle(color: pal.muted, fontSize: 12)),
                        ]),
                      ),
                      Text(Fmt.money(e.amount), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
          ]),
        ),
      ),
    );
  }
}
