import 'dart:convert';

import '../db/gym_db.dart';

/// Combo ka ek hissa: [productId] ki [qty] (units).
class ComboPart {
  final String productId;
  final double qty;
  const ComboPart(this.productId, this.qty);

  Map<String, Object?> toJson() => {'id': productId, 'qty': qty};
}

/// Counter ki cheez: supplement / drink / accessory (item), service (locker, steam — stock nahi),
/// ya combo (kai items ek qeemat par).
class Product {
  final String id;
  final String name;
  final String category;
  final String kind; // item / service / combo
  final String barcode;
  final double price; // farokht qeemat (fi unit)
  final double cost; // khareed qeemat (fi unit) — munafa ke liye
  final double lowStock; // is se kam => alert
  final String servingName; // e.g. scoop (khali = serving sale nahi)
  final double servingsPerUnit; // e.g. 1 dabba = 60 scoop
  final double servingPrice; // fi scoop qeemat
  final List<ComboPart> parts;
  final bool active;
  final String notes;

  /// Hisaab se (stock_moves) — DB column nahi.
  final double stock;

  const Product({
    required this.id,
    required this.name,
    this.category = 'Supplements',
    this.kind = 'item',
    this.barcode = '',
    this.price = 0,
    this.cost = 0,
    this.lowStock = 0,
    this.servingName = '',
    this.servingsPerUnit = 0,
    this.servingPrice = 0,
    this.parts = const [],
    this.active = true,
    this.notes = '',
    this.stock = 0,
  });

  bool get isService => kind == 'service';
  bool get isCombo => kind == 'combo';
  bool get tracksStock => kind == 'item';
  bool get hasServing => kind == 'item' && servingName.trim().isNotEmpty && servingsPerUnit > 0 && servingPrice > 0;
  bool get isLow => tracksStock && stock <= lowStock + 0.0001;
  bool get isOut => tracksStock && stock <= 0.0001;

  static List<ComboPart> parseParts(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final d = json.decode(raw);
      if (d is! List) return const [];
      final out = <ComboPart>[];
      for (final e in d) {
        if (e is Map) {
          final id = '${e['id'] ?? ''}';
          final q = e['qty'];
          final qty = q is num ? q.toDouble() : double.tryParse('$q') ?? 0;
          if (id.isNotEmpty && qty > 0) out.add(ComboPart(id, qty));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String encodeParts(List<ComboPart> parts) => json.encode([for (final p in parts) p.toJson()]);

  factory Product.fromMap(Map<String, Object?> m, {double stock = 0}) => Product(
        id: mStr(m, 'id'),
        name: mStr(m, 'name'),
        category: mStr(m, 'category').isEmpty ? 'Other' : mStr(m, 'category'),
        kind: mStr(m, 'kind').isEmpty ? 'item' : mStr(m, 'kind'),
        barcode: mStr(m, 'barcode'),
        price: mDbl(m, 'price'),
        cost: mDbl(m, 'cost'),
        lowStock: mDbl(m, 'low_stock'),
        servingName: mStr(m, 'serving_name'),
        servingsPerUnit: mDbl(m, 'servings_per_unit'),
        servingPrice: mDbl(m, 'serving_price'),
        parts: parseParts(mStr(m, 'parts')),
        active: mBool(m, 'active'),
        notes: mStr(m, 'notes'),
        stock: stock,
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'category': category,
        'kind': kind,
        'barcode': barcode,
        'price': price,
        'cost': cost,
        'low_stock': lowStock,
        'serving_name': servingName,
        'servings_per_unit': servingsPerUnit,
        'serving_price': servingPrice,
        'parts': encodeParts(parts),
        'active': active ? 1 : 0,
        'notes': notes,
      };

  Product withStock(double s) => Product(
        id: id,
        name: name,
        category: category,
        kind: kind,
        barcode: barcode,
        price: price,
        cost: cost,
        lowStock: lowStock,
        servingName: servingName,
        servingsPerUnit: servingsPerUnit,
        servingPrice: servingPrice,
        parts: parts,
        active: active,
        notes: notes,
        stock: s,
      );
}

/// Counter ki tokri ki ek line (sirf memory mein).
class CartLine {
  final Product product;

  /// true = scoop / serving ke hisaab se.
  final bool serving;
  double qty;
  double price;

  CartLine({required this.product, required this.serving, required this.qty, required this.price});

  String get key => '${product.id}|${serving ? 's' : 'u'}';
  double get total => qty * price;
  String get unitLabel => serving ? product.servingName : 'pc';

  /// Is line se kitne units stock se nikalne hain (combo / service par 0 — combo ke hisse alag).
  double get stockUnits {
    if (!product.tracksStock) return 0;
    if (serving && product.servingsPerUnit > 0) return qty / product.servingsPerUnit;
    return qty;
  }

  /// Is line ki khareed qeemat (munafa ke liye).
  double costWith(Map<String, Product> byId) {
    if (product.isCombo) {
      var c = 0.0;
      for (final part in product.parts) {
        c += (byId[part.productId]?.cost ?? 0) * part.qty;
      }
      return c * qty;
    }
    if (product.isService) return 0;
    return product.cost * stockUnits;
  }
}

class Sale {
  final String id;
  final String? memberId;
  final String customerName;
  final String date;
  final double subtotal;
  final double discount;
  final double total;
  final double paid;
  final String method;
  final String receiptNo;
  final String note;
  final String byUser;
  final String status; // done / void
  final int createdAt;
  final String memberName; // join
  final String memberCode;
  final String memberPhone;

  const Sale({
    required this.id,
    this.memberId,
    this.customerName = '',
    required this.date,
    this.subtotal = 0,
    this.discount = 0,
    this.total = 0,
    this.paid = 0,
    this.method = 'Cash',
    this.receiptNo = '',
    this.note = '',
    this.byUser = '',
    this.status = 'done',
    this.createdAt = 0,
    this.memberName = '',
    this.memberCode = '',
    this.memberPhone = '',
  });

  bool get isVoid => status == 'void';
  double get credit => (total - paid) > 0.5 ? total - paid : 0;
  String get buyer => memberName.isNotEmpty ? memberName : (customerName.isNotEmpty ? customerName : 'Walk-in');

  factory Sale.fromMap(Map<String, Object?> m) => Sale(
        id: mStr(m, 'id'),
        memberId: mStrN(m, 'member_id'),
        customerName: mStr(m, 'customer_name'),
        date: mStr(m, 'date'),
        subtotal: mDbl(m, 'subtotal'),
        discount: mDbl(m, 'discount'),
        total: mDbl(m, 'total'),
        paid: mDbl(m, 'paid'),
        method: mStr(m, 'method').isEmpty ? 'Cash' : mStr(m, 'method'),
        receiptNo: mStr(m, 'receipt_no'),
        note: mStr(m, 'note'),
        byUser: mStr(m, 'by_user'),
        status: mStr(m, 'status').isEmpty ? 'done' : mStr(m, 'status'),
        createdAt: mInt(m, 'created_at'),
        memberName: mStr(m, 'member_name'),
        memberCode: mStr(m, 'member_code'),
        memberPhone: mStr(m, 'member_phone'),
      );
}

class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final String name;
  final double qty;
  final String unit;
  final double price;
  final double cost;
  final double total;

  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.name,
    required this.qty,
    this.unit = 'pc',
    this.price = 0,
    this.cost = 0,
    this.total = 0,
  });

