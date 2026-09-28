insert into tickets (
    id,
    user_id,
    trip_id,
    ticket_code,
    status,
    product_id,
    valid_from_utc,
    valid_to_utc,
    price,
    currency
)
select
    :'ticket_id',
    t.user_id,
    t.trip_id,
    :'ticket_code',
    t.status,
    p.id,
    t.valid_from_utc,
    t.valid_to_utc,
    p.price,
    p.currency
from tickets t
cross join products p
where t.id = 'TICKET-1'
  and p.id = :'product_id'::uuid;
