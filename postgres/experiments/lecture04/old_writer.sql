insert into tickets (
    id,
    user_id,
    trip_id,
    ticket_code,
    status,
    product_code,
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
    'SINGLE',
    t.valid_from_utc,
    t.valid_to_utc,
    p.price,
    p.currency
from tickets t
join products p
  on p.code = 'SINGLE'
where t.id = 'TICKET-1';
