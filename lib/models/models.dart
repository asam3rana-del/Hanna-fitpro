import '../db/gym_db.dart';
import '../utils/fmt.dart';

/// Membership ki haalat (list filters, rang aur reminders ke liye).
enum MemberState { active, expiring, expired, none, inactive }

class Member {
  final String id;
  final String code;
  final String name;
  final String phone;
  final String cnic;
  final String gender; // male / female / other / ''
  final String? dob;
  final String address;
  final String emergencyName;
  final String emergencyPhone;
  final String bloodGroup;
  final String? joinedOn;
  final String? trainerId;
  final String timing; // morning / evening / ladies / ''
  final String goal;
  final double heightCm;
  final String notes;
  final String status; // active / inactive

  const Member({
    required this.id,
    required this.code,
    required this.name,
    this.phone = '',
    this.cnic = '',
    this.gender = '',
    this.dob,
    this.address = '',
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.bloodGroup = '',
    this.joinedOn,
    this.trainerId,
    this.timing = '',
    this.goal = '',
    this.heightCm = 0,
    this.notes = '',
    this.status = 'active',
  });

  factory Member.fromMap(Map<String, Object?> m) => Member(
        id: mStr(m, 'id'),
        code: mStr(m, 'code'),
        name: mStr(m, 'name'),
        phone: mStr(m, 'phone'),
        cnic: mStr(m, 'cnic'),
        gender: mStr(m, 'gender'),
        dob: mStrN(m, 'dob'),
        address: mStr(m, 'address'),
        emergencyName: mStr(m, 'emergency_name'),
        emergencyPhone: mStr(m, 'emergency_phone'),
        bloodGroup: mStr(m, 'blood_group'),
        joinedOn: mStrN(m, 'joined_on'),
        trainerId: mStrN(m, 'trainer_id'),
        timing: mStr(m, 'timing'),
        goal: mStr(m, 'goal'),
        heightCm: mDbl(m, 'height_cm'),
        notes: mStr(m, 'notes'),
        status: mStr(m, 'status').isEmpty ? 'active' : mStr(m, 'status'),
      );

  /// Photo is mein nahi (alag column, sirf zaroorat par).
  Map<String, Object?> toMap() => {
        'code': code,
        'name': name,
        'phone': phone,
        'cnic': cnic,
        'gender': gender,
        'dob': dob,
        'address': address,
        'emergency_name': emergencyName,
        'emergency_phone': emergencyPhone,
        'blood_group': bloodGroup,
        'joined_on': joinedOn,
        'trainer_id': trainerId,
        'timing': timing,
        'goal': goal,
        'height_cm': heightCm,
        'notes': notes,
        'status': status,
      };
}

/// List / dashboard ke liye member + us ki maujooda membership ka khulasa.
class MemberSummary {
  final Member member;
  final bool hasPhoto;
  final String? endDate;
  final String? planName;
  final double dues;
  final String? lastVisit;

  const MemberSummary({
    required this.member,
    required this.hasPhoto,
    this.endDate,
    this.planName,
    this.dues = 0,
    this.lastVisit,
  });

  factory MemberSummary.fromMap(Map<String, Object?> m) => MemberSummary(
        member: Member.fromMap(m),
        hasPhoto: mInt(m, 'has_photo') != 0,
        endDate: mStrN(m, 'end_date'),
        planName: mStrN(m, 'plan_name'),
        dues: mDbl(m, 'dues'),
        lastVisit: mStrN(m, 'last_visit'),
      );

  int get daysLeft => Fmt.daysLeft(endDate);

  MemberState stateFor(int reminderDays) {
    if (member.status == 'inactive') return MemberState.inactive;
    if (endDate == null) return MemberState.none;
    final d = daysLeft;
    if (d < 0) return MemberState.expired;
    if (d <= reminderDays) return MemberState.expiring;
    return MemberState.active;
  }
}

class Plan {
  final String id;
  final String name;
  final String kind; // gym / pt
  final int durationValue;
  final String durationUnit; // day / week / month / year
  final double price;
  final String description;
  final bool active;
  final int sort;

  const Plan({
    required this.id,
    required this.name,
    this.kind = 'gym',
    this.durationValue = 1,
    this.durationUnit = 'month',
    this.price = 0,
    this.description = '',
    this.active = true,
    this.sort = 0,
  });

