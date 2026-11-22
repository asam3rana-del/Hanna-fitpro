import 'package:shared_preferences/shared_preferences.dart';

import '../models/shop_models.dart';
import '../services/session.dart';
import '../sync/device_tag.dart';
import '../utils/fmt.dart';
import 'gym_db.dart';

GymDb get _db => GymDb.instance;

/// Counter ki ek muddat ka khulasa.
class ShopStats {
  final double total; // kul farokht (discount ke baad)
  final double paid; // naqad wasool
  final double credit; // members ke udhaar mein gaya
  final double cost; // bikne wale maal ki khareed qeemat
  final int count;
  final List<(String, double, double)> best; // (naam, qty, raqam)

  const ShopStats({
    required this.total,
    required this.paid,
    required this.credit,
    required this.cost,
    required this.count,
    required this.best,
  });

  double get grossProfit => total - cost;
}

/// Counter / shop: products, stock (harkat se hisaab — sync mein kabhi ghalat nahi), sale, udhaar, expiry.
class ShopRepo {
  ShopRepo._();

  static const categories = <String>[
    'Supplements',
    'Drinks & Shakes',
    'Snacks',
    'Accessories',
    'Apparel',
    'Services',
    'Combos',
    'Other',
  ];

  // ---------------- products + stock ----------------

  /// product_id => units (purchase + adjust - sale + void).
  static Future<Map<String, double>> stockMap() async {
    final r = await _db.rows('SELECT product_id, SUM(qty) AS q FROM stock_moves WHERE deleted = 0 GROUP BY product_id');
    return {for (final row in r) mStr(row, 'product_id'): mDbl(row, 'q')};
  }

  static Future<List<Product>> products({bool activeOnly = false}) async {
    final r = await _db.rows(
      'SELECT * FROM products WHERE deleted = 0 ${activeOnly ? 'AND active = 1' : ''} ORDER BY category, name COLLATE NOCASE',
    );
    final stock = await stockMap();
    final base = [for (final row in r) Product.fromMap(row, stock: stock[mStr(row, 'id')] ?? 0)];
    final byId = {for (final p in base) p.id: p};
    // Combo: jitne poore combo bana sakein (sab se kam wala hissa).
    return [
      for (final p in base)
        if (p.isCombo) p.withStock(comboStock(p, byId)) else p,
    ];
  }

  static double comboStock(Product combo, Map<String, Product> byId) {
    if (combo.parts.isEmpty) return 0;
    double? best;
    for (final part in combo.parts) {
      final s = byId[part.productId]?.stock ?? 0;
      final can = part.qty <= 0 ? 0.0 : (s / part.qty).floorToDouble();
      if (best == null || can < best) best = can;
    }
    return best ?? 0;
  }

  static Future<Product?> byBarcode(String code) async {
    final t = code.trim();
    if (t.isEmpty) return null;
    final all = await products(activeOnly: true);
    for (final p in all) {
      if (p.barcode.isNotEmpty && p.barcode.toLowerCase() == t.toLowerCase()) return p;
    }
    return null;
  }

  static Future<String> create(Product p) => _db.insert('products', p.toMap());
  static Future<void> save(Product p) => _db.update('products', p.id, p.toMap());
  static Future<void> delete(String id) => _db.softDelete('products', id);

  /// Maal aaya (purchase). [cost] fi unit; product ki khareed qeemat bhi isi par.
  static Future<void> stockIn({
    required String productId,
    required double qty,
    double cost = 0,
    String? expiry,
    String supplier = '',
    String note = '',
    DateTime? date,
  }) async {
    await _db.insert('stock_moves', {
      'product_id': productId,
      'qty': qty,
      'kind': 'purchase',
      'ref_id': null,
      'date': Fmt.ymd(date ?? Fmt.today()),
      'cost': cost,
      'expiry': (expiry == null || expiry.isEmpty) ? null : expiry,
      'supplier': supplier,
      'note': note,
    });
    if (cost > 0) await _db.update('products', productId, {'cost': cost});
  }

  /// Stock theek karna: [qty] + ya - (toot gaya, expire, ginti ka farq).
  static Future<void> adjust({required String productId, required double qty, String note = ''}) =>
      _db.insert('stock_moves', {
        'product_id': productId,
        'qty': qty,
        'kind': 'adjust',
        'ref_id': null,
        'date': Fmt.todayYmd(),
        'cost': 0,
        'expiry': null,
        'supplier': '',
        'note': note,
      });

