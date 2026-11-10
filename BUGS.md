# Bugs found & fixed

> One section per bug. Order doesn't matter. Keep each one short and precise.
> Commit the reproducing test **before** the fix.

---

## BUG-1: Cart mutations were not all persisted (QK-101)

- **Symptom:** A cart could return with a stale quantity or coupon after the app restarted.
- **Steps to reproduce:**
  1. Add an item, decrement/remove it or remove a coupon.
  2. Restart the app and reopen the cart.
- **Root cause:** `CartController` did not persist every mutation consistently. Rapid asynchronous taps could also race writes.
- **Fix:** Persist each mutation and serialize writes so the final stored cart reflects the latest state.
- **Test:** `test/cart_persistence_test.dart` → `decrement is persisted and survives restart`; also covers remove, coupon removal and rapid increments.
- **Commits:** test `b020892` → fix `813765e`

---

## BUG-2: Catalog and order history could show stale data (QK-102)

- **Symptom:** Refresh/search and order history could keep showing values from the API client's in-memory GET cache.
- **Steps to reproduce:** Change a product price or place an order, then refresh the catalog or open order history before the cache expires.
- **Root cause:** The shared API GET cache outlived the freshness expected by these views; catalog offline-cache keys also needed to distinguish query parameters.
- **Fix:** Force fresh requests for catalog/search and order history, scope catalog cache entries correctly, and retain the repository cache for offline fallback.
- **Test:** `test/catalog_cache_test.dart` → `catalog refresh fetches updated server prices`; `test/order_history_refresh_test.dart` → `order history reflects a newly placed order without manual refresh`.
- **Commits:** test `b020892` → fix `813765e`

---

## BUG-3: Free delivery threshold was exclusive

- **Symptom:** A cart totaling exactly the configured threshold was charged a delivery fee.
- **Root cause:** Cart pricing used a strict greater-than comparison while the business rule and server treat the threshold as inclusive.
- **Fix:** Make the client comparison inclusive.
- **Test:** `test/cart_pricing_boundary_test.dart` → exact-threshold case.
- **Commits:** test `b020892` → fix `813765e`

---

## BUG-4: Legacy product responses were parsed incorrectly

- **Symptom:** Products with a null MRP or string-valued stock could be displayed with invalid pricing or stock.
- **Root cause:** `ProductDto` assumed the newer response types and required an MRP even when the legacy endpoint omitted it.
- **Fix:** Fall back to selling price for a missing MRP and parse stock values from either supported representation.
- **Test:** `test/product_dto_test.dart` → `parses legacy nullable MRP and string stock`.
- **Commits:** test `b020892` → fix `813765e`

---

## BUG-5: Older search requests could overwrite newer results

- **Symptom:** A slow response for an earlier query could replace results for the latest query.
- **Root cause:** Search responses were applied without checking whether a newer request had already started.
- **Fix:** Apply results only for the current request sequence and bypass the stale in-memory API cache.
- **Test:** `test/search_controller_test.dart` → `a slower earlier search cannot replace newer results`.
- **Commits:** test `b020892` → fix `813765e`

---

## Suspicious but NOT a bug

- Timeout does not prove that order creation failed. The client now retries with the same idempotency key rather than assuming it is safe to create a new order.
