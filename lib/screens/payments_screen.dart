import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../models/models.dart';
import '../services/backup_service.dart';
import '../services/session.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'member_profile_screen.dart';
import 'members_screen.dart';
import 'membership_sheets.dart';

enum Period { today, week, month, lastMonth, custom }

/// Fees ki wasooli (din / hafta / mahina).
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with AutoRefresh {
  Period _period = Period.today;
  DateTimeRange? _custom;
  List<Payment>? _list;

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
    final l = await PaymentRepo.between(Fmt.ymd(a), Fmt.ymd(b));
    if (mounted) setState(() => _list = l);
  }

  Future<void> _choose(Period p) async {
    if (p == Period.custom) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: DateTime.now(),
        initialDateRange: _custom,
      );
      if (r == null) return;
      _custom = r;
    }
    setState(() {
      _period = p;
      _list = null;
    });
    _load();
  }

  Future<void> _collect() async {
    final m = await pickMember(context);
    if (m == null || !mounted) return;
    await showCollectPaymentSheet(context, m);
  }

  Future<void> _export() async {
    final l = _list ?? [];
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final b = StringBuffer('Date,Receipt,Member ID,Member,Amount,Method,Note,Received By\n');
    for (final p in l) {
      b.writeln([
        p.paidOn,
        esc(p.receiptNo),
        esc(p.memberCode),
        esc(p.memberName),
        p.amount.toStringAsFixed(0),
        esc(p.method),
        esc(p.note),
        esc(p.receivedBy),
      ].join(','));
    }
    final (a, z) = _range;
    final msg = await BackupService.shareText('fees-${Fmt.ymd(a)}-to-${Fmt.ymd(z)}.csv', b.toString());
    if (mounted) toast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final total = (list ?? []).fold<double>(0, (a, p) => a + p.amount);
    final byMethod = <String, double>{};
    for (final p in list ?? <Payment>[]) {
      byMethod[p.method] = (byMethod[p.method] ?? 0) + p.amount;
    }
    final (from, to) = _range;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(
        Loc.t('Fees', 'فیس'),
        subtitle: from == to ? Fmt.dateOf(from) : '${Fmt.dateOf(from)} – ${Fmt.dateOf(to)}',
        actions: [
          if (Session.canManage)
            IconButton(
              tooltip: Loc.t('Export CSV', 'CSV ایکسپورٹ'),
              onPressed: _export,
              icon: Icon(Icons.file_download_outlined, color: pal.muted),
            ),
          const SyncBadge(),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: pal.gold,
        foregroundColor: pal.onGold,
        onPressed: _collect,
        icon: const Icon(Icons.add_card),
        label: Text(Loc.t('Collect fee', 'فیس وصول'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
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
            HeroHeader(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Loc.t('Collected', 'وصولی'), style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(Fmt.money(total), style: TextStyle(color: pal.onHeader, fontSize: 30, fontWeight: FontWeight.w900)),
                Text(Loc.t('${list?.length ?? 0} receipts', '${list?.length ?? 0} رسیدیں'),
                    style: TextStyle(color: pal.onHeader.withValues(alpha: 0.6))),
                if (byMethod.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in byMethod.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
                        child: Text('${e.key}: ${Fmt.money(e.value)}',
                            style: TextStyle(color: pal.onHeader, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            if (list == null)
              Padding(padding: const EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: pal.gold)))
            else if (list.isEmpty)
              EmptyState(icon: Icons.receipt_long_outlined, title: Loc.t('No payments in this period', 'اس مدت میں کوئی ادائیگی نہیں'))
            else
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () async {
                      final bal = await PaymentRepo.duesOf(p.memberId);
                      final s = await MemberRepo.summary(p.memberId);
                      if (!mounted) return;
                      await showReceiptActions(context, p, balance: bal, phone: s?.member.phone ?? '');
                    },
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(color: pal.greenSoft, borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.south_west, color: pal.green, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          GestureDetector(
                            onTap: () => push(context, MemberProfileScreen(memberId: p.memberId)),
                            child: Text(p.memberName.isEmpty ? '-' : p.memberName,
                                style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                          ),
                          Text('${p.memberCode} · ${Fmt.date(p.paidOn)} · ${p.method}',
                              style: TextStyle(color: pal.muted, fontSize: 12)),
                          if (p.note.isNotEmpty) Text(p.note, style: TextStyle(color: pal.muted, fontSize: 12)),
                        ]),
                      ),
                      Text(Fmt.money(p.amount), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900, fontSize: 15.5)),
                    ]),
                  ),
                ),
          ]),
        ),
      ),
    );
  }
}