  static Future<List<StockMove>> movesFor(String productId, {int limit = 200}) async {
    final r = await _db.rows(
      'SELECT * FROM stock_moves WHERE product_id = ? AND deleted = 0 ORDER BY date DESC, created_at DESC LIMIT $limit',
      [productId],
    );
    return r.map(StockMove.fromMap).toList();
  }

  static Future<double> purchaseTotal(String fromYmd, String toYmd) => _db.sum(
        "SELECT COALESCE(SUM(qty * cost), 0) FROM stock_moves WHERE deleted = 0 AND kind = 'purchase' "
        'AND date >= ? AND date <= ?',
        [fromYmd, toYmd],
      );

  static Future<List<StockMove>> purchasesBetween(String fromYmd, String toYmd) async {
    final r = await _db.rows(
      "SELECT sm.*, p.name AS product_name FROM stock_moves sm LEFT JOIN products p ON p.id = sm.product_id "
      "WHERE sm.deleted = 0 AND sm.kind = 'purchase' AND sm.date >= ? AND sm.date <= ? ORDER BY sm.date DESC, sm.created_at DESC",
      [fromYmd, toYmd],
    );
    return r.map(StockMove.fromMap).toList();
  }

  /// Jo maal [days] din mein expire hoga (ya ho chuka) aur abhi stock mein hai.
  static Future<List<ExpiryLot>> expiring({int days = 60}) async {
    final prods = await products();
    final r = await _db.rows(
      "SELECT * FROM stock_moves WHERE deleted = 0 AND kind = 'purchase' AND expiry IS NOT NULL AND expiry != ''",
    );
    final byProduct = <String, List<StockMove>>{};
    for (final row in r) {
      final m = StockMove.fromMap(row);
      byProduct.putIfAbsent(m.productId, () => []).add(m);
    }
    // Saari purchases chahiye (bina expiry wali bhi) taake FIFO sahi bane.
    final all = await _db.rows("SELECT * FROM stock_moves WHERE deleted = 0 AND kind = 'purchase'");
    final allBy = <String, List<StockMove>>{};
    for (final row in all) {
      final m = StockMove.fromMap(row);
      allBy.putIfAbsent(m.productId, () => []).add(m);
    }
    final limit = Fmt.ymd(Fmt.today().add(Duration(days: days)));
    final out = <ExpiryLot>[];
    for (final p in prods) {
      if (!p.tracksStock || p.stock <= 0.0001 || !byProduct.containsKey(p.id)) continue;
      for (final (exp, qty) in remainingLots(p.stock, allBy[p.id] ?? const [])) {
        if (exp.compareTo(limit) <= 0) out.add(ExpiryLot(p, exp, qty));
      }
    }
    out.sort((a, b) => a.expiry.compareTo(b.expiry));
    return out;
  }

  // ---------------- sale ----------------

