import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  /// Returns the complete cart state allowed by the latest server data.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    final batch = cart.lines.isEmpty
        ? const ProductBatch(products: [], missingIds: [])
        : await catalogApi.getProductsByIds(
            cart.lines.map((line) => line.productId).toList(),
          );
    final products = {
      for (final product in batch.products) product.id: product
    };
    final missing = batch.missingIds.toSet();
    final lines = <CartLine>[];
    final changes = <CartChange>[];

    for (final line in cart.lines) {
      if (missing.contains(line.productId)) {
        changes.add(ProductUnavailable(
          productId: line.productId,
          productName: line.name,
        ));
        continue;
      }

      final product = products[line.productId];
      if (product == null) {
        throw const FormatException(
          'Product batch response omitted a requested product',
        );
      }
      if (!product.inStock) {
        changes.add(OutOfStock(
          productId: line.productId,
          productName: product.name,
        ));
        continue;
      }

      final available = product.purchasableQuantity;
      final quantity = line.quantity > available ? available : line.quantity;
      if (quantity != line.quantity) {
        changes.add(QuantityReduced(
          productId: line.productId,
          requestedQuantity: line.quantity,
          availableQuantity: quantity,
          productName: product.name,
        ));
      }
      if (line.unitPricePaise != product.pricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: product.pricePaise,
          productName: product.name,
        ));
      }
      lines.add(line.copyWith(
        name: product.name,
        unitPricePaise: product.pricePaise,
        quantity: quantity,
        maxPerOrder: available,
      ));
    }

    Coupon? coupon = cart.coupon;
    final currentCoupon = coupon;
    if (currentCoupon != null) {
      try {
        coupon = await couponApi.validate(currentCoupon.code);
      } on ClientException catch (error) {
        if (error.code != 'COUPON_NOT_FOUND' &&
            error.code != 'COUPON_EXPIRED') {
          rethrow;
        }
        coupon = null;
        changes.add(CouponRemoved(
          code: currentCoupon.code,
          reason: error.code == 'COUPON_EXPIRED' ? 'EXPIRED' : 'NOT_FOUND',
        ));
      }
    }

    return ReconciliationResult(
      cart: Cart(lines: lines, coupon: coupon),
      changes: changes,
    );
  }
}
