# AI usage log

Tools used: Copilot in VS Code

## Significant prompts (5–10)

| # | What I asked (summary is fine) | What I did with the answer |
|---|---|---|
| 1 | Review the assignment, docs, source and tests without editing; prepare Parts A–C plan. | Read the repository and used the plan as the implementation checklist after approval. |
| 2 | Implement the approved Parts A–C plan with regression coverage. | Added tests first, then implemented cart, checkout, catalog and remote-config changes. |
| 3 | Address stale catalog/search and order-history data. | Added targeted forced-refresh behavior and tests while retaining offline repository caching. |
| 4 | Verify the completed implementation. | Ran the full Flutter test suite and analyzer; both passed. |

## When the AI was wrong or misleading (at least 3)

### 1.
- **What it suggested:** An initial cart-persistence test setup used a key-value store instance separate from the one read by the controller.
- **Why it was wrong:** The fixture did not model the application's shared dependency, so it could not reliably verify state surviving controller recreation.
- **How I noticed:** The persistence assertion failed despite the controller mutation path appearing correct.
- **What I did instead:** Shared the test store through the same dependency setup used by the controller and reran the regression.

### 2.
- **What it suggested:** A catalog refresh test expected only the catalog endpoint request.
- **Why it was wrong:** The test's request count also included an order-history GET triggered by the tested flow.
- **How I noticed:** Inspecting recorded request paths showed the extra request was unrelated to catalog refresh.
- **What I did instead:** Asserted the relevant endpoint request directly rather than using a misleading total count.

### 3.
- **What it suggested:** The first cache-bypass change covered product listing refresh but left search on the shared API GET cache.
- **Why it was wrong:** Search can also return stale results until that cache expires, contrary to the intended freshness behavior.
- **How I noticed:** Tracing the catalog search path showed it used the same cached GET mechanism.
- **What I did instead:** Applied forced refresh to search as well and added stale-response coverage.

## What I would NOT trust an AI with in this codebase, and why

I would not trust generated assumptions about business-rule boundaries, API response compatibility, or order retry safety without checking the documented rules and mock-server behavior. I verified those cases with focused tests and kept the protected server/transport files unchanged.
