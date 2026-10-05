-- Run each statement separately after applying the integrity migration.
-- These use existing seed rows; they do not need extra test rows.

-- Negative capacity -> CHECK violation.
update trips
set capacity = -1
where id = 'TRIP-M2-20260429-0800';

-- Reserved seats greater than capacity -> CHECK violation.
update trips
set reserved_seats = capacity + 1
where id = 'TRIP-M2-20260429-0800';

-- Negative ticket price -> CHECK violation.
update tickets
set price = -1
where id = 'TICKET-1';

-- Negative payment amount -> CHECK violation.
update payments
set amount = -1
where id = 'PAYMENT-1';

-- Unsupported currency -> CHECK violation.
update tickets
set currency = 'XYZ'
where id = 'TICKET-1';

-- Duplicate ticket code -> UNIQUE violation.
update tickets
set ticket_code = 'CODE-M2-0001'
where id = 'TICKET-2';

-- Unknown trip referenced by a ticket -> FOREIGN KEY violation.
update tickets
set trip_id = 'TRIP-DOES-NOT-EXIST'
where id = 'TICKET-1';

-- Payment referencing an unknown ticket -> FOREIGN KEY violation.
update payments
set ticket_id = 'TICKET-DOES-NOT-EXIST'
where id = 'PAYMENT-1';

-- Validation combines the id of one ticket with the code of another -> FOREIGN KEY violation.
update validations
set ticket_id = 'TICKET-1'
where id = 'VALIDATION-1';

-- Reversed validity window -> CHECK violation.
update tickets
set valid_to_utc = valid_from_utc - interval '1 minute'
where id = 'TICKET-1';

-- Unknown ticket status -> CHECK violation.
update tickets
set status = 'Unknown'
where id = 'TICKET-1';

-- Duplicate external payment reference -> UNIQUE violation.
update payments
set external_payment_reference = 'gateway-capture-0001'
where id = 'PAYMENT-2';