  factory SaleItem.fromMap(Map<String, Object?> m) => SaleItem(
        id: mStr(m, 'id'),
        saleId: mStr(m, 'sale_id'),
        productId: mStr(m, 'product_id'),
        name: mStr(m, 'name'),
        qty: mDbl(m, 'qty'),
        unit: mStr(m, 'unit').isEmpty ? 'pc' : mStr(m, 'unit'),
        price: mDbl(m, 'price'),
        cost: mDbl(m, 'cost'),
        total: mDbl(m, 'total'),
      );
}

/// Stock ki ek harkat: purchase (+), sale (-), adjust (±), void (wapas +).
class StockMove {
  final String id;
  final String productId;
  final double qty;
  final String kind;
  final String? refId;
  final String date;
  final double cost;
  final String? expiry;
  final String supplier;
  final String note;
  final int createdAt;
  final String productName; // join

  const StockMove({
    required this.id,
    required this.productId,
    required this.qty,
    required this.kind,
    this.refId,
    required this.date,
    this.cost = 0,
    this.expiry,
    this.supplier = '',
    this.note = '',
    this.createdAt = 0,
    this.productName = '',
  });

  factory StockMove.fromMap(Map<String, Object?> m) => StockMove(
        id: mStr(m, 'id'),
        productId: mStr(m, 'product_id'),
        qty: mDbl(m, 'qty'),
        kind: mStr(m, 'kind'),
        refId: mStrN(m, 'ref_id'),
        date: mStr(m, 'date'),
        cost: mDbl(m, 'cost'),
        expiry: mStrN(m, 'expiry'),
        supplier: mStr(m, 'supplier'),
        note: mStr(m, 'note'),
        createdAt: mInt(m, 'created_at'),
        productName: mStr(m, 'product_name'),
      );
}

/// Kisi product ka bacha hua maal jo [expiry] par khatam hota hai.
class ExpiryLot {
  final Product product;
  final String expiry;
  final double qty;
  const ExpiryLot(this.product, this.expiry, this.qty);
}

/// FIFO: purana maal pehle bikta hai, is liye bacha hua [stock] sab se naye purchases mein hai.
/// [purchases] = (tareekh/created ke hisaab se koi bhi tarteeb), wapas: (expiry, qty) jin mein abhi maal hai.
List<(String, double)> remainingLots(double stock, List<StockMove> purchases) {
  final sorted = [...purchases]..sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });
  var left = stock;
  final out = <(String, double)>[];
  for (final m in sorted) {
    if (left <= 0.0001) break;
    final take = m.qty < left ? m.qty : left;
    left -= take;
    final e = m.expiry;
    if (e != null && e.isNotEmpty && take > 0) out.add((e, take));
  }
  return out;
}
