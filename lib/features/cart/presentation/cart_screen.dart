import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/utils/money.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../catalog/presentation/widgets/product_card.dart';
import '../../checkout/application/checkout_controller.dart';
import '../../checkout/presentation/order_success_screen.dart';
import '../application/cart_controller.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/cart_pricing.dart';
import '../domain/reconciliation.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final config = ref.watch(appConfigControllerProvider);
    final pricing = CartPricing.compute(cart, config);

    return Scaffold(
      appBar: AppBar(title: const Text('My cart')),
      body: Column(
        children: [
          if (!config.storeOpen)
            _StoreClosedBanner(message: config.storeClosedMessage),
          Expanded(
            child: cart.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🛒', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 8),
                        Text('Your cart is empty'),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (pricing.amountForFreeDeliveryPaise > 0)
                        Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Add ${formatMoney(pricing.amountForFreeDeliveryPaise)} '
                              'more for FREE delivery 🛵',
                            ),
                          ),
                        ),
                      Card(
                        child: Column(
                          children: [
                            for (final line in cart.lines)
                              _CartLineTile(line: line),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _CouponSection(),
                      const SizedBox(height: 8),
                      _BillDetails(pricing: pricing),
                      const SizedBox(height: 80),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _PlaceOrderBar(
              totalPaise: pricing.totalPaise,
              storeOpen: config.storeOpen,
            ),
    );
  }
}

class _StoreClosedBanner extends StatelessWidget {
  const _StoreClosedBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.orange.shade100,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              message.isEmpty ? 'The store is closed right now.' : message,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartControllerProvider.notifier);
    return ListTile(
      leading: Text(line.emoji, style: const TextStyle(fontSize: 28)),
      title: Text(line.name),
      subtitle: Text('${line.unit} • ${formatMoney(line.unitPricePaise)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          QuantityStepper(
            quantity: line.quantity,
            canIncrement: line.quantity < line.maxPerOrder,
            onIncrement: () => cart.increment(line.productId),
            onDecrement: () => cart.decrement(line.productId),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => cart.remove(line.productId),
          ),
        ],
      ),
    );
  }
}

class _CouponSection extends ConsumerStatefulWidget {
  const _CouponSection();

  @override
  ConsumerState<_CouponSection> createState() => _CouponSectionState();
}

class _CouponSectionState extends ConsumerState<_CouponSection> {
  final _controller = TextEditingController();
  bool _applying = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final coupon = await ref.read(couponApiProvider).validate(code);
      await ref.read(cartControllerProvider.notifier).applyCoupon(coupon);
      _controller.clear();
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (!mounted) return;
    setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final coupon = cart.coupon;
    if (coupon != null) {
      final shortBy = coupon.minOrderPaise - cart.subtotalPaise;
      return Card(
        child: ListTile(
          leading: const Icon(Icons.local_offer, color: Colors.green),
          title: Text('${coupon.code} applied'),
          subtitle: Text(shortBy > 0
              ? 'Add ${formatMoney(shortBy)} more to use this coupon'
              : coupon.description),
          trailing: TextButton(
            onPressed: () =>
                ref.read(cartControllerProvider.notifier).removeCoupon(),
            child: const Text('Remove'),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Coupon code (try FLAT50, SAVE10)',
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _applying ? null : _apply,
              child: _applying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillDetails extends StatelessWidget {
  const _BillDetails({required this.pricing});

  final CartPricing pricing;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: bold
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null),
              ),
              Text(value,
                  style: bold
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bill details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            row('Items total', formatMoney(pricing.subtotalPaise)),
            if (pricing.discountPaise > 0)
              row('Coupon discount', '-${formatMoney(pricing.discountPaise)}'),
            row(
              'Delivery fee',
              pricing.deliveryFeePaise == 0
                  ? 'FREE'
                  : formatMoney(pricing.deliveryFeePaise),
            ),
            const Divider(),
            row('To pay', formatMoney(pricing.totalPaise), bold: true),
          ],
        ),
      ),
    );
  }
}

class _PlaceOrderBar extends ConsumerWidget {
  const _PlaceOrderBar({
    required this.totalPaise,
    required this.storeOpen,
  });

  final int totalPaise;
  final bool storeOpen;

  Future<void> _placeOrder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result =
        await ref.read(checkoutControllerProvider.notifier).placeOrder();
    if (!context.mounted) return;
    switch (result) {
      case CheckoutSuccess(:final order):
        navigator.pushReplacement(MaterialPageRoute<void>(
          builder: (_) => OrderSuccessScreen(order: order),
        ));
      case CheckoutNeedsReview review:
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _CheckoutReviewDialog(result: review),
        );
      case CheckoutFailure(:final message):
        messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placing =
        ref.watch(checkoutControllerProvider.select((s) => s.isPlacingOrder));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: Colors.green.shade800,
          ),
          onPressed:
              placing || !storeOpen ? null : () => _placeOrder(context, ref),
          child: Row(
            children: [
              Text(formatMoney(totalPaise),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              if (placing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              else
                Text(storeOpen ? 'Place order  ▶' : 'Store closed'),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutReviewDialog extends StatelessWidget {
  const _CheckoutReviewDialog({required this.result});

  final CheckoutNeedsReview result;

  @override
  Widget build(BuildContext context) {
    final lines = result.reconciliation.changes
        .map((change) => _changeDescription(change))
        .toList();
    return AlertDialog(
      title: const Text('Review your updated cart'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.message != null) Text(result.message!),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('• $line'),
              ),
            const SizedBox(height: 8),
            const Text('Review the updated items and total before placing '
                'your order again.'),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('I have reviewed the changes'),
        ),
      ],
    );
  }

  String _changeDescription(CartChange change) => switch (change) {
        PriceChanged(
          :final productId,
          :final oldPricePaise,
          :final newPricePaise,
          :final productName,
        ) =>
          '${productName ?? productId} price changed from '
              '${formatMoney(oldPricePaise)} to '
              '${formatMoney(newPricePaise)}.',
        OutOfStock(:final productId, :final productName) =>
          '${productName ?? productId} is out of stock and was removed.',
        QuantityReduced(
          :final productId,
          :final requestedQuantity,
          :final availableQuantity,
          :final productName,
        ) =>
          '${productName ?? productId} quantity changed from '
              '$requestedQuantity to '
              '$availableQuantity.',
        ProductUnavailable(:final productId, :final productName) =>
          '${productName ?? productId} is no longer sold and was removed.',
        CouponRemoved(:final code, :final reason) =>
          'Coupon $code was removed ($reason).',
      };
}
