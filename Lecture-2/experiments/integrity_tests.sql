\set ON_ERROR_STOP on

begin;

-- Valid writes using only existing seed rows.
update trips
set capacity = 120, reserved_seats = 2
where id = 'TRIP-M2-20260429-0800';

update products
set price = 36.00, currency = 'DKK'
where code = 'SINGLE';

update tickets
set user_id = 'USER-1',
    trip_id = 'TRIP-M2-20260429-0800',
    product_code = 'SINGLE',
    ticket_code = 'CODE-M2-0001',
    status = 'Active',
    price = 36.00,
    currency = 'DKK',
    valid_from_utc = '2026-04-29 07:45:00+00',
    valid_to_utc = '2026-04-29 10:00:00+00'
where id = 'TICKET-1';

update payments
set ticket_id = 'TICKET-1',
    external_payment_reference = 'gateway-capture-0001',
    amount = 36.00,
    currency = 'DKK',
    status = 'Captured'
where id = 'PAYMENT-1';

update validations
set ticket_id = 'TICKET-2', ticket_code = 'CODE-5C-0001'
where id = 'VALIDATION-1';

-- Invalid writes. Each block asserts the PostgreSQL SQLSTATE.

-- 1. Capacity cannot be negative. 23514 = check_violation.
do $$
begin
    begin
        update trips set capacity = -1 where id = 'TRIP-M2-20260429-0800';
        raise exception 'TEST FAILED: negative capacity accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;
end $$;

-- 2. Reserved seats must stay between 0 and capacity.
do $$
begin
    begin
        update trips set reserved_seats = -1 where id = 'TRIP-M2-20260429-0800';
        raise exception 'TEST FAILED: negative reserved seats accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;

    begin
        update trips set reserved_seats = capacity + 1 where id = 'TRIP-M2-20260429-0800';
        raise exception 'TEST FAILED: reserved seats above capacity accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;
end $$;

-- 3. Product and ticket prices cannot be negative.
do $$
begin
    begin
        update products set price = -1 where code = 'SINGLE';
        raise exception 'TEST FAILED: negative product price accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;

    begin
        update tickets set price = -1 where id = 'TICKET-1';
        raise exception 'TEST FAILED: negative ticket price accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;
end $$;

-- 4. Payment amount cannot be negative.
do $$
begin
    begin
        update payments set amount = -1 where id = 'PAYMENT-1';
        raise exception 'TEST FAILED: negative payment amount accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;
end $$;

-- 5. Currency is required and uses the same accepted representation.
do $$
begin
    begin
        update products set currency = 'XYZ' where code = 'SINGLE';
        raise exception 'TEST FAILED: invalid product currency accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;

    begin
        update tickets set currency = 'XYZ' where id = 'TICKET-1';
        raise exception 'TEST FAILED: invalid ticket currency accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;

    begin
        update payments set currency = 'XYZ' where id = 'PAYMENT-1';
        raise exception 'TEST FAILED: invalid payment currency accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;
end $$;

-- 6. Ticket codes are unique. 23505 = unique_violation.
do $$
begin
    begin
        update tickets set ticket_code = 'CODE-M2-0001' where id = 'TICKET-2';
        raise exception 'TEST FAILED: duplicate ticket code accepted';
    exception when unique_violation then
        if sqlstate <> '23505' then raise; end if;
    end;
end $$;

-- 7. Tickets reference existing users, trips and products. 23503 = foreign_key_violation.
do $$
begin
    begin
        update tickets set user_id = 'NO-SUCH-USER' where id = 'TICKET-1';
        raise exception 'TEST FAILED: unknown user accepted';
    exception when foreign_key_violation then
        if sqlstate <> '23503' then raise; end if;
    end;

    begin
        update tickets set trip_id = 'NO-SUCH-TRIP' where id = 'TICKET-1';
        raise exception 'TEST FAILED: unknown trip accepted';
    exception when foreign_key_violation then
        if sqlstate <> '23503' then raise; end if;
    end;

    begin
        update tickets set product_code = 'NO-SUCH-PRODUCT' where id = 'TICKET-1';
        raise exception 'TEST FAILED: unknown product accepted';
    exception when foreign_key_violation then
        if sqlstate <> '23503' then raise; end if;
    end;
end $$;

-- 8. Payments reference an existing ticket.
do $$
begin
    begin
        update payments set ticket_id = 'NO-SUCH-TICKET' where id = 'PAYMENT-1';
        raise exception 'TEST FAILED: payment with unknown ticket accepted';
    exception when foreign_key_violation then
        if sqlstate <> '23503' then raise; end if;
    end;
end $$;

-- 9. A validation's ticket id and code must identify the same existing ticket.
do $$
begin
    begin
        update validations set ticket_id = 'TICKET-1' where id = 'VALIDATION-1';
        raise exception 'TEST FAILED: mismatched ticket id/code accepted';
    exception when foreign_key_violation then
        if sqlstate <> '23503' then raise; end if;
    end;
end $$;

-- 10. Ticket validity cannot end before it begins.
do $$
begin
    begin
        update tickets
        set valid_to_utc = valid_from_utc - interval '1 minute'
        where id = 'TICKET-1';
        raise exception 'TEST FAILED: reversed validity window accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;
end $$;

-- 11. Ticket and payment statuses come from known sets.
do $$
begin
    begin
        update tickets set status = 'Unknown' where id = 'TICKET-1';
        raise exception 'TEST FAILED: unknown ticket status accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;

    begin
        update payments set status = 'Unknown' where id = 'PAYMENT-1';
        raise exception 'TEST FAILED: unknown payment status accepted';
    exception when check_violation then
        if sqlstate <> '23514' then raise; end if;
    end;
end $$;

-- 12. One external payment reference cannot be recorded twice.
do $$
begin
    begin
        update payments
        set external_payment_reference = 'gateway-capture-0001'
        where id = 'PAYMENT-2';
        raise exception 'TEST FAILED: duplicate external payment reference accepted';
    exception when unique_violation then
        if sqlstate <> '23505' then raise; end if;
    end;
end $$;

rollback;
