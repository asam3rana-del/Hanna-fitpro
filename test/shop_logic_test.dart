import 'package:flutter_test/flutter_test.dart';

import 'package:hanna_fitness/db/shop_repo.dart';
import 'package:hanna_fitness/models/shop_models.dart';

void main() {
  const whey = Product(
    id: 'w',
    name: 'Whey 2lb',
    price: 9000,
    cost: 7000,
    servingName: 'scoop',
    servingsPerUnit: 30,
    servingPrice: 400,
    stock: 3,
  );
  const shaker = Product(id: 's', name: 'Shaker', price: 800, cost: 450, stock: 10, lowStock: 2);

  test('serving sale takes a fraction of a tub from stock', () {
    final l = CartLine(product: whey, serving: true, qty: 3, price: 400);
    expect(l.stockUnits, closeTo(0.1, 1e-9));
    expect(l.total, 1200);
    expect(l.costWith({'w': whey}), closeTo(700, 1e-6));
    expect(whey.hasServing, isTrue);
  });

  test('combo stock = how many full combos can be made', () {
    const combo = Product(id: 'c', name: 'Whey + Shaker', kind: 'combo', price: 9500, parts: [ComboPart('w', 1), ComboPart('s', 2)]);
    expect(ShopRepo.comboStock(combo, {'w': whey, 's': shaker}), 3);
    final line = CartLine(product: combo, serving: false, qty: 2, price: 9500);
    expect(line.stockUnits, 0); // combo ke hisse alag se stock se nikalte hain
    expect(line.costWith({'w': whey, 's': shaker}), (7000 + 900) * 2);
  });

  test('combo parts round-trip through JSON', () {
    final raw = Product.encodeParts(const [ComboPart('w', 1), ComboPart('s', 2)]);
    final back = Product.parseParts(raw);
    expect(back.length, 2);
    expect(back[1].productId, 's');
    expect(back[1].qty, 2);
    expect(Product.parseParts('garbage'), isEmpty);
  });

  test('low / out of stock flags', () {
    expect(shaker.isLow, isFalse);
    expect(shaker.withStock(2).isLow, isTrue);
    expect(shaker.withStock(0).isOut, isTrue);
    const service = Product(id: 'l', name: 'Locker', kind: 'service', price: 500);
    expect(service.isLow, isFalse);
    expect(service.tracksStock, isFalse);
  });

  test('FIFO: remaining stock sits in the newest purchases', () {
    const moves = [
      StockMove(id: '1', productId: 'w', qty: 5, kind: 'purchase', date: '2026-01-01', expiry: '2026-12-01'),
      StockMove(id: '2', productId: 'w', qty: 4, kind: 'purchase', date: '2026-06-01', expiry: '2027-06-01'),
    ];
    final lots = remainingLots(6, moves);
    expect(lots.length, 2);
    expect(lots[0].$1, '2027-06-01');
    expect(lots[0].$2, 4);
    expect(lots[1].$1, '2026-12-01');
    expect(lots[1].$2, 2);
    expect(remainingLots(3, moves).length, 1);
    expect(remainingLots(0, moves), isEmpty);
  });
}