  static Future<String> nextReceipt() async {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt('sale_seq') ?? 0) + 1;
    await prefs.setInt('sale_seq', n);
    return 'S-${DeviceTag.current}-${n.toString().padLeft(4, '0')}';
  }

  /// Bill save: sale + items + stock harkat ek saath. Member ho to kam diya hua hissa us ke baqaye mein.
  static Future<Sale> checkout({
    required List<CartLine> lines,
    required Map<String, Product> byId,
    String? memberId,
    String customerName = '',
    double discount = 0,
    required double paid,
    String method = 'Cash',
    String note = '',
  }) async {
    final subtotal = lines.fold<double>(0, (a, l) => a + l.total);
    final total = (subtotal - discount).clamp(0, double.infinity).toDouble();
    // Walk-in (bina member) par udhaar nahi: poori raqam.
    final paidNow = memberId == null ? total : paid.clamp(0, total).toDouble();
    final saleId = GymDb.newId();
    final today = Fmt.todayYmd();
    final receipt = await nextReceipt();
    final rows = <(String, Map<String, Object?>)>[
      (
        'sales',
        {
          'id': saleId,
          'member_id': memberId,
          'customer_name': customerName,
          'date': today,
          'subtotal': subtotal,
          'discount': discount,
          'total': total,
          'paid': paidNow,
          'method': method,
          'receipt_no': receipt,
          'note': note,
          'by_user': Session.displayName.isEmpty ? (Session.username ?? '') : Session.displayName,
          'status': 'done',
        }
      ),
    ];
    for (final l in lines) {
      rows.add((
        'sale_items',
        {
          'sale_id': saleId,
          'product_id': l.product.id,
          'name': l.serving ? '${l.product.name} (${l.product.servingName})' : l.product.name,
          'qty': l.qty,
          'unit': l.unitLabel,
          'price': l.price,
          'cost': l.costWith(byId),
          'total': l.total,
        }
      ));
      if (l.product.tracksStock) {
        rows.add(('stock_moves', _move(l.product.id, -l.stockUnits, 'sale', saleId, today)));
      } else if (l.product.isCombo) {
        for (final part in l.product.parts) {
          rows.add(('stock_moves', _move(part.productId, -(part.qty * l.qty), 'sale', saleId, today)));
        }
      }
    }
    await _db.insertAll(rows);
    final s = await sale(saleId);
    return s!;
  }

  static Map<String, Object?> _move(String productId, double qty, String kind, String ref, String date) => {
        'product_id': productId,
        'qty': qty,
        'kind': kind,
        'ref_id': ref,
        'date': date,
        'cost': 0,
        'expiry': null,
        'supplier': '',
        'note': '',
      };

  static const _join = 'SELECT s.*, m.name AS member_name, m.code AS member_code, m.phone AS member_phone '
      'FROM sales s LEFT JOIN members m ON m.id = s.member_id WHERE s.deleted = 0';

  static Future<Sale?> sale(String id) async {
    final r = await _db.rows('$_join AND s.id = ?', [id]);
    return r.isEmpty ? null : Sale.fromMap(r.first);
  }

  static Future<List<SaleItem>> items(String saleId) async {
    final r = await _db.rows('SELECT * FROM sale_items WHERE sale_id = ? AND deleted = 0 ORDER BY created_at', [saleId]);
    return r.map(SaleItem.fromMap).toList();
  }

  static Future<List<Sale>> salesBetween(String fromYmd, String toYmd) async {
    final r = await _db.rows('$_join AND s.date >= ? AND s.date <= ? ORDER BY s.date DESC, s.created_at DESC', [fromYmd, toYmd]);
    return r.map(Sale.fromMap).toList();
  }

  static Future<List<Sale>> salesForMember(String memberId) async {
    final r = await _db.rows('$_join AND s.member_id = ? ORDER BY s.date DESC, s.created_at DESC', [memberId]);
    return r.map(Sale.fromMap).toList();
  }

  /// Bill cancel: stock wapas, udhaar khatam (sale `void`).
  static Future<void> voidSale(Sale s) async {
    if (s.isVoid) return;
    final moves = await _db.rows(
      "SELECT * FROM stock_moves WHERE ref_id = ? AND kind = 'sale' AND deleted = 0",
      [s.id],
    );
    final rows = <(String, Map<String, Object?>)>[
      for (final m in moves) ('stock_moves', _move(mStr(m, 'product_id'), -mDbl(m, 'qty'), 'void', s.id, Fmt.todayYmd())),
    ];
    if (rows.isNotEmpty) await _db.insertAll(rows);
    await _db.update('sales', s.id, {'status': 'void'});
  }

  static Future<ShopStats> stats(String fromYmd, String toYmd) async {
    const live = "s.deleted = 0 AND s.status != 'void' AND s.date >= ? AND s.date <= ?";
    final sums = await _db.rows(
      'SELECT COALESCE(SUM(s.total), 0) AS t, COALESCE(SUM(s.paid), 0) AS p, COUNT(*) AS c FROM sales s WHERE $live',
      [fromYmd, toYmd],
    );
    final cost = await _db.sum(
      'SELECT COALESCE(SUM(si.cost), 0) FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE si.deleted = 0 AND $live',
      [fromYmd, toYmd],
    );
    final best = await _db.rows(
      'SELECT si.name AS n, SUM(si.qty) AS q, SUM(si.total) AS t FROM sale_items si JOIN sales s ON s.id = si.sale_id '
      'WHERE si.deleted = 0 AND $live GROUP BY si.product_id, si.name ORDER BY t DESC LIMIT 10',
      [fromYmd, toYmd],
    );
    final row = sums.isEmpty ? <String, Object?>{} : sums.first;
    final total = mDbl(row, 't');
    final paid = mDbl(row, 'p');
    return ShopStats(
      total: total,
      paid: paid,
      credit: (total - paid) > 0 ? total - paid : 0,
      cost: cost,
      count: mInt(row, 'c'),
      best: [for (final b in best) (mStr(b, 'n'), mDbl(b, 'q'), mDbl(b, 't'))],
    );
  }

  /// Naqad wasooli (dashboard / reports): counter par us din jo paisa aaya.
  static Future<double> cashBetween(String fromYmd, String toYmd) => _db.sum(
        "SELECT COALESCE(SUM(paid), 0) FROM sales WHERE deleted = 0 AND status != 'void' AND date >= ? AND date <= ?",
        [fromYmd, toYmd],
      );
}
