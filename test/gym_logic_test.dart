import 'package:flutter_test/flutter_test.dart';

import 'package:hanna_fitness/models/models.dart';
import 'package:hanna_fitness/screens/members_screen.dart' show matchesText, matchesFilter, MemberFilter;
import 'package:hanna_fitness/services/messaging.dart';
import 'package:hanna_fitness/utils/fmt.dart';

MemberSummary _summary({String? endDate, double dues = 0, String status = 'active', String code = 'EG-0012'}) =>
    MemberSummary(
      member: Member(id: 'm1', code: code, name: 'Asam Hameed', phone: '0300-1234567', status: status),
      hasPhoto: false,
      endDate: endDate,
      planName: 'Monthly',
      dues: dues,
    );

String _inDays(int d) => Fmt.ymd(Fmt.today().add(Duration(days: d)));

void main() {
  group('dates', () {
    test('ymd / parseYmd round trip', () {
      final d = DateTime.utc(2026, 3, 9);
      expect(Fmt.ymd(d), '2026-03-09');
      expect(Fmt.parseYmd('2026-03-09'), d);
      expect(Fmt.parseYmd('bad'), isNull);
    });

    test('addMonths clamps to the last day of the month', () {
      expect(Fmt.addMonths(DateTime.utc(2026, 1, 31), 1), DateTime.utc(2026, 2, 28));
      expect(Fmt.addMonths(DateTime.utc(2028, 1, 31), 1), DateTime.utc(2028, 2, 29));
      expect(Fmt.addMonths(DateTime.utc(2026, 11, 15), 3), DateTime.utc(2027, 2, 15));
      expect(Fmt.addMonths(DateTime.utc(2026, 1, 15), -1), DateTime.utc(2025, 12, 15));
      expect(Fmt.addMonths(DateTime.utc(2026, 1, 15), -13), DateTime.utc(2024, 12, 15));
    });

    test('plan end date is inclusive', () {
      expect(Fmt.planEnd(DateTime.utc(2026, 1, 1), 1, 'month'), DateTime.utc(2026, 1, 31));
      expect(Fmt.planEnd(DateTime.utc(2026, 3, 15), 1, 'year'), DateTime.utc(2027, 3, 14));
      expect(Fmt.planEnd(DateTime.utc(2026, 3, 15), 1, 'day'), DateTime.utc(2026, 3, 15));
      expect(Fmt.planEnd(DateTime.utc(2026, 3, 1), 2, 'week'), DateTime.utc(2026, 3, 14));
      expect(Fmt.planEnd(DateTime.utc(2026, 3, 1), 3, 'month'), DateTime.utc(2026, 5, 31));
    });

    test('days left', () {
      expect(Fmt.daysLeft(_inDays(0)), 0);
      expect(Fmt.daysLeft(_inDays(7)), 7);
      expect(Fmt.daysLeft(_inDays(-2)), -2);
    });
  });

  group('phone + text', () {
    test('WhatsApp digits for Pakistani numbers', () {
      expect(Fmt.whatsAppDigits('0300-1234567'), '923001234567');
      expect(Fmt.whatsAppDigits('+92 300 1234567'), '923001234567');
      expect(Fmt.whatsAppDigits('3001234567'), '923001234567');
      expect(Fmt.whatsAppDigits('0092 300 1234567'), '923001234567');
    });

    test('initials', () {
      expect(Fmt.initials('Asam Hameed'), 'AH');
      expect(Fmt.initials('ali'), 'A');
      expect(Fmt.initials('  '), '?');
    });

    test('number parsing', () {
      expect(Fmt.toDouble('12,500'), 12500);
      expect(Fmt.toDouble(''), 0);
      expect(Fmt.toInt('7'), 7);
    });
  });

  group('membership state', () {
    test('active / expiring / expired / none / inactive', () {
      expect(_summary(endDate: _inDays(30)).stateFor(5), MemberState.active);
      expect(_summary(endDate: _inDays(3)).stateFor(5), MemberState.expiring);
      expect(_summary(endDate: _inDays(0)).stateFor(5), MemberState.expiring);
      expect(_summary(endDate: _inDays(-1)).stateFor(5), MemberState.expired);
      expect(_summary().stateFor(5), MemberState.none);
      expect(_summary(endDate: _inDays(30), status: 'inactive').stateFor(5), MemberState.inactive);
    });

    test('filters', () {
      expect(matchesFilter(_summary(endDate: _inDays(3)), MemberFilter.active, 5), isTrue);
      expect(matchesFilter(_summary(endDate: _inDays(3)), MemberFilter.expiring, 5), isTrue);
      expect(matchesFilter(_summary(endDate: _inDays(-3)), MemberFilter.expired, 5), isTrue);
      expect(matchesFilter(_summary(endDate: _inDays(30), dues: 500), MemberFilter.dues, 5), isTrue);
      expect(matchesFilter(_summary(endDate: _inDays(30), status: 'inactive'), MemberFilter.all, 5), isFalse);
    });

    test('search by name, code number and phone', () {
      final s = _summary(endDate: _inDays(10));
      expect(matchesText(s, 'asam'), isTrue);
      expect(matchesText(s, '12'), isTrue);
      expect(matchesText(s, 'EG-0012'), isTrue);
      expect(matchesText(s, '1234567'), isTrue);
      expect(matchesText(s, 'zzz'), isFalse);
    });
  });

  group('messages', () {
    test('reminder text fills placeholders', () {
      final t = Messaging.reminderText(_summary(endDate: '2026-12-01', dues: 1500));
      expect(t, contains('Asam Hameed'));
      expect(t, contains('My Gym'));
      expect(t, contains('Monthly'));
      expect(t, contains('1 Dec 2026'));
      expect(t, contains('1,500'));
      expect(t, isNot(contains('{')));
    });

    test('receipt text', () {
      const p = Payment(
        id: 'p1',
        memberId: 'm1',
        amount: 3000,
        method: 'Cash',
        paidOn: '2026-11-23',
        receiptNo: 'R-AB12-0001',
        memberName: 'Asam Hameed',
        memberCode: 'EG-0012',
      );
      final t = Messaging.receiptText(p, balance: 0);
      expect(t, contains('R-AB12-0001'));
      expect(t, contains('3,000'));
      expect(t, contains('Clear'));
    });
  });
}
