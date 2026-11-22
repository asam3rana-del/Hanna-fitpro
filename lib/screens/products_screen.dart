import 'package:flutter/material.dart';

import '../db/shop_repo.dart';
import '../models/shop_models.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';

enum _StockFilter { all, low, out, expiring }

/// Counter ke products, stock, purchase (maal aaya), expiry aur kam-stock alerts.
class ProductsScreen extends StatefulWidget {
  /// Dashboard se seedha alerts dikhane ke liye.
  final bool alertsFirst;
  const ProductsScreen({super.key, this.alertsFirst = false});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> with AutoRefresh {
  List<Product>? _all;
  Map<String, String> _nextExpiry = {};
  late _StockFilter _filter = widget.alertsFirst ? _StockFilter.low : _StockFilter.all;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final p = await ShopRepo.products();
    final lots = await ShopRepo.expiring(days: 60);
    final next = <String, String>{};
    for (final l in lots) {
      final cur = next[l.product.id];
      if (cur == null || l.expiry.compareTo(cur) < 0) next[l.product.id] = l.expiry;
    }
    if (!mounted) return;
    setState(() {
      _all = p;
      _nextExpiry = next;
    });
  }

  bool _match(Product p, [_StockFilter? f]) {
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty && !(p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q) || p.barcode == q)) {
      return false;
    }
    return switch (f ?? _filter) {
      _StockFilter.all => true,
      _StockFilter.low => p.tracksStock && p.isLow,
      _StockFilter.out => p.tracksStock && p.isOut,
      _StockFilter.expiring => _nextExpiry.containsKey(p.id),
    };
  }

  int _count(_StockFilter f) => (_all ?? []).where((p) => _match(p, f)).length;

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final list = (all ?? []).where((p) => _match(p)).toList();
    final stockValue = (all ?? []).where((p) => p.tracksStock && p.stock > 0).fold<double>(0, (a, p) => a + p.stock * p.cost);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(
        Loc.t('Products & Stock', 'پروڈکٹس اور اسٹاک'),
        subtitle: Session.canManage && all != null ? Loc.t('Stock value ${Fmt.money(stockValue)}', 'اسٹاک کی مالیت ${Fmt.money(stockValue)}') : null,
      ),
      floatingActionButton: Session.canManage
          ? FloatingActionButton.extended(
              backgroundColor: pal.gold,
              foregroundColor: pal.onGold,
              onPressed: () => showProductForm(context, all: all ?? const []),
              icon: const Icon(Icons.add),
              label: Text(Loc.t('New product', 'نئی پروڈکٹ'), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: ThemeManager.field(Loc.t('Search product / barcode', 'پروڈکٹ / بارکوڈ تلاش'), icon: Icons.search),
          ),
        ),
        if (all != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ChoiceChips<_StockFilter>(
              options: [
                (_StockFilter.all, '${Loc.t('All', 'سب')} ${_count(_StockFilter.all)}'),
                (_StockFilter.low, '${Loc.t('Low stock', 'کم اسٹاک')} ${_count(_StockFilter.low)}'),
                (_StockFilter.out, '${Loc.t('Out', 'ختم')} ${_count(_StockFilter.out)}'),
                (_StockFilter.expiring, '${Loc.t('Expiring (60d)', 'ایکسپائری (60 دن)')} ${_count(_StockFilter.expiring)}'),
              ],
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        Expanded(
          child: all == null
              ? Center(child: CircularProgressIndicator(color: pal.gold))
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: all.isEmpty ? Loc.t('No products yet', 'ابھی کوئی پروڈکٹ نہیں') : Loc.t('Nothing here', 'یہاں کچھ نہیں'),
                      subtitle: all.isEmpty
                          ? Loc.t('Add whey protein, water, shaker, locker rent…', 'وے پروٹین، پانی، شیکر، لاکر کرایہ… شامل کریں')
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final p = list[i];
                        final exp = _nextExpiry[p.id];
                        return PCard(
                          padding: const EdgeInsets.all(12),
                          onTap: () => push(context, ProductDetailScreen(productId: p.id)),
                          child: Row(children: [
                            Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: pal.goldSoft, borderRadius: BorderRadius.circular(14)),
                              child: Icon(
                                p.isService ? Icons.room_service_outlined : (p.isCombo ? Icons.redeem_outlined : Icons.inventory_2_outlined),
                                color: pal.gold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: TextStyle(color: p.active ? pal.ink : pal.muted, fontWeight: FontWeight.w800)),
                                Text(
                                  [p.category, Fmt.money(p.price), if (p.hasServing) '${p.servingName} ${Fmt.money(p.servingPrice)}']
                                      .join('  ·  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: pal.muted, fontSize: 12.5),
                                ),
                                const SizedBox(height: 6),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  if (p.isService)
                                    Pill(Loc.t('Service', 'سروس'), color: pal.blue, soft: pal.blueSoft)
                                  else
                                    Pill(
                                      p.isOut
                                          ? Loc.t('Out of stock', 'اسٹاک ختم')
                                          : Loc.t('Stock ${Fmt.decimal(p.stock)}', 'اسٹاک ${Fmt.decimal(p.stock)}'),
                                      color: p.isOut ? pal.red : (p.isLow ? pal.amber : pal.green),
                                      soft: p.isOut ? pal.redSoft : (p.isLow ? pal.amberSoft : pal.greenSoft),
                                    ),
                                  if (exp != null)
                                    Pill(
                                      Fmt.daysLeft(exp) < 0
                                          ? Loc.t('Expired ${Fmt.date(exp)}', '${Fmt.date(exp)} کو ایکسپائر')
                                          : Loc.t('Expires ${Fmt.date(exp)}', 'ایکسپائری ${Fmt.date(exp)}'),
                                      color: pal.red,
                                      soft: pal.redSoft,
                                      icon: Icons.event_busy,
                                    ),
                                  if (!p.active) Pill(Loc.t('Hidden', 'چھپی'), color: pal.muted, soft: pal.cardAlt),
                                ]),
                              ]),
                            ),
                            Icon(Icons.chevron_right, color: pal.muted),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

/// Ek product: stock, maal aaya / theek karo, tareekh-war harkat.
class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> with AutoRefresh {
  Product? _p;
  List<Product> _all = [];
  List<StockMove> _moves = [];
  List<(String, double)> _lots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDataChanged() => _load();

  Future<void> _load() async {
    final all = await ShopRepo.products();
    Product? p;
    for (final x in all) {
      if (x.id == widget.productId) p = x;
    }
    final moves = await ShopRepo.movesFor(widget.productId);
    final purchases = moves.where((m) => m.kind == 'purchase').toList();
    if (!mounted) return;
    setState(() {
      _all = all;
      _p = p;
      _moves = moves;
      _lots = p == null ? [] : remainingLots(p.stock, purchases);
    });
  }

  String _nameOf(String id) {
    for (final x in _all) {
      if (x.id == id) return x.name;
    }
    return '?';
  }

  String _kindLabel(String k) => switch (k) {
        'purchase' => Loc.t('Stock in', 'مال آیا'),
        'sale' => Loc.t('Sold', 'بکا'),
        'void' => Loc.t('Bill cancelled', 'بل منسوخ'),
        _ => Loc.t('Adjusted', 'درستی'),
      };

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(backgroundColor: pal.bg, appBar: gymAppBar(Loc.t('Product', 'پروڈکٹ')), body: const SizedBox.shrink());
    }
    final margin = p.price > 0 && p.cost > 0 ? (p.price - p.cost) / p.price * 100 : null;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: gymAppBar(p.name, subtitle: p.category, actions: [
        if (Session.canManage)
          IconButton(
            icon: Icon(Icons.edit_outlined, color: pal.gold),
            onPressed: () => showProductForm(context, product: p, all: _all),
          ),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            HeroHeader(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p.isService ? Loc.t('Service (no stock)', 'سروس (اسٹاک نہیں)') : Loc.t('In stock', 'اسٹاک میں'),
                  style: TextStyle(color: pal.gold, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                if (!p.isService)
                  Text(
                    '${Fmt.decimal(p.stock)}${p.hasServing ? '  (≈ ${Fmt.number(p.stock * p.servingsPerUnit)} ${p.servingName})' : ''}',
                    style: TextStyle(color: p.isOut ? pal.red : pal.onHeader, fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                const SizedBox(height: 10),
                Wrap(spacing: 18, runSpacing: 8, children: [
                  _kv(Loc.t('Price', 'قیمت'), Fmt.money(p.price)),
                  if (Session.canManage && !p.isService) _kv(Loc.t('Cost', 'خرید'), Fmt.money(p.cost)),
                  if (Session.canManage && margin != null) _kv(Loc.t('Margin', 'مارجن'), '${margin.toStringAsFixed(0)}%'),
                  if (p.hasServing) _kv(p.servingName, '${Fmt.money(p.servingPrice)} · ${Fmt.decimal(p.servingsPerUnit)}/pc'),
                  if (p.barcode.isNotEmpty) _kv(Loc.t('Barcode', 'بارکوڈ'), p.barcode),
                  if (p.tracksStock) _kv(Loc.t('Alert below', 'الرٹ'), Fmt.decimal(p.lowStock)),
                ]),
                if (p.isCombo) ...[
                  const SizedBox(height: 10),
                  for (final part in p.parts)
                    Text(
                      '• ${_nameOf(part.productId)} × ${Fmt.decimal(part.qty)}',
                      style: TextStyle(color: pal.onHeader.withValues(alpha: 0.8)),
                    ),
                ],
              ]),
            ),
            if (Session.canManage && p.tracksStock) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => showStockInSheet(context, p),
                    icon: const Icon(Icons.add_box_outlined),
                    label: Text(Loc.t('Stock in', 'مال آیا')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showAdjustSheet(context, p),
                    icon: Icon(Icons.tune, color: pal.gold),
                    label: Text(Loc.t('Adjust', 'درستی')),
                  ),
                ),
              ]),
            ],
            if (_lots.isNotEmpty) ...[
              SectionTitle(Loc.t('Expiry of current stock', 'موجودہ اسٹاک کی ایکسپائری')),
              PCard(
                child: Column(children: [
                  for (final (exp, qty) in _lots)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(Icons.event, color: Fmt.daysLeft(exp) <= 60 ? pal.red : pal.muted, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(Fmt.date(exp), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700))),
                        Text('${Fmt.decimal(qty)} pc', style: TextStyle(color: pal.muted)),
                        const SizedBox(width: 10),
                        Text(
                          Fmt.daysLeft(exp) < 0
                              ? Loc.t('expired', 'ختم')
                              : Loc.t('${Fmt.daysLeft(exp)} days', '${Fmt.daysLeft(exp)} دن'),
                          style: TextStyle(color: Fmt.daysLeft(exp) <= 60 ? pal.red : pal.green, fontWeight: FontWeight.w700),
                        ),
                      ]),
                    ),
                ]),
              ),
            ],
            if (!p.isService) ...[
              SectionTitle(Loc.t('Stock history', 'اسٹاک کی تاریخ')),
              if (_moves.isEmpty)
                PCard(child: Text(Loc.t('No movement yet', 'ابھی کوئی حرکت نہیں'), style: TextStyle(color: pal.muted)))
              else
                PCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    for (final m in _moves)
                      ListTile(
                        dense: true,
                        leading: Icon(m.qty >= 0 ? Icons.south_west : Icons.north_east, color: m.qty >= 0 ? pal.green : pal.red),
                        title: Text('${_kindLabel(m.kind)}  ${m.qty >= 0 ? '+' : ''}${Fmt.decimal(m.qty)}',
                            style: TextStyle(color: pal.ink, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            Fmt.date(m.date),
                            if (m.kind == 'purchase' && m.cost > 0 && Session.canManage) '@ ${Fmt.money(m.cost)}',
                            if (m.supplier.isNotEmpty) m.supplier,
                            if (m.expiry != null) '${Loc.t('exp', 'ایکسپ')} ${Fmt.date(m.expiry)}',
                            if (m.note.isNotEmpty) m.note,
                          ].join(' · '),
                          style: TextStyle(color: pal.muted, fontSize: 12),
                        ),
                      ),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: pal.onHeader.withValues(alpha: 0.55), fontSize: 11.5)),
        Text(v, style: TextStyle(color: pal.onHeader, fontWeight: FontWeight.w800)),
      ]);
}