  factory Plan.fromMap(Map<String, Object?> m) => Plan(
        id: mStr(m, 'id'),
        name: mStr(m, 'name'),
        kind: mStr(m, 'kind').isEmpty ? 'gym' : mStr(m, 'kind'),
        durationValue: mInt(m, 'duration_value') < 1 ? 1 : mInt(m, 'duration_value'),
        durationUnit: mStr(m, 'duration_unit').isEmpty ? 'month' : mStr(m, 'duration_unit'),
        price: mDbl(m, 'price'),
        description: mStr(m, 'description'),
        active: mBool(m, 'active'),
        sort: mInt(m, 'sort'),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'kind': kind,
        'duration_value': durationValue,
        'duration_unit': durationUnit,
        'price': price,
        'description': description,
        'active': active ? 1 : 0,
        'sort': sort,
      };
}

class Membership {
  final String id;
  final String memberId;
  final String? planId;
  final String planName;
  final String kind;
  final String? trainerId;
  final String startDate;
  final String endDate;
  final double price;
  final double admissionFee;
  final double discount;
  final double total;
  final int frozenDays;
  final String note;
  final String status; // active / cancelled
  final int createdAt;

  const Membership({
    required this.id,
    required this.memberId,
    this.planId,
    required this.planName,
    this.kind = 'gym',
    this.trainerId,
    required this.startDate,
    required this.endDate,
    this.price = 0,
    this.admissionFee = 0,
    this.discount = 0,
    this.total = 0,
    this.frozenDays = 0,
    this.note = '',
    this.status = 'active',
    this.createdAt = 0,
  });

  factory Membership.fromMap(Map<String, Object?> m) => Membership(
        id: mStr(m, 'id'),
        memberId: mStr(m, 'member_id'),
        planId: mStrN(m, 'plan_id'),
        planName: mStr(m, 'plan_name'),
        kind: mStr(m, 'kind').isEmpty ? 'gym' : mStr(m, 'kind'),
        trainerId: mStrN(m, 'trainer_id'),
        startDate: mStr(m, 'start_date'),
        endDate: mStr(m, 'end_date'),
        price: mDbl(m, 'price'),
        admissionFee: mDbl(m, 'admission_fee'),
        discount: mDbl(m, 'discount'),
        total: mDbl(m, 'total'),
        frozenDays: mInt(m, 'frozen_days'),
        note: mStr(m, 'note'),
        status: mStr(m, 'status').isEmpty ? 'active' : mStr(m, 'status'),
        createdAt: mInt(m, 'created_at'),
      );

  bool get cancelled => status == 'cancelled';
}

class Payment {
  final String id;
  final String memberId;
  final String? membershipId;
  final double amount;
  final String method;
  final String paidOn;
  final String receiptNo;
  final String note;
  final String receivedBy;
  final int createdAt;

  /// Join se (list screens).
  final String memberName;
  final String memberCode;

  const Payment({
    required this.id,
    required this.memberId,
    this.membershipId,
    required this.amount,
    this.method = 'Cash',
    required this.paidOn,
    this.receiptNo = '',
    this.note = '',
    this.receivedBy = '',
    this.createdAt = 0,
    this.memberName = '',
    this.memberCode = '',
  });

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: mStr(m, 'id'),
        memberId: mStr(m, 'member_id'),
        membershipId: mStrN(m, 'membership_id'),
        amount: mDbl(m, 'amount'),
        method: mStr(m, 'method').isEmpty ? 'Cash' : mStr(m, 'method'),
        paidOn: mStr(m, 'paid_on'),
        receiptNo: mStr(m, 'receipt_no'),
        note: mStr(m, 'note'),
        receivedBy: mStr(m, 'received_by'),
        createdAt: mInt(m, 'created_at'),
        memberName: mStr(m, 'member_name'),
        memberCode: mStr(m, 'member_code'),
      );
}

class Attendance {
  final String id;
  final String memberId;
  final String date;
  final int? checkIn;
  final int? checkOut;
  final String memberName;
  final String memberCode;
  final bool hasPhoto;

