import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../db/user_repository.dart';
import '../models/models.dart';
import '../utils/fmt.dart';
import '../utils/pdf_urdu.dart';

/// Receipt (80mm roll — thermal ya kisi bhi printer par) aur Member ID card (ATM card size, QR ke saath).
class PdfService {
  PdfService._();

  static const _gold = PdfColor.fromInt(0xFFB8912B);
  static const _goldLight = PdfColor.fromInt(0xFFE9D8A6);
  static const _black = PdfColor.fromInt(0xFF15151A);
  static const _muted = PdfColor.fromInt(0xFF6F6A5F);
  static const _white = PdfColor.fromInt(0xFFFFFFFF);
  static const _line = PdfColor.fromInt(0xFFE6DFCF);

  /// PDF ka built-in font sirf Latin parhta hai — baqi huroof hata do (Urdu alag tasveer ban kar aata hai).
  static String _latin(String s) =>
      String.fromCharCodes(s.runes.map((r) => r == 0x2014 || r == 0x2013 ? 0x2D : r).where((r) => r <= 0xFF));

  static pw.Widget _t(String s,
      {double size = 9, bool bold = false, PdfColor color = _black, pw.TextAlign align = pw.TextAlign.left}) {
    final u = UrduPdf.widget(s, fontSize: size, argb: color.toInt(), bold: bold);
    if (u != null) return u;
    return pw.Text(
      _latin(s),
      textAlign: align,
      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
    );
  }

  static pw.Widget _row(String label, String value, {bool bold = false, double size = 8.5}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 62, child: _t(label, size: size, color: _muted)),
          pw.Expanded(child: _t(value, size: size, bold: bold)),
        ]),
      );

  // ---------------- receipt ----------------

  static Future<Uint8List> receipt({
    required Payment payment,
    Membership? membership,
    double balance = 0,
  }) async {
    pw.Widget body() => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Center(child: _t(GymSettings.gymName.toUpperCase(), size: 14, bold: true)),
          pw.SizedBox(height: 2),
          pw.Center(child: _t(GymSettings.gymTagline, size: 7.5, color: _muted)),
          if (GymSettings.gymAddress.isNotEmpty) pw.Center(child: _t(GymSettings.gymAddress, size: 7.5, color: _muted)),
          if (GymSettings.gymPhone.isNotEmpty) pw.Center(child: _t('Ph: ${GymSettings.gymPhone}', size: 7.5, color: _muted)),
          pw.SizedBox(height: 6),
          pw.Container(height: 2, color: _gold),
          pw.SizedBox(height: 6),
          pw.Center(child: _t('PAYMENT RECEIPT', size: 10, bold: true, color: _gold)),
          pw.SizedBox(height: 6),
          _row('Receipt #', payment.receiptNo, bold: true),
          _row('Date', Fmt.date(payment.paidOn)),
          _row('Member', payment.memberName, bold: true),
          _row('Member ID', payment.memberCode),
          if (membership != null) ...[
            _row('Plan', membership.planName),
            _row('Valid', '${Fmt.date(membership.startDate)} to ${Fmt.date(membership.endDate)}'),
            if (membership.admissionFee > 0) _row('Admission', Fmt.money(membership.admissionFee)),
            if (membership.discount > 0) _row('Discount', Fmt.money(membership.discount)),
            _row('Plan Total', Fmt.money(membership.total)),
          ],
          pw.SizedBox(height: 4),
          pw.Divider(color: _line, thickness: 0.8),
          pw.Row(children: [
            pw.Expanded(child: _t('PAID (${payment.method})', size: 10, bold: true)),
            _t(Fmt.money(payment.amount), size: 12, bold: true),
          ]),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            pw.Expanded(child: _t('Balance', size: 9, color: _muted)),
            _t(balance > 0.5 ? Fmt.money(balance) : 'Clear', size: 9, bold: true),
          ]),
          pw.Divider(color: _line, thickness: 0.8),
          if (payment.note.isNotEmpty) _row('Note', payment.note),
          if (payment.receivedBy.isNotEmpty) _row('Received by', payment.receivedBy),
          pw.SizedBox(height: 8),
          pw.Center(child: _t(GymSettings.receiptNote, size: 7.5, color: _muted, align: pw.TextAlign.center)),
          pw.SizedBox(height: 6),
          pw.Center(child: _t('Powered by Hanna Solutions', size: 6.5, color: _muted)),
        ]);

    // Pehla pass: Urdu text jama karo, tasveerein banao, phir asal PDF.
    body();
    await UrduPdf.flush();
    final doc = pw.Document(title: 'Receipt ${payment.receiptNo}', author: GymSettings.gymName);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 12, marginRight: 12, marginTop: 14, marginBottom: 14),
      build: (_) => body(),
    ));
    return doc.save();
  }

  // ---------------- member card ----------------

  static Future<Uint8List> memberCard({
    required Member member,
    Uint8List? photo,
    String? validTill,
    String? planName,
  }) async {
    final img = photo == null ? null : pw.MemoryImage(photo);

    pw.Widget front() => pw.Container(
          decoration: pw.BoxDecoration(color: _black, borderRadius: pw.BorderRadius.circular(8)),
          padding: const pw.EdgeInsets.all(10),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Row(children: [
              pw.Expanded(child: _t(GymSettings.gymName.toUpperCase(), size: 10, bold: true, color: _goldLight)),
              _t('MEMBER', size: 7, bold: true, color: _gold),
            ]),
            pw.SizedBox(height: 3),
            pw.Container(height: 1.2, color: _gold),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Container(
                  width: 52,
                  height: 52,
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFF2A2720),
                    borderRadius: pw.BorderRadius.circular(26),
                    border: pw.Border.all(color: _gold, width: 1.2),
                  ),
                  child: img == null
                      ? pw.Center(child: _t(Fmt.initials(member.name), size: 16, bold: true, color: _goldLight))
                      : pw.ClipOval(child: pw.Image(img, fit: pw.BoxFit.cover, width: 52, height: 52)),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        _t(member.name, size: 10.5, bold: true, color: _white),
                        pw.SizedBox(height: 3),
                        _t('ID: ${member.code}', size: 8, bold: true, color: _gold),
                        if (planName != null && planName.isNotEmpty) _t(planName, size: 6.5, color: _goldLight),
                        if (validTill != null) _t('Valid till ${Fmt.date(validTill)}', size: 6.5, color: _goldLight),
                      ]),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(color: _white, borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: member.code.isEmpty ? member.id : member.code,
                    width: 50,
                    height: 50,
                  ),
                ),
              ]),
            ),
            pw.SizedBox(height: 4),
            pw.Row(children: [
              pw.Expanded(child: _t(GymSettings.gymPhone.isEmpty ? '' : 'Ph: ${GymSettings.gymPhone}', size: 6, color: _goldLight)),
              _t('Show this card at reception', size: 6, color: _muted),
            ]),
          ]),
        );

    front();
    await UrduPdf.flush();
    final doc = pw.Document(title: 'Member Card ${member.code}', author: GymSettings.gymName);
    // CR80 (ATM card) size.
    const card = PdfPageFormat(85.6 * PdfPageFormat.mm, 54 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm);
    doc.addPage(pw.Page(pageFormat: card, build: (_) => front()));
    return doc.save();
  }

  // ---------------- actions ----------------

  static Future<void> printPdf(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  static Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