/// Naya / edit product.
Future<void> showProductForm(BuildContext context, {Product? product, required List<Product> all}) async {
  final p = product;
  final name = TextEditingController(text: p?.name ?? '');
  final barcode = TextEditingController(text: p?.barcode ?? '');
  final price = TextEditingController(text: p == null ? '' : p.price.toStringAsFixed(0));
  final cost = TextEditingController(text: (p == null || p.cost == 0) ? '' : p.cost.toStringAsFixed(0));
  final low = TextEditingController(text: (p == null || p.lowStock == 0) ? '' : Fmt.decimal(p.lowStock));
  final servingName = TextEditingController(text: (p?.servingName.isNotEmpty ?? false) ? p!.servingName : '');
  final servings = TextEditingController(text: (p == null || p.servingsPerUnit == 0) ? '' : Fmt.decimal(p.servingsPerUnit));
  final servingPrice = TextEditingController(text: (p == null || p.servingPrice == 0) ? '' : p.servingPrice.toStringAsFixed(0));
  final notes = TextEditingController(text: p?.notes ?? '');
  var category = p?.category ?? ShopRepo.categories.first;
  var kind = p?.kind ?? 'item';
  var active = p?.active ?? true;
  final parts = <String, double>{for (final x in p?.parts ?? const <ComboPart>[]) x.productId: x.qty};
  final items = all.where((x) => x.kind == 'item' && x.id != p?.id).toList();
  final cats = [...ShopRepo.categories];
  if (!cats.contains(category)) cats.add(category);

  await showGymSheet<void>(
    context,
    title: p == null ? Loc.t('New product', 'نئی پروڈکٹ') : Loc.t('Edit product', 'پروڈکٹ میں ترمیم'),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ChoiceChips<String>(
          options: [
            ('item', Loc.t('Product (stock)', 'پروڈکٹ (اسٹاک)')),
            ('service', Loc.t('Service', 'سروس')),
            ('combo', Loc.t('Combo / deal', 'کومبو / ڈیل')),
          ],
          value: kind,
          onChanged: (v) => setSheet(() {
            kind = v;
            if (v == 'service' && category == ShopRepo.categories.first) category = 'Services';
            if (v == 'combo' && category == ShopRepo.categories.first) category = 'Combos';
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: ThemeManager.field(Loc.t('Name (e.g. Whey Protein 2lb)', 'نام (مثلاً وے پروٹین 2 پاؤنڈ)'), icon: Icons.label_outline),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cats)
            GestureDetector(
              onTap: () => setSheet(() => category = c),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c == category ? pal.gold : pal.cardAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c == category ? pal.gold : pal.border),
                ),
                child: Text(c, style: TextStyle(color: c == category ? pal.onGold : pal.ink, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: ThemeManager.field(Loc.t('Sale price', 'فروخت قیمت'), icon: Icons.sell_outlined),
            ),
          ),
          if (kind == 'item') ...[
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration: ThemeManager.field(Loc.t('Cost price', 'خرید قیمت'), icon: Icons.shopping_cart_outlined),
              ),
            ),
          ],
        ]),
        if (kind == 'item') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: barcode,
                decoration: ThemeManager.field(Loc.t('Barcode (scan)', 'بارکوڈ (اسکین)'), icon: Icons.qr_code),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: low,
                keyboardType: TextInputType.number,
                decoration: ThemeManager.field(Loc.t('Alert when stock ≤', 'اسٹاک کم ہو تو الرٹ ≤'), icon: Icons.warning_amber),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          PCard(
            color: pal.cardAlt,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(Loc.t('Sell by scoop / serving (optional)', 'اسکوپ / سرونگ کے حساب سے (اختیاری)'),
                  style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
              Text(Loc.t('e.g. protein tub = 60 scoops, 1 scoop shake = Rs 250', 'مثلاً پروٹین کا ڈبہ = 60 اسکوپ، ایک اسکوپ شیک = 250 روپے'),
                  style: TextStyle(color: pal.muted, fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: servingName, decoration: ThemeManager.field(Loc.t('Name', 'نام'), hint: 'scoop'))),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: servings,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: ThemeManager.field(Loc.t('Per pc', 'فی پیس'), hint: '60'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: servingPrice,
                    keyboardType: TextInputType.number,
                    decoration: ThemeManager.field(Loc.t('Price', 'قیمت'), hint: '250'),
                  ),
                ),
              ]),
            ]),
          ),
        ],
        if (kind == 'combo') ...[
          const SizedBox(height: 12),
          Text(Loc.t('Items in this combo', 'اس کومبو میں کیا ہے'), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Text(Loc.t('Add stock products first', 'پہلے اسٹاک والی پروڈکٹس شامل کریں'), style: TextStyle(color: pal.muted)),
          for (final it in items)
            Row(children: [
              Expanded(child: Text(it.name, style: TextStyle(color: pal.ink))),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.remove_circle_outline, color: pal.muted),
                onPressed: () => setSheet(() {
                  final q = (parts[it.id] ?? 0) - 1;
                  if (q <= 0) {
                    parts.remove(it.id);
                  } else {
                    parts[it.id] = q;
                  }
                }),
              ),
              Text(Fmt.decimal(parts[it.id] ?? 0), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w900)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add_circle_outline, color: pal.gold),
                onPressed: () => setSheet(() => parts[it.id] = (parts[it.id] ?? 0) + 1),
              ),
            ]),
        ],
        const SizedBox(height: 10),
        TextField(controller: notes, decoration: ThemeManager.field(Loc.t('Notes', 'نوٹس'), icon: Icons.notes)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: active,
          onChanged: (v) => setSheet(() => active = v),
          title: Text(Loc.t('Show on counter', 'کاؤنٹر پر دکھائیں'), style: TextStyle(color: pal.ink)),
        ),
        const SizedBox(height: 8),
        GoldButton(
          label: Loc.t('SAVE', 'محفوظ کریں'),
          onPressed: () async {
            if (name.text.trim().isEmpty) {
              toast(ctx, Loc.t('Enter product name', 'پروڈکٹ کا نام لکھیں'));
              return;
            }
            if (kind == 'combo' && parts.isEmpty) {
              toast(ctx, Loc.t('Add items to the combo', 'کومبو میں آئٹمز شامل کریں'));
              return;
            }
            final x = Product(
              id: p?.id ?? '',
              name: name.text.trim(),
              category: category,
              kind: kind,
              barcode: kind == 'item' ? barcode.text.trim() : '',
              price: Fmt.toDouble(price.text),
              cost: kind == 'item' ? Fmt.toDouble(cost.text) : 0,
              lowStock: kind == 'item' ? Fmt.toDouble(low.text) : 0,
              servingName: kind == 'item' ? servingName.text.trim() : '',
              servingsPerUnit: kind == 'item' ? Fmt.toDouble(servings.text) : 0,
              servingPrice: kind == 'item' ? Fmt.toDouble(servingPrice.text) : 0,
              parts: kind == 'combo' ? [for (final e in parts.entries) ComboPart(e.key, e.value)] : const [],
              active: active,
              notes: notes.text.trim(),
            );
            if (p == null) {
              await ShopRepo.create(x);
            } else {
              await ShopRepo.save(x);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
        if (p != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final ok = await confirm(ctx, Loc.t('Delete product?', 'پروڈکٹ مٹائیں؟'),
                  Loc.t('Old bills keep their item names.', 'پرانے بلوں میں نام رہیں گے۔'),
                  danger: true);
              if (!ok) return;
              await ShopRepo.delete(p.id);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (Navigator.of(context).canPop()) Navigator.of(context).pop();
              }
            },
            icon: Icon(Icons.delete_outline, color: pal.red),
            label: Text(Loc.t('Delete product', 'پروڈکٹ مٹائیں'), style: TextStyle(color: pal.red)),
          ),
        ],
      ]),
    ),
  );
}

