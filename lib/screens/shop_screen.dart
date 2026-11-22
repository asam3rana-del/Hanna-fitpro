import 'package:flutter/material.dart';

import '../db/gym_repo.dart';
import '../db/shop_repo.dart';
import '../models/models.dart';
import '../models/shop_models.dart';
import '../services/messaging.dart';
import '../services/pdf_service.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'members_screen.dart';
import 'products_screen.dart';
import 'shop_sales_screen.dart';

/// Counter: protein, shakes, accessories, services — tez bill, barcode, scoop sale, member ka udhaar.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> with AutoRefresh {
  List<Product>? _products;
  final Map<String, CartLine> _cart = {};
  String _category = '';
  String _q = '';
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final p = await ShopRepo.products(activeOnly: true);
    if (mounted) setState(() => _products = p);
  }

  Map<String, Product> get _byId => {for (final p in _products ?? <Product>[]) p.id: p};

  double get _total => _cart.values.fold<double>(0, (a, l) => a + l.total);
  double get _count => _cart.values.fold<double>(0, (a, l) => a + l.qty);

  void _add(Product p, {bool serving = false}) {
    final key = '${p.id}|${serving ? 's' : 'u'}';
    final line = _cart[key];
    setState(() {
      if (line != null) {
        line.qty += 1;
      } else {
        _cart[key] = CartLine(product: p, serving: serving, qty: 1, price: serving ? p.servingPrice : p.price);
      }
    });
    final l = _cart[key]!;
    if ((p.tracksStock || p.isCombo) && l.stockUnits > p.stock + 0.0001 && !p.isCombo) {
      toast(context, Loc.t('Only ${Fmt.decimal(p.stock)} left in stock', 'اسٹاک میں صرف ${Fmt.decimal(p.stock)} باقی'));
    } else if (p.isCombo && l.qty > p.stock + 0.0001) {
      toast(context, Loc.t('Not enough stock for this combo', 'اس کومبو کے لیے اسٹاک کم ہے'));
    }
  }

  Future<void> _scan(String code) async {
    final t = code.trim();
    if (t.isEmpty) return;
    final p = await ShopRepo.byBarcode(t);
    if (!mounted) return;
    if (p != null) {
      _add(p);
      setState(() {
        _search.clear();
        _q = '';
      });
      _searchFocus.requestFocus();
      return;
    }
    final matches = _visible;
    if (matches.length == 1) {
      _add(matches.first);
      setState(() {
        _search.clear();
        _q = '';
      });
    }
  }

  List<Product> get _visible {
    final q = _q.trim().toLowerCase();
    return (_products ?? []).where((p) {
      if (_category.isNotEmpty && p.category != _category) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.barcode.toLowerCase() == q || p.category.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openCart() async {
    await showGymSheet<void>(
      context,
      title: Loc.t('Bill', 'بل'),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void refresh() {
          setSheet(() {});
          setState(() {});
        }

        return _CartPanel(
          cart: _cart,
          onChanged: refresh,
          onCheckout: () {
            Navigator.pop(ctx);
            _checkout();
          },
        );
      }),
    );
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final sale = await showGymSheet<Sale>(
      context,
      title: Loc.t('Checkout', 'ادائیگی'),
      builder: (ctx) => _CheckoutForm(lines: _cart.values.toList(), byId: _byId),
    );
    if (sale == null || !mounted) return;
    setState(_cart.clear);
    await showSaleReceipt(context, sale);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final list = _visible;
    final cats = <String>{for (final p in _products ?? <Product>[]) p.category}.toList()..sort();
    final grid = _products == null
        ? Center(child: CircularProgressIndicator(color: pal.gold))
        : (_products!.isEmpty
            ? EmptyState(
                icon: Icons.storefront_outlined,
                title: Loc.t('No products yet', 'ابھی کوئی پروڈکٹ نہیں'),
                subtitle: Loc.t('Add protein, drinks, accessories and services', 'پروٹین، ڈرنکس، ایکسیسریز اور سروسز شامل کریں'),
                action: Session.canManage
                    ? FilledButton.icon(
                        onPressed: () => push(context, const ProductsScreen()),
                        icon: const Icon(Icons.add),
                        label: Text(Loc.t('Add products', 'پروڈکٹس شامل کریں')),
                      )
                    : null,
              )
            : LayoutBuilder(builder: (context, c) {
                final cols = (c.maxWidth / 170).floor().clamp(2, 6).toInt();
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, wide ? 24 : 110),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _ProductTile(
                    p: list[i],
                    inCart: _cart.values.where((l) => l.product.id == list[i].id).fold<double>(0, (a, l) => a + l.qty),
                    onTap: () => _add(list[i]),
                    onServing: list[i].hasServing ? () => _add(list[i], serving: true) : null,
                  ),
                );
              }));

    final body = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          onChanged: (v) => setState(() => _q = v),
          onSubmitted: _scan,
          decoration: ThemeManager.field(
            Loc.t('Search or scan barcode', 'تلاش کریں یا بارکوڈ اسکین کریں'),
            icon: Icons.qr_code_scanner,
            suffix: _q.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, color: pal.muted),
                    onPressed: () => setState(() {
                      _search.clear();
                      _q = '';
                    }),
                  ),
          ),
        ),
      ),
      if (cats.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ChoiceChips<String>(
            options: [('', Loc.t('All', 'سب')), for (final c in cats) (c, c)],
            value: _category,
            onChanged: (v) => setState(() => _category = v),
          ),
        ),
      Expanded(child: grid),
    ]);

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(
        Loc.t('Counter', 'کاؤنٹر'),
        subtitle: Loc.t('Supplements · drinks · accessories · services', 'سپلیمنٹس · ڈرنکس · ایکسیسریز · سروسز'),
        actions: [
          IconButton(
            tooltip: Loc.t('Sales history', 'سیل ہسٹری'),
            onPressed: () => push(context, const ShopSalesScreen()),
            icon: Icon(Icons.receipt_long_outlined, color: pal.gold),
          ),
          IconButton(
            tooltip: Loc.t('Products & stock', 'پروڈکٹس اور اسٹاک'),
            onPressed: () => push(context, const ProductsScreen()),
            icon: Icon(Icons.inventory_2_outlined, color: pal.gold),
          ),
          const SyncBadge(),
          const SizedBox(width: 4),
        ],
      ),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: body),
              Container(
                width: 380,
                margin: const EdgeInsets.fromLTRB(0, 4, 16, 16),
                child: PCard(
                  padding: const EdgeInsets.all(16),
                  child: _CartPanel(cart: _cart, onChanged: () => setState(() {}), onCheckout: _checkout, scroll: true),
                ),
              ),
            ])
          : body,
      bottomSheet: wide || _cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                color: pal.bg,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Material(
                  color: pal.gold,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openCart,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      child: Row(children: [
                        Icon(Icons.shopping_bag, color: pal.onGold),
                        const SizedBox(width: 10),
                        Text(Loc.t('${Fmt.decimal(_count)} items', '${Fmt.decimal(_count)} آئٹمز'),
                            style: TextStyle(color: pal.onGold, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(Fmt.money(_total), style: TextStyle(color: pal.onGold, fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right, color: pal.onGold),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product p;
  final double inCart;
  final VoidCallback onTap;
  final VoidCallback? onServing;
  const _ProductTile({required this.p, required this.inCart, required this.onTap, this.onServing});

  IconData get _icon {
    switch (p.category) {
      case 'Supplements':
        return Icons.science_outlined;
      case 'Drinks & Shakes':
        return Icons.local_drink_outlined;
      case 'Snacks':
        return Icons.cookie_outlined;
      case 'Accessories':
        return Icons.sports_handball_outlined;
      case 'Apparel':
        return Icons.checkroom_outlined;
      case 'Services':
        return Icons.room_service_outlined;
      case 'Combos':
        return Icons.redeem_outlined;
      default:
        return Icons.shopping_basket_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockText = p.isService
        ? Loc.t('Service', 'سروس')
        : (p.isOut ? Loc.t('Out of stock', 'ختم') : Loc.t('Stock ${Fmt.decimal(p.stock)}', 'اسٹاک ${Fmt.decimal(p.stock)}'));
    final stockColor = p.isService ? pal.blue : (p.isOut ? pal.red : (p.isLow ? pal.amber : pal.green));
    return PCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      borderColor: inCart > 0 ? pal.gold : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: pal.goldSoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(_icon, color: pal.gold, size: 20),
          ),
          const Spacer(),
          if (inCart > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: pal.gold, borderRadius: BorderRadius.circular(20)),
              child: Text(Fmt.decimal(inCart), style: TextStyle(color: pal.onGold, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Text(p.name,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800, fontSize: 13.5)),
        ),
        Text(Fmt.money(p.price), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(
            child: Text(stockText,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: stockColor, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          if (onServing != null)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onServing,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: pal.purpleSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('+1 ${p.servingName}',
                    style: TextStyle(color: pal.purple, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// Tokri: lines, qty +/-, kul, aur "Checkout".
class _CartPanel extends StatelessWidget {
  final Map<String, CartLine> cart;
  final VoidCallback onChanged;
  final VoidCallback onCheckout;
  final bool scroll;
  const _CartPanel({required this.cart, required this.onChanged, required this.onCheckout, this.scroll = false});

  @override
  Widget build(BuildContext context) {
    final lines = cart.values.toList();
    final total = lines.fold<double>(0, (a, l) => a + l.total);
    final rows = <Widget>[
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.serving ? '${l.product.name} (${l.product.servingName})' : l.product.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                Text('${Fmt.money(l.price)} × ${Fmt.decimal(l.qty)} = ${Fmt.money(l.total)}',
                    style: TextStyle(color: pal.muted, fontSize: 12)),
              ]),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.remove_circle_outline, color: pal.muted),
              onPressed: () {
                l.qty -= 1;
                if (l.qty <= 0) cart.remove(l.key);
                onChanged();
              },
            ),
            Text(Fmt.decimal(l.qty), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.add_circle_outline, color: pal.gold),
              onPressed: () {
                l.qty += 1;
                onChanged();
              },
            ),
          ]),
        ),
    ];
    final footer = <Widget>[
      Divider(color: pal.border),
      Row(children: [
        Expanded(child: Text(Loc.t('Total', 'کل'), style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700))),
        Text(Fmt.money(total), style: TextStyle(color: pal.ink, fontSize: 22, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 12),
      GoldButton(
        label: Loc.t('CHECKOUT', 'بل بنائیں'),
        icon: Icons.point_of_sale,
        onPressed: lines.isEmpty ? null : onCheckout,
      ),
      if (lines.isNotEmpty)
        TextButton(
          onPressed: () {
            cart.clear();
            onChanged();
          },
          child: Text(Loc.t('Clear bill', 'بل صاف کریں'), style: TextStyle(color: pal.muted)),
        ),
    ];
    final empty = Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(children: [
        Icon(Icons.shopping_bag_outlined, color: pal.muted, size: 40),
        const SizedBox(height: 8),
        Text(Loc.t('Tap products to add', 'پروڈکٹ دبا کر شامل کریں'), style: TextStyle(color: pal.muted)),
      ]),
    );
    if (scroll) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(Loc.t('Current bill', 'موجودہ بل'), style: TextStyle(color: pal.ink, fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Expanded(child: lines.isEmpty ? empty : ListView(children: rows)),
        ...footer,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (lines.isEmpty) empty else ...rows,
      ...footer,
    ]);
  }
}

/// Member / walk-in, discount, raqam, tareeqa => sale save. Wapas (pop): Sale.
class _CheckoutForm extends StatefulWidget {
  final List<CartLine> lines;
  final Map<String, Product> byId;
  const _CheckoutForm({required this.lines, required this.byId});

  @override
  State<_CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends State<_CheckoutForm> {
  MemberSummary? _member;
  final _name = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  String _method = 'Cash';
  bool _busy = false;
  bool _paidTouched = false;

  double get _subtotal => widget.lines.fold<double>(0, (a, l) => a + l.total);
  double get _total => (_subtotal - Fmt.toDouble(_discount.text)).clamp(0, double.infinity).toDouble();

  @override
  void initState() {
    super.initState();
    _paid.text = _total.toStringAsFixed(0);
  }

  @override
  void dispose() {
    for (final c in [_name, _discount, _paid, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    if (!_paidTouched || _member == null) _paid.text = _total.toStringAsFixed(0);
  }

  Future<void> _pickMember() async {
    final m = await pickMember(context);
    if (m != null && mounted) setState(() => _member = m);
  }

  Future<void> _save() async {
    final paid = _member == null ? _total : Fmt.toDouble(_paid.text);
    setState(() => _busy = true);
    final sale = await ShopRepo.checkout(
      lines: widget.lines,
      byId: widget.byId,
      memberId: _member?.member.id,
      customerName: _member == null ? _name.text.trim() : '',
      discount: Fmt.toDouble(_discount.text),
      paid: paid,
      method: _method,
      note: _note.text.trim(),
    );
    if (mounted) Navigator.pop<Sale>(context, sale);
  }

  @override
  Widget build(BuildContext context) {
    final m = _member;
    final credit = m == null ? 0.0 : (_total - Fmt.toDouble(_paid.text));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: pal.goldSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Text(Loc.t('${widget.lines.length} items', '${widget.lines.length} آئٹمز'),
                style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
          ),
          Text(Fmt.money(_total), style: TextStyle(color: pal.ink, fontSize: 22, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 14),
      if (m == null) ...[
        OutlinedButton.icon(
          onPressed: _pickMember,
          icon: Icon(Icons.person_search, color: pal.gold),
          label: Text(Loc.t('Sell to a member (can add to account)', 'ممبر کو بیچیں (ادھار ہو سکتا ہے)')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          decoration: ThemeManager.field(Loc.t('…or walk-in customer name (optional)', '…یا عام گاہک کا نام (اختیاری)'),
              icon: Icons.person_outline),
        ),
      ] else
        PCard(
          color: pal.cardAlt,
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            MemberAvatar(memberId: m.member.id, name: m.member.name, hasPhoto: m.hasPhoto, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.member.name, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
                Text(
                  '${m.member.code} · ${Loc.t('Balance', 'بقایا')} ${m.dues > 0.5 ? Fmt.money(m.dues) : Loc.t('clear', 'صاف')}',
                  style: TextStyle(color: pal.muted, fontSize: 12),
                ),
              ]),
            ),
            IconButton(
              icon: Icon(Icons.close, color: pal.muted),
              onPressed: () => setState(() {
                _member = null;
                _paidTouched = false;
                _sync();
              }),
            ),
          ]),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _discount,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(_sync),
        decoration: ThemeManager.field(Loc.t('Discount', 'رعایت'), icon: Icons.percent),
      ),
      if (m != null) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _paid,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _paidTouched = true),
          decoration: ThemeManager.field(Loc.t('Paid now (rest goes to account)', 'ابھی وصول (باقی ادھار)'),
              icon: Icons.payments_outlined),
        ),
        if (credit > 0.5)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(Loc.t('${Fmt.money(credit)} will be added to ${m.member.name}\'s balance', '${Fmt.money(credit)} ادھار میں جائے گا'),
                style: TextStyle(color: pal.purple, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
      ],
      const SizedBox(height: 10),
      ChoiceChips<String>(
        options: [for (final x in paymentMethods) (x, x)],
        value: _method,
        onChanged: (v) => setState(() => _method = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: _note, decoration: ThemeManager.field(Loc.t('Note (optional)', 'نوٹ (اختیاری)'), icon: Icons.notes)),
      const SizedBox(height: 18),
      GoldButton(label: Loc.t('SAVE BILL', 'بل محفوظ کریں'), icon: Icons.check_circle_outline, busy: _busy, onPressed: _save),
    ]);
  }
}

/// Counter bill ki receipt: print / PDF / WhatsApp (aur manager ke liye cancel).
Future<void> showSaleReceipt(BuildContext context, Sale sale) async {
  final items = await ShopRepo.items(sale.id);
  final balance = sale.memberId == null ? 0.0 : await PaymentRepo.duesOf(sale.memberId!);
  if (!context.mounted) return;
  await showGymSheet<void>(
    context,
    title: sale.isVoid ? Loc.t('Cancelled bill', 'منسوخ بل') : Loc.t('Bill saved ✓', 'بل محفوظ ✓'),
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PCard(
        color: pal.cardAlt,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Text(Fmt.money(sale.total),
                style: TextStyle(
                    color: pal.ink,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    decoration: sale.isVoid ? TextDecoration.lineThrough : null)),
          ),
          Center(
            child: Text('${sale.receiptNo} · ${sale.buyer} · ${Fmt.date(sale.date)}',
                textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
          ),
          const SizedBox(height: 10),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${i.name} × ${Fmt.decimal(i.qty)}', style: TextStyle(color: pal.ink))),
                Text(Fmt.money(i.total), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
              ]),
            ),
          if (sale.discount > 0) Text('${Loc.t('Discount', 'رعایت')}: ${Fmt.money(sale.discount)}', style: TextStyle(color: pal.green)),
          Text('${Loc.t('Paid', 'وصول')}: ${Fmt.money(sale.paid)} (${sale.method})', style: TextStyle(color: pal.muted)),
          if (sale.credit > 0)
            Text('${Loc.t('On account', 'ادھار')}: ${Fmt.money(sale.credit)}',
                style: TextStyle(color: pal.purple, fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(height: 14),
      if (sale.memberPhone.isNotEmpty)
        FilledButton.icon(
          onPressed: () => Messaging.whatsApp(ctx, sale.memberPhone, Messaging.saleText(sale, items, balance: balance)),
          icon: const Icon(Icons.chat),
          label: Text(Loc.t('Send bill on WhatsApp', 'بل واٹس ایپ پر بھیجیں')),
        ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final b = await PdfService.saleReceipt(sale: sale, items: items, balance: balance);
              await PdfService.printPdf(b, 'Bill ${sale.receiptNo}');
            },
            icon: Icon(Icons.print_outlined, color: pal.gold),
            label: Text(Loc.t('Print', 'پرنٹ')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final b = await PdfService.saleReceipt(sale: sale, items: items, balance: balance);
              await PdfService.sharePdf(b, 'bill-${sale.receiptNo}.pdf');
            },
            icon: Icon(Icons.picture_as_pdf_outlined, color: pal.gold),
            label: Text(Loc.t('PDF', 'پی ڈی ایف')),
          ),
        ),
      ]),
      if (!sale.isVoid && Session.canManage) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            final ok = await confirm(
              ctx,
              Loc.t('Cancel this bill?', 'یہ بل منسوخ کریں؟'),
              Loc.t('Stock will come back and any amount on account will be removed.', 'اسٹاک واپس آ جائے گا اور ادھار ختم ہو جائے گا۔'),
              danger: true,
            );
            if (!ok) return;
            await ShopRepo.voidSale(sale);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          icon: Icon(Icons.block, color: pal.red),
          label: Text(Loc.t('Cancel bill', 'بل منسوخ کریں'), style: TextStyle(color: pal.red)),
        ),
      ],
      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Loc.t('Done', 'ٹھیک ہے'))),
    ]),
  );
}
