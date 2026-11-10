import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/product_dto.dart';

void main() {
  test('parses legacy nullable MRP and string stock', () {
    final product = ProductDto.fromJson({
      'id': 'dairy-00',
      'name': 'Toned Milk',
      'categoryId': 'dairy',
      'price': 29,
      'mrp': null,
      'stock': '120',
      'maxPerOrder': 6,
    });

    expect(product.pricePaise, 2900);
    expect(product.mrpPaise, 2900);
    expect(product.stock, 120);
  });
}