/// Maal aaya: qty, khareed qeemat, expiry, supplier.
Future<void> showStockInSheet(BuildContext context, Product p) async {
  final qty = TextEditingController();
  final cost = TextEditingController(text: p.cost > 0 ? p.cost.toStringAsFixed(0) : '');
  final supplier = TextEditingController();
  final note = TextEditingController();
  DateTime? expiry;
  var date = Fmt.today();
  await showGymSheet<void>(
    context,
    title: Loc.t('Stock in — ${p.name}', 'مال آیا — ${p.name}'),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: ThemeManager.field(Loc.t('Quantity (pcs)', 'تعداد (پیس)'), icon: Icons.add_box_outlined),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: cost,
              keyboardType: TextInputType.number,
              decoration: ThemeManager.field(Loc.t('Cost per pc', 'فی پیس خرید'), icon: Icons.shopping_cart_outlined),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        DateField(label: Loc.t('Date', 'تاریخ'), value: date, onChanged: (d) => setSheet(() => date = d)),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final d = await showDatePicker(
              context: ctx,
              initialDate: expiry ?? Fmt.addMonths(Fmt.today(), 12),
              firstDate: DateTime(2015),
              lastDate: DateTime(2100),
            );
            if (d != null) setSheet(() => expiry = DateTime.utc(d.year, d.month, d.day));
          },
          child: InputDecorator(
            decoration: ThemeManager.field(Loc.t('Expiry date (supplements)', 'ایکسپائری (سپلیمنٹس)'), icon: Icons.event_busy),
            child: Text(expiry == null ? Loc.t('Not set', 'نہیں') : Fmt.dateOf(expiry!), style: TextStyle(color: pal.ink)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: supplier, decoration: ThemeManager.field(Loc.t('Supplier (optional)', 'سپلائر (اختیاری)'), icon: Icons.local_shipping_outlined)),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: ThemeManager.field(Loc.t('Note', 'نوٹ'), icon: Icons.notes)),
        const SizedBox(height: 18),
        GoldButton(
          label: Loc.t('ADD TO STOCK', 'اسٹاک میں شامل کریں'),
          onPressed: () async {
            final q = Fmt.toDouble(qty.text);
            if (q <= 0) return;
            final e = expiry;
            await ShopRepo.stockIn(
              productId: p.id,
              qty: q,
              cost: Fmt.toDouble(cost.text),
              expiry: e == null ? null : Fmt.ymd(e),
              supplier: supplier.text.trim(),
              note: note.text.trim(),
              date: date,
            );
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ]),
    ),
  );
}

