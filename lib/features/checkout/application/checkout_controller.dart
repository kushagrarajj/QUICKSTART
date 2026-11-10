import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/money.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../../checkout/data/order_api.dart';
import '../../checkout/domain/order.dart';
import '../../orders/data/order_tracking_repository.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation, {this.message});

  final ReconciliationResult reconciliation;
  final String? message;
}

/// The order was not placed, or its outcome could not be confirmed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  static const _attemptKey = 'checkout.pending_attempt.v1';
  static const _uuid = Uuid();

  Future<CheckoutResult>? _inFlight;

  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() {
    final existing = _inFlight;
    if (existing != null) return existing;

    state = const CheckoutState(isPlacingOrder: true);
    late final Future<CheckoutResult> operation;
    operation = _placeOrder().then(
      (result) {
        state = CheckoutState(lastResult: result);
        return result;
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Checkout operation failed: $error\n$stackTrace');
        const result = CheckoutFailure(
          'We could not confirm your order. Check My orders before trying '
          'again.',
          canRetry: true,
        );
        state = const CheckoutState(lastResult: result);
        return result;
      },
    ).whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<CheckoutResult> _placeOrder() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) return const CheckoutFailure('Your cart is empty');

    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) {
      return CheckoutFailure(
        config.storeClosedMessage.isEmpty
            ? 'The store is closed right now. You can keep browsing.'
            : config.storeClosedMessage,
      );
    }

    final _CheckoutAttempt attempt;
    try {
      attempt = await _attemptFor(cart);
    } on Object catch (error, stackTrace) {
      debugPrint(
          'Could not prepare a safe checkout attempt: $error\n$stackTrace');
      return const CheckoutFailure(
        'We could not safely save this checkout yet. Please try again.',
        canRetry: true,
      );
    }
    return _send(attempt, retryOnTimeout: true, retryOnConflict: true);
  }

  Future<_CheckoutAttempt> _attemptFor(Cart cart) async {
    final store = ref.read(keyValueStoreProvider);
    final raw = await store.getString(_attemptKey);
    if (raw != null) {
      try {
        final saved =
            _CheckoutAttempt.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (saved.cart == cart) return saved;
      } on FormatException catch (error, stackTrace) {
        debugPrint(
            'Discarding malformed pending checkout: $error\n$stackTrace');
      } on TypeError catch (error, stackTrace) {
        debugPrint(
            'Discarding malformed pending checkout: $error\n$stackTrace');
      }
    }

    final attempt = _CheckoutAttempt(
      idempotencyKey: _uuid.v4(),
      cart: cart,
      pricing: CartPricing.compute(cart, ref.read(appConfigControllerProvider)),
    );
    await store.setString(_attemptKey, jsonEncode(attempt.toJson()));
    return attempt;
  }

  Future<CheckoutResult> _send(
    _CheckoutAttempt attempt, {
    required bool retryOnTimeout,
    required bool retryOnConflict,
  }) async {
    try {
      final order = await ref.read(orderApiProvider).placeOrder(
            attempt.cart,
            attempt.pricing,
            idempotencyKey: attempt.idempotencyKey,
          );
      final cartController = ref.read(cartControllerProvider.notifier);
      if (ref.read(cartControllerProvider) == attempt.cart) {
        await cartController.clear();
      }
      await ref.read(keyValueStoreProvider).remove(_attemptKey);
      ref.invalidate(ordersProvider);
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      if (retryOnTimeout) {
        return await _send(
          attempt,
          retryOnTimeout: false,
          retryOnConflict: retryOnConflict,
        );
      }
      return const CheckoutFailure(
        'We could not confirm the response. Your order may have been placed. '
        'Check My orders before trying again.',
        canRetry: true,
      );
    } on ClientException catch (error) {
      if (error.code == 'STORE_CLOSED') {
        return const CheckoutFailure(
          'The store is closed. If you already tried this checkout, check '
          'My orders to confirm it was not placed.',
        );
      }
      if (_isReconciliationConflict(error.code)) {
        return _handleConflict(
          attempt,
          error,
          retryOnConflict: retryOnConflict,
        );
      }
      if (error.code == 'TOTAL_MISMATCH') {
        return _handleTotalMismatch(attempt, error);
      }
      return CheckoutFailure(error.message);
    } on ApiException catch (error) {
      return CheckoutFailure(
        error is NetworkException
            ? 'You are offline. Your order was not confirmed; reconnect and '
                'try again.'
            : error is ServerException
                ? 'We could not confirm the response. Your order may have been '
                    'placed. Check My orders before trying again.'
                : error.message,
        canRetry: error.isTransient,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Checkout failed unexpectedly: $error\n$stackTrace');
      return const CheckoutFailure(
        'We could not confirm your order. Check My orders before trying again.',
        canRetry: true,
      );
    }
  }

  bool _isReconciliationConflict(String? code) => const {
        'PRODUCT_UNAVAILABLE',
        'PRICE_CHANGED',
        'QUANTITY_LIMIT',
        'INSUFFICIENT_STOCK',
        'COUPON_INVALID',
      }.contains(code);

  Future<CheckoutResult> _handleConflict(
    _CheckoutAttempt attempt,
    ClientException error, {
    required bool retryOnConflict,
  }) async {
    try {
      var reconciliation =
          await ref.read(cartReconcilerProvider).reconcile(attempt.cart);
      if (error.code == 'COUPON_INVALID' &&
          error.details is Map &&
          (error.details as Map)['reason'] == 'MIN_ORDER_NOT_MET' &&
          reconciliation.cart.coupon != null) {
        final coupon = reconciliation.cart.coupon!;
        reconciliation = ReconciliationResult(
          cart: reconciliation.cart.withoutCoupon(),
          changes: [
            ...reconciliation.changes,
            CouponRemoved(code: coupon.code, reason: 'MIN_ORDER_NOT_MET'),
          ],
        );
      }

      final cartController = ref.read(cartControllerProvider.notifier);
      if (ref.read(cartControllerProvider) == attempt.cart) {
        await cartController.replace(reconciliation.cart);
      }
      if (reconciliation.requiresUserReview) {
        return CheckoutNeedsReview(reconciliation);
      }
      if (reconciliation.hasChanges && retryOnConflict) {
        final refreshedAttempt = await _attemptFor(reconciliation.cart);
        return await _send(
          refreshedAttempt,
          retryOnTimeout: true,
          retryOnConflict: false,
        );
      }
      return CheckoutFailure(error.message, canRetry: true);
    } on ApiException catch (reconcileError) {
      return CheckoutFailure(
        'We could not refresh your cart (${reconcileError.message}). '
        'Your order was not placed; reconnect and try again.',
        canRetry: reconcileError.isTransient,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Could not apply checkout reconciliation: '
          '$error\n$stackTrace');
      return const CheckoutFailure(
        'We could not update your cart safely. Your order was not placed; '
        'please try again.',
        canRetry: true,
      );
    }
  }

  Future<CheckoutResult> _handleTotalMismatch(
    _CheckoutAttempt attempt,
    ClientException error,
  ) async {
    final reconciliation = ReconciliationResult(
      cart: attempt.cart,
      changes: const [],
    );
    final details = error.details;
    try {
      await ref.read(keyValueStoreProvider).remove(_attemptKey);
    } on Object catch (storageError, stackTrace) {
      debugPrint('Could not clear stale checkout attempt: '
          '$storageError\n$stackTrace');
      return const CheckoutFailure(
        'We could not refresh the order total safely. Please try again.',
        canRetry: true,
      );
    }
    String message;
    if (details is Map && details['serverTotalPaise'] is int) {
      final serverTotal = details['serverTotalPaise'] as int;
      await ref.read(appConfigControllerProvider.notifier).refresh();
      message = 'Delivery pricing changed. The updated total is '
          '${formatMoney(serverTotal)}; review it '
          'before placing your order.';
    } else {
      message = 'The order total changed. Review the updated total before '
          'placing your order.';
    }
    return CheckoutNeedsReview(reconciliation, message: message);
  }
}

