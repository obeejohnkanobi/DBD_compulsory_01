# Integrity map

| # | Invariant — what must always be true? | Affected table(s) / column(s) | Classification / mechanism | DDL used | Expected failure | Evidence / result |
|---|---|---|---|---|---|---|
| 1 | Capacity cannot be negative. | `trips.capacity` | Direct constraint | `NOT NULL`, `CHECK (capacity >= 0)` | `23514` check violation | Valid: `capacity = 120`; invalid: `capacity = -1` -> `23514` |
| 2 | Reserved seats cannot be negative or exceed capacity. | `trips.reserved_seats`, `trips.capacity` | Direct constraint | `NOT NULL`, `CHECK (reserved_seats BETWEEN 0 AND capacity)` | `23514` check violation | Valid: `reserved_seats = 2`; invalid: `-1` or `capacity + 1` -> `23514` |
| 3 | Product and ticket prices cannot be negative. | `products.price`, `tickets.price` | Direct constraint | `CHECK (price >= 0)` | `23514` check violation | Valid: `36.00`; invalid: `-1` -> `23514` |
| 4 | Payment amount cannot be negative. | `payments.amount` | Direct constraint | `CHECK (amount >= 0)` | `23514` check violation | Valid: `36.00`; invalid: `-1` -> `23514` |
| 5 | Currency must be present and use the same representation. | `products.currency`, `tickets.currency`, `payments.currency` | Direct constraint | `NOT NULL`, `CHECK (currency IN ('DKK','EUR','USD'))` | `23514` check violation | Valid: `DKK`; invalid: `XYZ` -> `23514` |
| 6 | Ticket codes must identify tickets unambiguously. | `tickets.ticket_code` | Unique rule | `NOT NULL`, `UNIQUE (ticket_code)` | `23505` unique violation | Valid existing codes succeed; duplicate code -> `23505` |
| 7 | A ticket must reference an existing user, trip and product. | `tickets.user_id`, `trip_id`, `product_code` | Referential constraint | `NOT NULL` + three `FOREIGN KEY`s | `23503` FK violation | Existing references succeed; unknown reference -> `23503` |
| 8 | A payment must reference an existing ticket. | `payments.ticket_id` | Referential constraint | `NOT NULL`, `FOREIGN KEY (ticket_id)` | `23503` FK violation | Existing ticket succeeds; unknown ticket -> `23503` |
| 9 | A validation must reference one existing ticket, and its id/code must belong to that same ticket. | `validations.ticket_id`, `ticket_code` | Referential constraint | `UNIQUE (tickets.id, ticket_code)` + composite `FOREIGN KEY` | `23503` FK violation | Existing pair succeeds; mixed id/code -> `23503` |
| 10 | Ticket validity cannot end before it begins. | `tickets.valid_from_utc`, `valid_to_utc` | Direct constraint | `CHECK (valid_to_utc >= valid_from_utc)` | `23514` check violation | Normal window succeeds; reversed window -> `23514` |
| 11 | Ticket and payment statuses must come from known sets. | `tickets.status`, `payments.status` | Direct constraint | `CHECK (... IN (...))` | `23514` check violation | Seed statuses succeed; `Unknown` -> `23514` |
| 12 | The same external payment reference must not be recorded twice. | `payments.external_payment_reference` | Unique rule | `UNIQUE (external_payment_reference)` | `23505` unique violation | Existing distinct refs succeed; duplicate ref -> `23505` |

## Issue register

### Issue 1 — concurrent seat purchase

- Evidence: `reserved_seats <= capacity` is checked on each stored trip row.
- Problem: two transactions can both observe remaining capacity before either commits.
- Consequence: a row-level `CHECK` does not solve the race.
- Specific improvement: handle it in the transactions lecture with an atomic update/locking strategy.
- Open question: what purchase/hold behaviour should the application use?

### Issue 2 — external payment capture

- Evidence: PostgreSQL can make `external_payment_reference` unique.
- Problem: it cannot make an external gateway action and a database transaction atomic.
- Consequence: capture and local recording can diverge after failures/retries.
- Specific improvement: use idempotent workflow/reconciliation logic.
- Open question: which payment states and retry rules does the domain require?

### Issue 3 — disabled users

- Evidence: `users.is_disabled` exists, but the lab does not define whether disabled users are forbidden from buying.
- Problem: the intended rule is ambiguous.
- Consequence: enforcing a guessed rule could reject valid business cases.
- Specific improvement: make the domain decision first.
- Open question: may disabled users buy, or only be prevented from future account actions?

## State-transition trace

### Ticket purchase

1. The referenced `user`, `trip`, and `product` must already exist.
2. Insert the ticket with a unique code, accepted status/currency, non-negative price, and a valid time window; update the trip's `reserved_seats` without making the stored row invalid.
3. Insert the payment referencing the ticket, with a non-negative amount, accepted currency/status, and a non-duplicate external payment reference.

Concurrency is intentionally not analysed here.

### Ticket validation

1. The ticket must already exist.
2. Insert a validation whose `(ticket_id, ticket_code)` pair matches that same ticket.
3. If the workflow changes the ticket status to `Validated`, the new status must be in the accepted set.

## Delete and update behaviour

| Relationship | Delete behaviour | Update behaviour |
|---|---|---|
| `tickets.user_id -> users.id` | Restrict; keep the historical ticket. Prefer soft deletion/disablement of the user if needed. | Reject an id change that would rewrite ticket history. |
| `tickets.trip_id -> trips.id` | Restrict; do not delete a trip that historical tickets reference. | Reject changing the referenced trip identity. |
| `tickets.product_code -> products.code` | Restrict; keep the product identity used by historical tickets. | Reject changing the referenced product code. |
| `payments.ticket_id -> tickets.id` | Restrict; payment history must not disappear because a ticket is deleted. | Reject changing the ticket identity. |
| `validations.(ticket_id,ticket_code) -> tickets.(id,ticket_code)` | Restrict; validation history must remain attached to its ticket. | Reject changes that would alter the historical ticket identity/code. |

The migration uses `ON DELETE RESTRICT ON UPDATE RESTRICT` for these relationships. Longer-term removal of financial/audit history should be handled by an explicit retention policy rather than cascades.
