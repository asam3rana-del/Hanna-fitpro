import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../db/user_repository.dart';
import '../models/models.dart';
import '../services/messaging.dart';
import '../services/pdf_service.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/ui.dart';

/// Nayi / renew membership (+ saath hi fees). Wapas: true agar save hui.
Future<bool> showNewMembershipSheet(BuildContext context, String memberId) async {
  final s = await MemberRepo.summary(memberId);
  final plans = await PlanRepo.all(activeOnly: true);
  final trainers = await TrainerRepo.all(activeOnly: true);
  final previous = await MembershipRepo.forMember(memberId);
  if (s == null || !context.mounted) return false;
  final r = await showGymSheet<Object>(
    context,
    title: previous.isEmpty ? Loc.t('New membership', 'نئی ممبرشپ') : Loc.t('Renew membership', 'ممبرشپ تجدید'),
    builder: (ctx) => _MembershipForm(summary: s, plans: plans, trainers: trainers, firstTime: previous.isEmpty),
  );
  if (r is Payment) {
    final ms = r.membershipId == null ? null : await MembershipRepo.get(r.membershipId!);
    final bal = await PaymentRepo.duesOf(memberId);
    if (context.mounted) {
      await showReceiptActions(context, r, membership: ms, balance: bal, phone: s.member.phone);
    }
  }
  return r != null;
}

class _MembershipForm extends StatefulWidget {
  final MemberSummary summary;
  final List<Plan> plans;
  final List<Trainer> trainers;
  final bool firstTime;
  const _MembershipForm({required this.summary, required this.plans, required this.trainers, required this.firstTime});

  @override
  State<_MembershipForm> createState() => _MembershipFormState();
}

class _MembershipFormState extends State<_MembershipForm> {
  Plan? _plan;
  late DateTime _start;
  late DateTime _end;
  final _price = TextEditingController();
  final _admission = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  String _method = 'Cash';
  String? _trainerId;
  bool _busy = false;
  bool _paidTouched = false;

  @override
  void initState() {
    super.initState();
    // Pichhli membership abhi chal rahi ho to nayi us ke agle din se (koi din zaya na ho).
    final cur = widget.summary;
    final curEnd = Fmt.parseYmd(cur.endDate);
    _start = (curEnd != null && cur.daysLeft >= 0) ? curEnd.add(const Duration(days: 1)) : Fmt.today();
    _trainerId = cur.member.trainerId;
    if (widget.firstTime && GymSettings.admissionFee > 0) {
      _admission.text = Fmt.number(GymSettings.admissionFee).replaceAll(',', '');
    }
    final firstGym = widget.plans.where((p) => p.kind == 'gym').toList();
    _choose(firstGym.isNotEmpty ? firstGym.first : (widget.plans.isNotEmpty ? widget.plans.first : null));
  }

