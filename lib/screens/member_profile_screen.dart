import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../db/shop_repo.dart';
import '../models/models.dart';
import '../models/shop_models.dart';
import '../services/messaging.dart';
import '../services/pdf_service.dart';
import '../services/photo_service.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'member_form_screen.dart';
import 'membership_sheets.dart';
import 'shop_screen.dart' show showSaleReceipt;

class MemberProfileScreen extends StatefulWidget {
  final String memberId;

  /// Naya member save hote hi membership sheet khud khul jaye.
  final bool openNewMembership;
  const MemberProfileScreen({super.key, required this.memberId, this.openNewMembership = false});

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> with AutoRefresh {
  MemberSummary? _s;
  List<Membership> _ms = [];
  List<Payment> _pays = [];
  List<Attendance> _att = [];
  List<Measurement> _meas = [];
  List<Sale> _sales = [];
  List<Trainer> _trainers = [];
  bool _inGym = false;
  int _tab = 0;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.openNewMembership && mounted && _s != null) {
        showNewMembershipSheet(context, widget.memberId);
      }
    });
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final s = await MemberRepo.summary(widget.memberId);
    if (s == null) {
      if (mounted) setState(() => _missing = true);
      return;
    }
    final ms = await MembershipRepo.forMember(widget.memberId);
    final pays = await PaymentRepo.forMember(widget.memberId);
    final att = await AttendanceRepo.forMember(widget.memberId);
    final meas = await MeasurementRepo.forMember(widget.memberId);
    final today = await AttendanceRepo.todayFor(widget.memberId);
    final trainers = await TrainerRepo.all();
    final sales = await ShopRepo.salesForMember(widget.memberId);
    if (!mounted) return;
    setState(() {
      _s = s;
      _ms = ms;
      _pays = pays;
      _att = att;
      _meas = meas;
      _trainers = trainers;
      _sales = sales;
      _inGym = today != null && today.checkOut == null;
    });
  }

  String _trainerName(String? id) {
    if (id == null) return '';
    for (final t in _trainers) {
      if (t.id == id) return t.name;
    }
    return '';
  }

  Future<void> _toggleAttendance() async {
    final s = _s!;
    if (!_inGym && s.stateFor(5) == MemberState.expired) {
      final ok = await confirm(
        context,
        Loc.t('Membership expired', 'ممبرشپ ختم ہو چکی'),
        Loc.t('${s.member.name}\'s membership ended on ${Fmt.date(s.endDate)}. Check in anyway?',
            '${s.member.name} کی ممبرشپ ${Fmt.date(s.endDate)} کو ختم ہو گئی۔ پھر بھی حاضری لگائیں؟'),
        yes: Loc.t('Check in', 'حاضری لگائیں'),
      );
      if (!ok) return;
    }
    final inNow = await AttendanceRepo.toggle(s.member.id);
    if (mounted) toast(context, inNow ? Loc.t('Checked in ✓', 'حاضری لگ گئی ✓') : Loc.t('Checked out ✓', 'چیک آؤٹ ✓'));
  }

  Future<void> _idCard() async {
    final s = _s!;
    final photo = s.hasPhoto ? await PhotoService.bytesFor(s.member.id) : null;
    final bytes = await PdfService.memberCard(member: s.member, photo: photo, validTill: s.endDate, planName: s.planName);
    if (!mounted) return;
    await showGymSheet<void>(
      context,
      title: Loc.t('Member ID card', 'ممبر کارڈ'),
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          Loc.t('ATM-card size with QR code. Scan it (or type the ID) at Check-in.',
              'اے ٹی ایم کارڈ سائز، QR کوڈ کے ساتھ۔ حاضری پر اسکین کریں (یا آئی ڈی لکھیں)۔'),
          style: TextStyle(color: pal.muted),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => PdfService.printPdf(bytes, 'Card ${s.member.code}'),
          icon: const Icon(Icons.print),
          label: Text(Loc.t('Print card', 'کارڈ پرنٹ کریں')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => PdfService.sharePdf(bytes, 'card-${s.member.code}.pdf'),
          icon: Icon(Icons.share, color: pal.gold),
          label: Text(Loc.t('Share PDF', 'پی ڈی ایف شیئر')),
        ),
      ]),
    );
  }

  Future<void> _delete() async {
    final s = _s!;
    final ok = await confirm(
      context,
      Loc.t('Delete ${s.member.name}?', '${s.member.name} کو مٹائیں؟'),
      Loc.t('All memberships, payments and attendance of this member will also be removed.',
          'اس ممبر کی تمام ممبرشپ، ادائیگیاں اور حاضری بھی مٹ جائیں گی۔'),
      yes: Loc.t('Delete', 'مٹائیں'),
      danger: true,
    );
    if (!ok) return;
    await MemberRepo.delete(s.member.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (_missing) {
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: gymAppBar(Loc.t('Member', 'ممبر')),
        body: EmptyState(icon: Icons.person_off_outlined, title: Loc.t('Member not found', 'ممبر نہیں ملا')),
      );
    }
    if (s == null) {
      return Scaffold(backgroundColor: pal.bg, body: Center(child: CircularProgressIndicator(color: pal.gold)));
    }
    final Widget tabBody = switch (_tab) {
      1 => _memberships(),
      2 => _payments(),
      3 => _attendance(),
      4 => _progress(s),
      5 => _shop(),
      _ => _overview(s),
    };
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(
        s.member.code,
        actions: [
          IconButton(
            tooltip: Loc.t('Edit', 'ترمیم'),
            icon: Icon(Icons.edit_outlined, color: pal.gold),
            onPressed: () async {
              await push(context, MemberFormScreen(member: s.member));
              _load();
            },
          ),
          PopupMenuButton<String>(
            color: pal.card,
            icon: Icon(Icons.more_vert, color: pal.ink),
            onSelected: (v) {
              if (v == 'card') _idCard();
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'card', child: Text(Loc.t('Member ID card (QR)', 'ممبر کارڈ (QR)'))),
              if (Session.canManage)
                PopupMenuItem(value: 'delete', child: Text(Loc.t('Delete member', 'ممبر مٹائیں'), style: TextStyle(color: pal.red))),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            _hero(s),
            const SizedBox(height: 14),
            ChoiceChips<int>(
              options: [
                (0, Loc.t('Overview', 'تفصیل')),
                (1, '${Loc.t('Memberships', 'ممبرشپ')} ${_ms.length}'),
                (2, '${Loc.t('Payments', 'ادائیگیاں')} ${_pays.length}'),
                (3, '${Loc.t('Attendance', 'حاضری')} ${_att.length}'),
                (4, '${Loc.t('Progress', 'پیش رفت')} ${_meas.length}'),
                (5, '${Loc.t('Counter', 'کاؤنٹر')} ${_sales.length}'),
              ],
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
            const SizedBox(height: 12),
            tabBody,
          ]),
        ),
      ),
    );
  }

  Widget _hero(MemberSummary s) => HeroHeader(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            MemberAvatar(memberId: s.member.id, name: s.member.name, hasPhoto: s.hasPhoto, size: 78),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.member.name,
                    style: TextStyle(color: pal.onHeader, fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  [s.member.code, if (s.member.phone.isNotEmpty) s.member.phone].join('  ·  '),
                  style: TextStyle(color: pal.onHeader.withValues(alpha: 0.65), fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatePill(s),
                  if (_inGym) Pill(Loc.t('In gym now', 'ابھی جم میں'), color: pal.green, soft: pal.greenSoft, icon: Icons.circle),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _heroStat(Loc.t('Plan', 'پلان'), s.planName ?? '-'),
            _heroStat(Loc.t('Valid till', 'آخری تاریخ'), Fmt.date(s.endDate)),
            _heroStat(Loc.t('Balance', 'بقایا'), s.dues > 0.5 ? Fmt.money(s.dues) : Loc.t('Clear', 'صاف'),
                color: s.dues > 0.5 ? pal.amber : pal.green),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _action(Icons.workspace_premium, s.endDate == null ? Loc.t('Add plan', 'پلان') : Loc.t('Renew', 'تجدید'), true,
                () => showNewMembershipSheet(context, s.member.id)),
            _action(Icons.payments_outlined, Loc.t('Collect fee', 'فیس'), false, () => showCollectPaymentSheet(context, s)),
            _action(_inGym ? Icons.logout : Icons.how_to_reg, _inGym ? Loc.t('Check out', 'چیک آؤٹ') : Loc.t('Check in', 'حاضری'),
                false, _toggleAttendance),
            if (s.member.phone.isNotEmpty) ...[
              _action(Icons.chat_outlined, 'WhatsApp', false,
                  () => Messaging.whatsApp(context, s.member.phone, Messaging.reminderText(s))),
              _action(Icons.call_outlined, Loc.t('Call', 'کال'), false, () => Messaging.call(context, s.member.phone)),
            ],
          ]),
        ]),
      );

  Widget _heroStat(String label, String value, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: pal.onHeader.withValues(alpha: 0.55), fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color ?? pal.onHeader, fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
      );

  Widget _action(IconData icon, String label, bool primary, VoidCallback onTap) => Material(
        color: primary ? pal.gold : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: primary ? pal.onGold : pal.onHeader),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: primary ? pal.onGold : pal.onHeader, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      );

  // ---------------- tabs ----------------

  Widget _overview(MemberSummary s) {
    final m = s.member;
    final dob = Fmt.parseYmd(m.dob);
    final age = dob == null ? '' : '${Fmt.today().difference(dob).inDays ~/ 365} ${Loc.t('years', 'سال')}';
    String gender(String g) => g == 'male'
        ? Loc.t('Male', 'مرد')
        : g == 'female'
            ? Loc.t('Female', 'خاتون')
            : g;
    String timing(String t) => switch (t) {
          'morning' => Loc.t('Morning', 'صبح'),
          'evening' => Loc.t('Evening', 'شام'),
          'ladies' => Loc.t('Ladies time', 'خواتین کا وقت'),
          _ => Loc.t('Any', 'کوئی بھی'),
        };
    final monthStart = Fmt.ymd(DateTime.utc(Fmt.today().year, Fmt.today().month, 1));
    final visitsThisMonth = _att.where((a) => a.date.compareTo(monthStart) >= 0).map((a) => a.date).toSet().length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: StatCard(
            icon: Icons.calendar_month,
            label: Loc.t('Visits this month', 'اس مہینے حاضری'),
            value: '$visitsThisMonth',
            color: pal.blue,
            soft: pal.blueSoft,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.history,
            label: Loc.t('Last visit', 'آخری حاضری'),
            value: Fmt.date(s.lastVisit),
            color: pal.green,
            soft: pal.greenSoft,
          ),
        ),
      ]),
      const SizedBox(height: 12),
      PCard(
        child: Column(children: [
          InfoRow(Loc.t('Phone', 'فون'), m.phone, icon: Icons.phone_outlined),
          InfoRow(Loc.t('Gender', 'جنس'), gender(m.gender), icon: Icons.wc),
          InfoRow(Loc.t('Age', 'عمر'), age, icon: Icons.cake_outlined),
          InfoRow(Loc.t('Joined', 'شمولیت'), Fmt.date(m.joinedOn), icon: Icons.event_available),
          InfoRow(Loc.t('Timing', 'وقت'), timing(m.timing), icon: Icons.schedule),
          InfoRow(Loc.t('Goal', 'مقصد'), m.goal, icon: Icons.flag_outlined),
          InfoRow(Loc.t('Trainer', 'ٹرینر'), _trainerName(m.trainerId), icon: Icons.sports_gymnastics),
          InfoRow(Loc.t('Height', 'قد'), m.heightCm > 0 ? '${Fmt.decimal(m.heightCm)} cm' : '', icon: Icons.height),
          InfoRow(Loc.t('Blood group', 'بلڈ گروپ'), m.bloodGroup, icon: Icons.bloodtype_outlined),
          InfoRow(Loc.t('CNIC', 'شناختی کارڈ'), m.cnic, icon: Icons.credit_card),
          InfoRow(Loc.t('Emergency', 'ہنگامی'), [m.emergencyName, m.emergencyPhone].where((e) => e.isNotEmpty).join(' · '),
              icon: Icons.emergency_outlined),
          InfoRow(Loc.t('Address', 'پتہ'), m.address, icon: Icons.home_outlined),
          if (m.notes.isNotEmpty) InfoRow(Loc.t('Notes', 'نوٹس'), m.notes, icon: Icons.notes),
        ]),
      ),
    ]);
  }

  Widget _memberships() {
    if (_ms.isEmpty) {
      return EmptyState(
        icon: Icons.workspace_premium_outlined,
        title: Loc.t('No membership yet', 'ابھی کوئی ممبرشپ نہیں'),
        action: FilledButton.icon(
          onPressed: () => showNewMembershipSheet(context, widget.memberId),
          icon: const Icon(Icons.add),
          label: Text(Loc.t('Add membership', 'ممبرشپ شامل کریں')),
        ),
      );
    }
    return Column(children: [
      for (final m in _ms)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PCard(
            borderColor: m.cancelled ? pal.border : (Fmt.daysLeft(m.endDate) >= 0 ? pal.gold.withValues(alpha: 0.5) : pal.border),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: m.kind == 'pt' ? pal.purpleSoft : pal.goldSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(m.kind == 'pt' ? Icons.sports_gymnastics : Icons.workspace_premium,
                    color: m.kind == 'pt' ? pal.purple : pal.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.planName,
                      style: TextStyle(
                          color: pal.ink,
                          fontWeight: FontWeight.w800,
                          decoration: m.cancelled ? TextDecoration.lineThrough : null)),
                  const SizedBox(height: 2),
                  Text('${Fmt.date(m.startDate)}  →  ${Fmt.date(m.endDate)}', style: TextStyle(color: pal.muted, fontSize: 12.5)),
                  if (m.trainerId != null && _trainerName(m.trainerId).isNotEmpty)
                    Text('${Loc.t('Trainer', 'ٹرینر')}: ${_trainerName(m.trainerId)}', style: TextStyle(color: pal.muted, fontSize: 12.5)),
                  if (m.frozenDays > 0)
                    Text(Loc.t('Extended ${m.frozenDays} days', '${m.frozenDays} دن بڑھائی گئی'), style: TextStyle(color: pal.blue, fontSize: 12)),
                  if (m.note.isNotEmpty) Text(m.note, style: TextStyle(color: pal.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    Pill(Fmt.money(m.total), color: pal.ink, soft: pal.cardAlt),
                    if (m.discount > 0) Pill('-${Fmt.money(m.discount)}', color: pal.green, soft: pal.greenSoft),
                    if (m.cancelled) Pill(Loc.t('Cancelled', 'منسوخ'), color: pal.red, soft: pal.redSoft),
                  ]),
                ]),
              ),
              if (!m.cancelled)
                PopupMenuButton<String>(
                  color: pal.card,
                  icon: Icon(Icons.more_vert, color: pal.muted),
                  onSelected: (v) async {
                    if (v == 'extend') await showExtendSheet(context, m);
                    if (v == 'cancel' && mounted) {
                      final ok = await confirm(context, Loc.t('Cancel this membership?', 'یہ ممبرشپ منسوخ کریں؟'),
                          Loc.t('Its fee will be removed from the balance. Payments stay recorded.', 'اس کی فیس بقایا سے نکل جائے گی۔ ادائیگیاں ریکارڈ میں رہیں گی۔'),
                          danger: true);
                      if (ok) await MembershipRepo.cancel(m.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'extend', child: Text(Loc.t('Freeze / extend', 'فریز / بڑھائیں'))),
                    if (Session.canManage)
                      PopupMenuItem(value: 'cancel', child: Text(Loc.t('Cancel membership', 'منسوخ کریں'), style: TextStyle(color: pal.red))),
                  ],
                ),
            ]),
          ),
        ),
    ]);
  }

  Widget _payments() {
    if (_pays.isEmpty) {
      return EmptyState(icon: Icons.payments_outlined, title: Loc.t('No payments yet', 'ابھی کوئی ادائیگی نہیں'));
    }
    final total = _pays.fold<double>(0, (a, p) => a + p.amount);
    return Column(children: [
      PCard(
        color: pal.cardAlt,
        child: Row(children: [
          Expanded(child: Text(Loc.t('Total paid', 'کل ادا'), style: TextStyle(color: pal.muted))),
          Text(Fmt.money(total), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900, fontSize: 17)),
        ]),
      ),
      const SizedBox(height: 10),
      for (final p in _pays)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onTap: () async {
              final bal = await PaymentRepo.duesOf(widget.memberId);
              if (!mounted) return;
              await showReceiptActions(context, p, balance: bal, phone: _s?.member.phone ?? '');
            },
            child: Row(children: [
              Icon(Icons.receipt_long, color: pal.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Fmt.money(p.amount), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                  Text('${Fmt.date(p.paidOn)} · ${p.method} · ${p.receiptNo}', style: TextStyle(color: pal.muted, fontSize: 12)),
                  if (p.note.isNotEmpty) Text(p.note, style: TextStyle(color: pal.muted, fontSize: 12)),
                ]),
              ),
              if (Session.canManage)
                IconButton(
                  tooltip: Loc.t('Delete', 'مٹائیں'),
                  icon: Icon(Icons.delete_outline, color: pal.muted),
                  onPressed: () async {
                    final ok = await confirm(context, Loc.t('Delete this payment?', 'یہ ادائیگی مٹائیں؟'),
                        '${Fmt.money(p.amount)} · ${p.receiptNo}', danger: true);
                    if (ok) await PaymentRepo.delete(p.id);
                  },
                ),
            ]),
          ),
        ),
    ]);
  }

  Widget _shop() {
    if (_sales.isEmpty) {
      return EmptyState(icon: Icons.storefront_outlined, title: Loc.t('No counter purchases', 'کاؤنٹر سے کوئی خریداری نہیں'));
    }
    return Column(children: [
      for (final sale in _sales)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onTap: () => showSaleReceipt(context, sale),
            child: Row(children: [
              Icon(sale.isVoid ? Icons.block : Icons.shopping_bag_outlined, color: sale.isVoid ? pal.red : pal.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${sale.receiptNo} · ${Fmt.date(sale.date)}', style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                  Text(
                    sale.credit > 0 && !sale.isVoid
                        ? '${Loc.t('Paid', 'ادا')} ${Fmt.money(sale.paid)} · ${Loc.t('On account', 'ادھار')} ${Fmt.money(sale.credit)}'
                        : '${Loc.t('Paid', 'ادا')} ${Fmt.money(sale.paid)} · ${sale.method}',
                    style: TextStyle(color: pal.muted, fontSize: 12),
                  ),
                ]),
              ),
              Text(Fmt.money(sale.total),
                  style: TextStyle(
                      color: sale.isVoid ? pal.muted : pal.ink,
                      fontWeight: FontWeight.w900,
                      decoration: sale.isVoid ? TextDecoration.lineThrough : null)),
            ]),
          ),
        ),
    ]);
  }

  Widget _attendance() {
    if (_att.isEmpty) {
      return EmptyState(icon: Icons.event_available_outlined, title: Loc.t('No visits yet', 'ابھی کوئی حاضری نہیں'));
    }
    return PCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        for (final a in _att)
          ListTile(
            dense: true,
            leading: Icon(Icons.check_circle, color: pal.green),
            title: Text(Fmt.date(a.date), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${Loc.t('In', 'آمد')} ${Fmt.time(a.checkIn)}${a.checkOut != null ? '  ·  ${Loc.t('Out', 'روانگی')} ${Fmt.time(a.checkOut)}' : ''}',
              style: TextStyle(color: pal.muted, fontSize: 12),
            ),
          ),
      ]),
    );
  }

  Widget _progress(MemberSummary s) {
    final h = s.member.heightCm;
    String bmi(double w) {
      if (h <= 0 || w <= 0) return '';
      final v = w / ((h / 100) * (h / 100));
      return 'BMI ${v.toStringAsFixed(1)}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(
        onPressed: () => _addMeasurement(s),
        icon: Icon(Icons.add_chart, color: pal.gold),
        label: Text(Loc.t('Add body measurement', 'جسمانی پیمائش شامل کریں')),
      ),
      const SizedBox(height: 10),
      if (_meas.isEmpty)
        EmptyState(icon: Icons.monitor_weight_outlined, title: Loc.t('No measurements yet', 'ابھی کوئی پیمائش نہیں'))
      else ...[
        if (_meas.length >= 2)
          PCard(
            color: pal.cardAlt,
            child: Row(children: [
              Icon(Icons.trending_flat, color: pal.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Loc.t(
                    'Weight ${Fmt.decimal(_meas.last.weight)} → ${Fmt.decimal(_meas.first.weight)} kg '
                        '(${(_meas.first.weight - _meas.last.weight) >= 0 ? '+' : ''}${Fmt.decimal(_meas.first.weight - _meas.last.weight)})',
                    'وزن ${Fmt.decimal(_meas.last.weight)} → ${Fmt.decimal(_meas.first.weight)} کلو',
                  ),
                  style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        for (final m in _meas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(Fmt.date(m.date), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800))),
                  if (bmi(m.weight).isNotEmpty) Pill(bmi(m.weight), color: pal.blue, soft: pal.blueSoft),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: pal.muted, size: 20),
                    onPressed: () => MeasurementRepo.delete(m.id),
                  ),
                ]),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  if (m.weight > 0) Text('${Loc.t('Weight', 'وزن')}: ${Fmt.decimal(m.weight)} kg', style: TextStyle(color: pal.ink)),
                  if (m.bodyFat > 0) Text('${Loc.t('Fat', 'چربی')}: ${Fmt.decimal(m.bodyFat)}%', style: TextStyle(color: pal.ink)),
                  if (m.chest > 0) Text('${Loc.t('Chest', 'سینہ')}: ${Fmt.decimal(m.chest)}"', style: TextStyle(color: pal.ink)),
                  if (m.waist > 0) Text('${Loc.t('Waist', 'کمر')}: ${Fmt.decimal(m.waist)}"', style: TextStyle(color: pal.ink)),
                  if (m.arms > 0) Text('${Loc.t('Arms', 'بازو')}: ${Fmt.decimal(m.arms)}"', style: TextStyle(color: pal.ink)),
                  if (m.thigh > 0) Text('${Loc.t('Thigh', 'ران')}: ${Fmt.decimal(m.thigh)}"', style: TextStyle(color: pal.ink)),
                ]),
                if (m.note.isNotEmpty) Text(m.note, style: TextStyle(color: pal.muted, fontSize: 12)),
              ]),
            ),
          ),
      ],
    ]);
  }

  Future<void> _addMeasurement(MemberSummary s) async {
    final c = {
      for (final k in ['weight', 'fat', 'chest', 'waist', 'arms', 'thigh', 'note']) k: TextEditingController(),
    };
    DateTime date = Fmt.today();
    Widget numField(String k, String label) => Expanded(
          child: TextField(
            controller: c[k],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: ThemeManager.field(label),
          ),
        );
    await showGymSheet<void>(
      context,
      title: Loc.t('Body measurement', 'جسمانی پیمائش'),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DateField(label: Loc.t('Date', 'تاریخ'), value: date, onChanged: (d) => setSheet(() => date = d)),
          const SizedBox(height: 10),
          Row(children: [numField('weight', Loc.t('Weight (kg)', 'وزن (کلو)')), const SizedBox(width: 10), numField('fat', Loc.t('Body fat %', 'چربی %'))]),
          const SizedBox(height: 10),
          Row(children: [numField('chest', Loc.t('Chest (in)', 'سینہ (انچ)')), const SizedBox(width: 10), numField('waist', Loc.t('Waist (in)', 'کمر (انچ)'))]),
          const SizedBox(height: 10),
          Row(children: [numField('arms', Loc.t('Arms (in)', 'بازو (انچ)')), const SizedBox(width: 10), numField('thigh', Loc.t('Thigh (in)', 'ران (انچ)'))]),
          const SizedBox(height: 10),
          TextField(controller: c['note'], decoration: ThemeManager.field(Loc.t('Note', 'نوٹ'), icon: Icons.notes)),
          const SizedBox(height: 18),
          GoldButton(
            label: Loc.t('SAVE', 'محفوظ کریں'),
            onPressed: () async {
              await MeasurementRepo.create(Measurement(
                id: '',
                memberId: s.member.id,
                date: Fmt.ymd(date),
                weight: Fmt.toDouble(c['weight']!.text),
                bodyFat: Fmt.toDouble(c['fat']!.text),
                chest: Fmt.toDouble(c['chest']!.text),
                waist: Fmt.toDouble(c['waist']!.text),
                arms: Fmt.toDouble(c['arms']!.text),
                thigh: Fmt.toDouble(c['thigh']!.text),
                note: c['note']!.text.trim(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }
}