/// Stock theek karo (toota, expire, ginti ka farq).
Future<void> showAdjustSheet(BuildContext context, Product p) async {
  final qty = TextEditingController();
  final note = TextEditingController();
  var add = false;
  await showGymSheet<void>(
    context,
    title: Loc.t('Adjust stock — ${p.name}', 'اسٹاک درستی — ${p.name}'),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(Loc.t('Now: ${Fmt.decimal(p.stock)} pcs', 'ابھی: ${Fmt.decimal(p.stock)} پیس'), style: TextStyle(color: pal.muted)),
        const SizedBox(height: 10),
        ChoiceChips<bool>(
          options: [(false, Loc.t('Remove (damaged / expired / used)', 'کم کریں (خراب / ایکسپائر / استعمال)')), (true, Loc.t('Add (count fix)', 'زیادہ کریں (گنتی درست)'))],
          value: add,
          onChanged: (v) => setSheet(() => add = v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: qty,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: ThemeManager.field(Loc.t('Quantity (pcs)', 'تعداد (پیس)'), icon: Icons.tune),
        ),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: ThemeManager.field(Loc.t('Reason', 'وجہ'), icon: Icons.notes)),
        const SizedBox(height: 18),
        GoldButton(
          label: Loc.t('SAVE', 'محفوظ کریں'),
          onPressed: () async {
            final q = Fmt.toDouble(qty.text);
            if (q <= 0) return;
            await ShopRepo.adjust(productId: p.id, qty: add ? q : -q, note: note.text.trim());
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ]),
    ),
  );
}