  const Attendance({
    required this.id,
    required this.memberId,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.memberName = '',
    this.memberCode = '',
    this.hasPhoto = false,
  });

  factory Attendance.fromMap(Map<String, Object?> m) => Attendance(
        id: mStr(m, 'id'),
        memberId: mStr(m, 'member_id'),
        date: mStr(m, 'date'),
        checkIn: mIntN(m, 'check_in'),
        checkOut: mIntN(m, 'check_out'),
        memberName: mStr(m, 'member_name'),
        memberCode: mStr(m, 'member_code'),
        hasPhoto: mInt(m, 'has_photo') != 0,
      );
}

class Trainer {
  final String id;
  final String name;
  final String phone;
  final String specialty;
  final double salary;
  final double commissionPct;
  final bool active;
  final String notes;
  final int memberCount; // join se

  const Trainer({
    required this.id,
    required this.name,
    this.phone = '',
    this.specialty = '',
    this.salary = 0,
    this.commissionPct = 0,
    this.active = true,
    this.notes = '',
    this.memberCount = 0,
  });

  factory Trainer.fromMap(Map<String, Object?> m) => Trainer(
        id: mStr(m, 'id'),
        name: mStr(m, 'name'),
        phone: mStr(m, 'phone'),
        specialty: mStr(m, 'specialty'),
        salary: mDbl(m, 'salary'),
        commissionPct: mDbl(m, 'commission_pct'),
        active: mBool(m, 'active'),
        notes: mStr(m, 'notes'),
        memberCount: mInt(m, 'member_count'),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'phone': phone,
        'specialty': specialty,
        'salary': salary,
        'commission_pct': commissionPct,
        'active': active ? 1 : 0,
        'notes': notes,
      };
}

class Expense {
  final String id;
  final String category;
  final double amount;
  final String date;
  final String note;
  final String paidTo;
  final String method;

  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.note = '',
    this.paidTo = '',
    this.method = 'Cash',
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: mStr(m, 'id'),
        category: mStr(m, 'category'),
        amount: mDbl(m, 'amount'),
        date: mStr(m, 'date'),
        note: mStr(m, 'note'),
        paidTo: mStr(m, 'paid_to'),
        method: mStr(m, 'method').isEmpty ? 'Cash' : mStr(m, 'method'),
      );

  Map<String, Object?> toMap() => {
        'category': category,
        'amount': amount,
        'date': date,
        'note': note,
        'paid_to': paidTo,
        'method': method,
      };
}

class Measurement {
  final String id;
  final String memberId;
  final String date;
  final double weight;
  final double bodyFat;
  final double chest;
  final double waist;
  final double arms;
  final double thigh;
  final String note;

  const Measurement({
    required this.id,
    required this.memberId,
    required this.date,
    this.weight = 0,
    this.bodyFat = 0,
    this.chest = 0,
    this.waist = 0,
    this.arms = 0,
    this.thigh = 0,
    this.note = '',
  });

  factory Measurement.fromMap(Map<String, Object?> m) => Measurement(
        id: mStr(m, 'id'),
        memberId: mStr(m, 'member_id'),
        date: mStr(m, 'date'),
        weight: mDbl(m, 'weight'),
        bodyFat: mDbl(m, 'body_fat'),
        chest: mDbl(m, 'chest'),
        waist: mDbl(m, 'waist'),
        arms: mDbl(m, 'arms'),
        thigh: mDbl(m, 'thigh'),
        note: mStr(m, 'note'),
      );

  Map<String, Object?> toMap() => {
        'member_id': memberId,
        'date': date,
        'weight': weight,
        'body_fat': bodyFat,
        'chest': chest,
        'waist': waist,
        'arms': arms,
        'thigh': thigh,
        'note': note,
      };
}

class AppUser {
  final String id;
  final String username;
  final String displayName;
  final String passwordHash;
  final String role; // admin / manager / reception
  final bool active;

  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.passwordHash,
    required this.role,
    this.active = true,
  });

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: mStr(m, 'id'),
        username: mStr(m, 'username'),
        displayName: mStr(m, 'display_name'),
        passwordHash: mStr(m, 'password_hash'),
        role: mStr(m, 'role').isEmpty ? 'reception' : mStr(m, 'role'),
        active: mBool(m, 'active'),
      );
}
