select t.id,
       t.product_code,
       t.price,
       t.currency
from tickets t
order by t.id;
