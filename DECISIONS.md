# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?** Immediately before checkout and again after a server conflict, so submitted line items, stock and coupon eligibility reflect current server state.
- **What does the user see for each kind of change?** Price increases and quantity reductions require review; price drops apply without blocking checkout. Removed items and invalid coupons are listed in the review.
- **What happens to out-of-stock / discontinued items?** They are removed from the candidate cart and shown in the reconciliation summary.
- **Offline-built carts:** Checkout fails closed if reconciliation cannot complete; it does not submit a partial or unverified order.
- **Alternatives considered and rejected:** Reusing stale cart prices/stock was rejected because it can produce invalid totals or orders.

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** A UUID idempotency key and cart/pricing snapshot are persisted for an order attempt and reused for retries, including after app restart; the server's idempotency record is authoritative.
- **What does the user see on timeout / lost response?** The client automatically retries once with the same key; if the outcome remains uncertain, it explains that and preserves the attempt for a later retry.
- **Edge cases you handled:** Concurrent taps share one in-flight request; timeouts reuse the key; price conflicts update the cart and require review; a known closed store is blocked before placing an order.
- **Edge cases you know you did NOT handle:** Idempotency state is device-local until the server receives the request, so a user starting a separate attempt on another device is outside this client-side protection.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:** Persist the last valid parsed config; on network or malformed-response errors, retain it, or use safe defaults if no valid cache exists.
- **How live updates propagate, and how you avoid leaks:** The config controller listens to repository updates and cancels its subscription when disposed.
- **Force / optional update UX:** Required updates block app use and open the configured store link. Optional updates can be dismissed for the current version; HTTP(S) links use `url_launcher`.
- **Store closed UX:** Home and cart show the closed state; checkout is disabled and guarded in the controller.
- **Server-driven home: robustness to bad config:** Parse known sections defensively, preserve configured ordering, ignore unknown/duplicate entries, and fall back to defaults for invalid or empty configuration.

## 4. Feature 3 (if attempted)

Search requests are sequenced so late responses cannot replace newer results; product/search and order-history views request fresh server data while repositories retain their offline cache behavior.

## 5. Other decisions

- Packages added (and why): `url_launcher` to open configured HTTP(S) update links on supported platforms.
- Refactors you made to the existing code (and why): Added an explicit force-refresh option to the API client so freshness-sensitive reads can bypass its shared GET cache without removing caching globally.

## 6. Looking ahead

- What would you do with one more week? Add end-to-end coverage across restart, offline/online transitions, remote config and platform-specific update-link behavior.
- What breaks first at 10× users (10k DAU)? What would you change? The mock service and client-side cache/state are not designed for that scale; introduce a production API with observability, server-side load testing, cache policy and durable order idempotency.
- How would you ship a hotfix for a critical bug without a store release? Use a server-side kill switch or remote-configured behavior when the issue is safely reversible there; otherwise ship a signed store update through the normal release pipeline.
