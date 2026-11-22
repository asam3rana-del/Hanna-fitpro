import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/user_repository.dart';
import '../models/models.dart';
import '../models/shop_models.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';

/// WhatsApp / call / reminder text.
class Messaging {
  Messaging._();

  static Future<void> whatsApp(BuildContext context, String phone, String text) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final digits = Fmt.whatsAppDigits(phone);
    if (digits.length < 10) {
      messenger?.showSnackBar(SnackBar(content: Text(Loc.t('Phone number missing / wrong', 'فون نمبر غلط یا خالی'))));
      return;
    }
    final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await Clipboard.setData(ClipboardData(text: text));
        messenger?.showSnackBar(
            SnackBar(content: Text(Loc.t('WhatsApp not found — message copied', 'واٹس ایپ نہیں ملا — پیغام کاپی ہو گیا'))));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger?.showSnackBar(SnackBar(content: Text(Loc.t('Message copied', 'پیغام کاپی ہو گیا'))));
    }
  }

  static Future<void> call(BuildContext context, String phone) async {
    final p = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: p));
    } catch (_) {}
  }

  /// Membership khatam / baqaya ka reminder (Settings ka template).
  static String reminderText(MemberSummary s) {
    final dues = s.dues > 0.5 ? 'Pending dues: ${Fmt.money(s.dues)}\n' : '';
    final d = s.daysLeft;
    return GymSettings.reminderTemplate
        .replaceAll('{name}', s.member.name)
        .replaceAll('{gym}', GymSettings.gymName)
        .replaceAll('{date}', Fmt.date(s.endDate))
        .replaceAll('{days}', d < 0 ? '0' : '$d')
        .replaceAll('{plan}', s.planName ?? 'gym')
        .replaceAll('{dues}', dues);
  }

  /// Sirf baqaya ka reminder.
  static String duesText(MemberSummary s) =>
      'Assalam o Alaikum ${s.member.name}!\n'
      'Your pending balance at ${GymSettings.gymName} is ${Fmt.money(s.dues)}.\n'
      'Kindly clear it at the reception. Thank you!\n'
      '— ${GymSettings.gymName}';

  /// Fees wasool hone ke baad shukriya + receipt text.
  static String receiptText(Payment p, {String? planLine, double balance = 0}) {
    final b = StringBuffer()
      ..writeln('*${GymSettings.gymName}* — Payment Receipt')
      ..writeln('Receipt: ${p.receiptNo}')
      ..writeln('Date: ${Fmt.date(p.paidOn)}')
      ..writeln('Member: ${p.memberName} (${p.memberCode})');
    if (planLine != null && planLine.isNotEmpty) b.writeln(planLine);
    b
      ..writeln('Paid: *${Fmt.money(p.amount)}* (${p.method})')
      ..writeln(balance > 0.5 ? 'Balance due: ${Fmt.money(balance)}' : 'Balance: Clear ✓')
      ..writeln()
      ..write('Thank you for training with us! 💪');
    return b.toString();
  }

  /// Counter ka bill (WhatsApp).
  static String saleText(Sale s, List<SaleItem> items, {double balance = 0}) {
    final b = StringBuffer()
      ..writeln('*${GymSettings.gymName}* — Bill')
      ..writeln('Bill: ${s.receiptNo}  ·  ${Fmt.date(s.date)}')
      ..writeln('Customer: ${s.buyer}${s.memberCode.isEmpty ? '' : ' (${s.memberCode})'}')
      ..writeln();
    for (final i in items) {
      b.writeln('• ${i.name} × ${Fmt.decimal(i.qty)} = ${Fmt.money(i.total)}');
    }
    b.writeln();
    if (s.discount > 0) b.writeln('Discount: ${Fmt.money(s.discount)}');
    b
      ..writeln('Total: *${Fmt.money(s.total)}*')
      ..writeln('Paid: ${Fmt.money(s.paid)} (${s.method})');
    if (s.credit > 0) b.writeln('Added to account: ${Fmt.money(s.credit)}');
    if (s.memberId != null) b.writeln(balance > 0.5 ? 'Total balance due: ${Fmt.money(balance)}' : 'Balance: Clear ✓');
    b.write('Thank you! 💪');
    return b.toString();
  }
}
