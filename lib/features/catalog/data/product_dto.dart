import '../../../core/utils/money.dart';
import '../domain/product.dart';

/// Maps the API representation of a product (see API_CONTRACT.md) to the
/// domain [Product].
class ProductDto {
  const ProductDto._();

  static Product fromJson(Map<String, dynamic> json) {
    final price = json['price'];
    if (price is! num) {
      throw const FormatException('Product price must be numeric');
    }
    final rawMrp = json['mrp'];
    final mrp = rawMrp is num ? rawMrp : price;
    final rawStock = json['stock'];
    final stock = rawStock is int
        ? rawStock
        : rawStock is String
            ? int.tryParse(rawStock)
            : null;
    if (stock == null) {
      throw const FormatException('Product stock must be an integer');
    }
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      emoji: json['emoji'] as String? ?? '🛒',
      unit: json['unit'] as String? ?? '',
      pricePaise: rupeesToPaise(price),
      mrpPaise: rupeesToPaise(mrp),
      stock: stock,
      maxPerOrder: json['maxPerOrder'] as int? ?? 10,
    );
  }

  static List<Product> listFromJson(Object? json) =>
      (json as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
}
