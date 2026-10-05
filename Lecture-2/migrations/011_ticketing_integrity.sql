begin;


alter table trips
    alter column capacity set not null,                 -- Invarient Row 1
    alter column reserved_seats set not null,           -- Invarient Row 2
    add check (capacity >= 0),                          -- Invarient Row 1
    add check (reserved_seats between 0 and capacity);  -- Invarient Row 2

alter table products
    alter column currency set not null,            -- Invarient Row 5
    add check (price >= 0),                        -- Invarient Row 3
    add check (currency in ('DKK', 'EUR', 'USD')); -- Invarient Row 5

alter table tickets
    alter column user_id set not null,                 -- Invarient Row 7
    alter column trip_id set not null,                 -- Invarient Row 7
    alter column product_code set not null,            -- Invarient Row 7
    alter column ticket_code set not null,             -- Invarient Row 6
    alter column currency set not null,                -- Invarient Row 5
    add unique (ticket_code),                          -- Invarient Row 6
    add unique (id, ticket_code),                      -- Invarient Row 9
    add foreign key (user_id) references users (id)    -- Invarient Row 7
        on delete restrict on update restrict,
    add foreign key (trip_id) references trips (id)    -- Invarient Row 7
        on delete restrict on update restrict,
    add foreign key (product_code) references products (code)     -- Invarient Row 7
        on delete restrict on update restrict,
    add check (price >= 0),                            -- Invarient Row 3
    add check (currency in ('DKK', 'EUR', 'USD')),     -- Invarient Row 5
    add check (valid_to_utc >= valid_from_utc);        -- Invarient Row 10

alter table payments
    alter column ticket_id set not null,     -- Invarient Row 8
    alter column currency set not null,      -- Invarient Row 5
    add foreign key (ticket_id) references tickets (id)     -- Invarient Row 8
        on delete restrict on update restrict,
    add unique (external_payment_reference), -- Invarient Row 12
    add check (amount >= 0),                 -- Invarient Row 4
    add check (currency in ('DKK', 'EUR', 'USD'));          -- Invarient Row 5

alter table validations
    add foreign key (ticket_id, ticket_code) -- Invarient Row 9
        references tickets (id, ticket_code)
        on delete restrict on update restrict;

commit;