  @override
  void dispose() {
    for (final c in [_price, _admission, _discount, _paid, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _choose(Plan? p) {
    _plan = p;
    if (p != null) {
      _price.text = p.price.toStringAsFixed(0);
      _end = Fmt.planEnd(_start, p.durationValue, p.durationUnit);
    } else {
      _end = Fmt.addMonths(_start, 1).subtract(const Duration(days: 1));
    }
    _syncPaid();
  }

  double get _total =>
      (Fmt.toDouble(_price.text) + Fmt.toDouble(_admission.text) - Fmt.toDouble(_discount.text)).clamp(0, double.infinity).toDouble();

  void _syncPaid() {
    if (!_paidTouched) _paid.text = _total.toStringAsFixed(0);
  }

  Future<void> _save() async {
    final name = _plan?.name ?? Loc.t('Custom', 'کسٹم');
    if (_end.isBefore(_start)) {
      toast(context, Loc.t('End date is before start date', 'آخری تاریخ شروع سے پہلے ہے'));
      return;
    }
    setState(() => _busy = true);
    final msId = await MembershipRepo.create(
      memberId: widget.summary.member.id,
      plan: _plan,
      planName: name,
      kind: _plan?.kind ?? 'gym',
      trainerId: (_plan?.kind == 'pt') ? _trainerId : null,
      start: _start,
      end: _end,
      price: Fmt.toDouble(_price.text),
      admissionFee: Fmt.toDouble(_admission.text),
      discount: Fmt.toDouble(_discount.text),
      note: _note.text.trim(),
    );
    final paid = Fmt.toDouble(_paid.text);
    Payment? payment;
    if (paid > 0) {
      payment = await PaymentRepo.create(
        memberId: widget.summary.member.id,
        membershipId: msId,
        amount: paid,
        method: _method,
        note: name,
      );
    }
    if (!mounted) return;
    // Sheet band; receipt bahar wala function dikhata hai (is sheet ka context ab nahi rahega).
    Navigator.pop<Object>(context, payment ?? true);
  }

  @override
  Widget build(BuildContext context) {
    final gymPlans = widget.plans;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        MemberAvatar(memberId: widget.summary.member.id, name: widget.summary.member.name, hasPhoto: widget.summary.hasPhoto, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.summary.member.name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
            Text(
              widget.summary.endDate == null
                  ? widget.summary.member.code
                  : '${widget.summary.member.code} · ${Loc.t('current till', 'موجودہ')} ${Fmt.date(widget.summary.endDate)}',
              style: TextStyle(color: pal.muted, fontSize: 12),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Text(Loc.t('Choose plan', 'پلان چنیں'), style: TextStyle(color: pal.muted, fontSize: 12.5)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in gymPlans)
          GestureDetector(
            onTap: () => setState(() => _choose(p)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _plan?.id == p.id ? pal.goldSoft : pal.cardAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _plan?.id == p.id ? pal.gold : pal.border, width: _plan?.id == p.id ? 1.6 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (p.kind == 'pt') ...[Icon(Icons.sports_gymnastics, size: 14, color: pal.purple), const SizedBox(width: 4)],
                  Text(p.name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
                Text(Fmt.money(p.price), style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
          ),
        GestureDetector(
          onTap: () => setState(() => _choose(null)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: _plan == null ? pal.goldSoft : pal.cardAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _plan == null ? pal.gold : pal.border),
            ),
            child: Text(Loc.t('Custom', 'کسٹم'), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: DateField(
            label: Loc.t('Start', 'شروع'),
            value: _start,
            onChanged: (d) => setState(() {
              _start = d;
              final p = _plan;
              _end = p == null ? Fmt.addMonths(d, 1).subtract(const Duration(days: 1)) : Fmt.planEnd(d, p.durationValue, p.durationUnit);
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: DateField(label: Loc.t('Valid till', 'آخری دن'), value: _end, onChanged: (d) => setState(() => _end = d))),
      ]),
      if (_plan?.kind == 'pt' && widget.trainers.isNotEmpty) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: widget.trainers.any((t) => t.id == _trainerId) ? _trainerId : null,
          isExpanded: true,
          dropdownColor: pal.card,
          decoration: ThemeManager.field(Loc.t('Personal trainer', 'پرسنل ٹرینر'), icon: Icons.sports_gymnastics),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(Loc.t('Select trainer', 'ٹرینر چنیں'))),
            for (final t in widget.trainers) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
          ],
          onChanged: (v) => setState(() => _trainerId = v),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(_syncPaid),
            decoration: ThemeManager.field(Loc.t('Fee', 'فیس'), icon: Icons.sell_outlined),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _admission,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(_syncPaid),
            decoration: ThemeManager.field(Loc.t('Admission', 'داخلہ فیس'), icon: Icons.how_to_reg_outlined),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _discount,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(_syncPaid),
        decoration: ThemeManager.field(Loc.t('Discount', 'رعایت'), icon: Icons.percent),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: pal.goldSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(child: Text(Loc.t('Total', 'کل'), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700))),
          Text(Fmt.money(_total), style: TextStyle(color: pal.ink, fontSize: 20, fontWeight: FontWeight.w900)),
        ]),
      ),
      if (widget.summary.dues > 0.5)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(Loc.t('Old balance: ${Fmt.money(widget.summary.dues)}', 'پچھلا بقایا: ${Fmt.money(widget.summary.dues)}'),
              style: TextStyle(color: pal.purple, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      const SizedBox(height: 14),
      TextField(
        controller: _paid,
        keyboardType: TextInputType.number,
        onChanged: (_) => _paidTouched = true,
        decoration: ThemeManager.field(Loc.t('Paid now', 'ابھی وصول'), icon: Icons.payments_outlined),
      ),
      const SizedBox(height: 10),
      ChoiceChips<String>(
        options: [for (final m in paymentMethods) (m, m)],
        value: _method,
        onChanged: (v) => setState(() => _method = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: _note, decoration: ThemeManager.field(Loc.t('Note (optional)', 'نوٹ (اختیاری)'), icon: Icons.notes)),
      const SizedBox(height: 18),
      GoldButton(label: Loc.t('SAVE MEMBERSHIP', 'ممبرشپ محفوظ کریں'), icon: Icons.workspace_premium, busy: _busy, onPressed: _save),
    ]);
  }
}

/// Fees wasool karo (purana baqaya / advance). Wapas: true agar save hui.
Future<bool> showCollectPaymentSheet(BuildContext context, MemberSummary s) async {
  final p = await showGymSheet<Payment>(
    context,
    title: Loc.t('Collect fee', 'فیس وصول کریں'),
    builder: (ctx) => _PaymentForm(summary: s),
  );
  if (p == null) return false;
  final bal = await PaymentRepo.duesOf(s.member.id);
  if (context.mounted) await showReceiptActions(context, p, balance: bal, phone: s.member.phone);
  return true;
}

class _PaymentForm extends StatefulWidget {
  final MemberSummary summary;
  const _PaymentForm({required this.summary});

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _method = 'Cash';
  DateTime _date = Fmt.today();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.summary.dues > 0.5) _amount.text = widget.summary.dues.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = Fmt.toDouble(_amount.text);
    if (amt <= 0) {
      toast(context, Loc.t('Enter amount', 'رقم لکھیں'));
      return;
    }
    setState(() => _busy = true);
    final p = await PaymentRepo.create(
      memberId: widget.summary.member.id,
      amount: amt,
      method: _method,
      date: _date,
      note: _note.text.trim(),
    );
    if (!mounted) return;
    Navigator.pop<Payment>(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        MemberAvatar(memberId: s.member.id, name: s.member.name, hasPhoto: s.hasPhoto, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.member.name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
            Text(s.member.code, style: TextStyle(color: pal.muted, fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Loc.t('Balance', 'بقایا'), style: TextStyle(color: pal.muted, fontSize: 12)),
          Text(s.dues > 0.5 ? Fmt.money(s.dues) : Loc.t('Clear', 'صاف'),
              style: TextStyle(color: s.dues > 0.5 ? pal.purple : pal.green, fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
      ]),
      const SizedBox(height: 16),
      TextField(
        controller: _amount,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: TextStyle(color: pal.ink, fontSize: 22, fontWeight: FontWeight.w800),
        decoration: ThemeManager.field(Loc.t('Amount', 'رقم'), icon: Icons.payments_outlined),
      ),
      const SizedBox(height: 10),
      ChoiceChips<String>(
        options: [for (final m in paymentMethods) (m, m)],
        value: _method,
        onChanged: (v) => setState(() => _method = v),
      ),
      const SizedBox(height: 10),
      DateField(label: Loc.t('Date', 'تاریخ'), value: _date, onChanged: (d) => setState(() => _date = d)),
      const SizedBox(height: 10),
      TextField(controller: _note, decoration: ThemeManager.field(Loc.t('Note (optional)', 'نوٹ (اختیاری)'), icon: Icons.notes)),
      const SizedBox(height: 18),
      GoldButton(label: Loc.t('RECEIVE PAYMENT', 'رقم وصول کریں'), icon: Icons.check_circle_outline, busy: _busy, onPressed: _save),
    ]);
  }
}

/// Receipt: print / PDF share / WhatsApp.
Future<void> showReceiptActions(BuildContext context, Payment p,
    {Membership? membership, double balance = 0, String phone = ''}) async {
  final Membership? ms =
      membership ?? (p.membershipId == null ? null : await MembershipRepo.get(p.membershipId!));
  if (!context.mounted) return;
  await showGymSheet<void>(
    context,
    title: Loc.t('Payment received ✓', 'رقم وصول ہو گئی ✓'),
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PCard(
        color: pal.cardAlt,
        child: Column(children: [
          Text(Fmt.money(p.amount), style: TextStyle(color: pal.ink, fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${p.receiptNo} · ${p.method} · ${Fmt.date(p.paidOn)}', style: TextStyle(color: pal.muted)),
          const SizedBox(height: 6),
          Text(
            balance > 0.5 ? Loc.t('Balance due: ${Fmt.money(balance)}', 'باقی: ${Fmt.money(balance)}') : Loc.t('Balance clear ✓', 'حساب صاف ✓'),
            style: TextStyle(color: balance > 0.5 ? pal.purple : pal.green, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => Messaging.whatsApp(
          ctx,
          phone,
          Messaging.receiptText(p,
              planLine: ms == null ? null : 'Plan: ${ms.planName} (${Fmt.date(ms.startDate)} - ${Fmt.date(ms.endDate)})',
              balance: balance),
        ),
        icon: const Icon(Icons.chat),
        label: Text(Loc.t('Send receipt on WhatsApp', 'رسید واٹس ایپ پر بھیجیں')),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final bytes = await PdfService.receipt(payment: p, membership: ms, balance: balance);
              await PdfService.printPdf(bytes, 'Receipt ${p.receiptNo}');
            },
            icon: Icon(Icons.print_outlined, color: pal.gold),
            label: Text(Loc.t('Print', 'پرنٹ')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final bytes = await PdfService.receipt(payment: p, membership: ms, balance: balance);
              await PdfService.sharePdf(bytes, 'receipt-${p.receiptNo}.pdf');
            },
            icon: Icon(Icons.picture_as_pdf_outlined, color: pal.gold),
            label: Text(Loc.t('PDF', 'پی ڈی ایف')),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Loc.t('Done', 'ٹھیک ہے'))),
    ]),
  );
}

/// Membership barhao (freeze / chhutti / bonus din).
Future<void> showExtendSheet(BuildContext context, Membership m) async {
  final days = TextEditingController(text: '7');
  final reason = TextEditingController();
  await showGymSheet<void>(
    context,
    title: Loc.t('Freeze / extend membership', 'ممبرشپ فریز / بڑھائیں'),
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        Loc.t('${m.planName} — now valid till ${Fmt.date(m.endDate)}', '${m.planName} — ابھی ${Fmt.date(m.endDate)} تک'),
        style: TextStyle(color: pal.muted),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: days,
        keyboardType: TextInputType.number,
        decoration: ThemeManager.field(Loc.t('Add days', 'دن بڑھائیں'), icon: Icons.add_circle_outline),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: reason,
        decoration: ThemeManager.field(Loc.t('Reason (travel, illness, bonus…)', 'وجہ (سفر، بیماری، بونس…)'), icon: Icons.notes),
      ),
      const SizedBox(height: 18),
      GoldButton(
        label: Loc.t('EXTEND', 'بڑھائیں'),
        icon: Icons.ac_unit,
        onPressed: () async {
          final d = Fmt.toInt(days.text);
          if (d <= 0) return;
          await MembershipRepo.extend(m, d, reason: reason.text);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    ]),
  );
  // Controllers jaan boojh kar dispose nahi (sheet band hone ki animation ke dauran bhi istemal hote hain).
}