class _CheckoutAttempt {
  const _CheckoutAttempt({
    required this.idempotencyKey,
    required this.cart,
    required this.pricing,
  });

  final String idempotencyKey;
  final Cart cart;
  final CartPricing pricing;

  Map<String, Object?> toJson() => {
        'idempotencyKey': idempotencyKey,
        'cart': cart.toJson(),
        'pricing': {
          'subtotalPaise': pricing.subtotalPaise,
          'discountPaise': pricing.discountPaise,
          'deliveryFeePaise': pricing.deliveryFeePaise,
          'totalPaise': pricing.totalPaise,
          'amountForFreeDeliveryPaise': pricing.amountForFreeDeliveryPaise,
        },
      };

  factory _CheckoutAttempt.fromJson(Map<String, dynamic> json) {
    final pricing = json['pricing'] as Map<String, dynamic>;
    return _CheckoutAttempt(
      idempotencyKey: json['idempotencyKey'] as String,
      cart: Cart.fromJson(json['cart'] as Map<String, dynamic>),
      pricing: CartPricing(
        subtotalPaise: pricing['subtotalPaise'] as int,
        discountPaise: pricing['discountPaise'] as int,
        deliveryFeePaise: pricing['deliveryFeePaise'] as int,
        totalPaise: pricing['totalPaise'] as int,
        amountForFreeDeliveryPaise:
            pricing['amountForFreeDeliveryPaise'] as int,
      ),
    );
  }
}
