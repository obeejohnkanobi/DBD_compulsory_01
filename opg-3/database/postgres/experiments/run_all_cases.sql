-- run_all_cases.sql
-- Instrumenteret udgave af reporting_cases.sql: samme seks testcases, men
-- efter hvert skridt aflæses ALLE FIRE tilgange (direkte forespørgsel,
-- funktion, materialiseret view, trigger-tabel), så man kan se dem drive
-- fra hinanden i realtid. Kør efter alle tre migrationer (020, 021, 022)
-- er anvendt. Start fra en frisk container for at gentage præcist.
--
-- Det fulde, faktiske output af at køre denne fil gemmes i
-- docs/evidence-run-output.txt og opsummeres i docs/lab-report.md.

set timezone = 'UTC';

\echo '=== BASELINE ==='
\echo '-- 1) direkte forespørgsel --'
select r.operator_id, p.created_utc::date as revenue_date,
       sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date
order by 1, 2;

\echo '-- 2) funktion --'
select 'OP-METRO' as operator_id, * from captured_revenue_for_day('OP-METRO', '2026-04-29')
union all
select 'OP-BUS' as operator_id, * from captured_revenue_for_day('OP-BUS', '2026-04-29');

\echo '-- 3) materialiseret view: tom/upopuleret indtil første refresh --'
do $$
begin
    perform * from daily_captured_revenue;
exception
    when object_not_in_prerequisite_state then
        raise notice 'controlled expected error: %', sqlerrm;
end
$$;
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;

\echo '-- 4) trigger-tabel: tom ved oprettelse, INGEN backfill sker automatisk --'
select * from daily_revenue_by_operator order by operator_id, revenue_date;

\echo '=== REBUILD PATH: manuel backfill af daily_revenue_by_operator fra autoriteten ==='
truncate table daily_revenue_by_operator;
insert into daily_revenue_by_operator (operator_id, revenue_date, captured_amount, captured_payments)
select r.operator_id, p.created_utc::date, sum(p.amount), count(*)
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date;
select * from daily_revenue_by_operator order by operator_id, revenue_date;

-- ---------------------------------------------------------------------
\echo '=== CASE 1: captured payment insert ==='
insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status, created_utc)
values ('PAY-CASE-CAPTURED', 'USER-1', 'TICKET-1', 'gateway-case-captured', 36, 'DKK', 'Captured', '2026-04-29 10:00:00+00');

\echo '-- 1) direkte forespørgsel --'
select r.operator_id, p.created_utc::date as revenue_date, sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id=p.ticket_id join trips tr on tr.id=t.trip_id join routes r on r.id=tr.route_id
where p.status='Captured' group by r.operator_id, p.created_utc::date order by 1,2;
\echo '-- 2) funktion --'
select 'OP-METRO' as operator_id, * from captured_revenue_for_day('OP-METRO','2026-04-29')
union all
select 'OP-BUS' as operator_id, * from captured_revenue_for_day('OP-BUS','2026-04-29');
\echo '-- 3a) materialiseret view før refresh (stale) --'
select * from daily_captured_revenue order by operator_id, revenue_date;
\echo '-- 4) trigger-tabel --'
select * from daily_revenue_by_operator order by operator_id, revenue_date;
\echo '-- 3b) materialiseret view efter refresh --'
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;

-- ---------------------------------------------------------------------
\echo '=== CASE 2: failed payment insert ==='
insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status, created_utc)
values ('PAY-CASE-FAILED', 'USER-1', 'TICKET-1', 'gateway-case-failed', 50, 'DKK', 'Failed', '2026-04-29 10:05:00+00');

\echo '-- 1) direkte forespørgsel --'
select r.operator_id, p.created_utc::date as revenue_date, sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id=p.ticket_id join trips tr on tr.id=t.trip_id join routes r on r.id=tr.route_id
where p.status='Captured' group by r.operator_id, p.created_utc::date order by 1,2;
\echo '-- 2) funktion --'
select 'OP-METRO' as operator_id, * from captured_revenue_for_day('OP-METRO','2026-04-29')
union all
select 'OP-BUS' as operator_id, * from captured_revenue_for_day('OP-BUS','2026-04-29');
\echo '-- 3a) materialiseret view før refresh --'
select * from daily_captured_revenue order by operator_id, revenue_date;
\echo '-- 4) trigger-tabel --'
select * from daily_revenue_by_operator order by operator_id, revenue_date;
\echo '-- 3b) materialiseret view efter refresh --'
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;

-- ---------------------------------------------------------------------
\echo '=== CASE 3: status correction Failed -> Captured ==='
update payments set status = 'Captured' where id = 'PAY-CASE-FAILED';

\echo '-- 1) direkte forespørgsel --'
select r.operator_id, p.created_utc::date as revenue_date, sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id=p.ticket_id join trips tr on tr.id=t.trip_id join routes r on r.id=tr.route_id
where p.status='Captured' group by r.operator_id, p.created_utc::date order by 1,2;
\echo '-- 2) funktion --'
select 'OP-METRO' as operator_id, * from captured_revenue_for_day('OP-METRO','2026-04-29')
union all
select 'OP-BUS' as operator_id, * from captured_revenue_for_day('OP-BUS','2026-04-29');
\echo '-- 3a) materialiseret view før refresh (stale) --'
select * from daily_captured_revenue order by operator_id, revenue_date;    -- stale before refresh
\echo '-- 4) trigger-tabel --'
select * from daily_revenue_by_operator order by operator_id, revenue_date; -- never updates: no UPDATE trigger
\echo '-- 3b) materialiseret view efter refresh --'
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;    -- now agrees with direct query

-- ---------------------------------------------------------------------
\echo '=== CASE 4: status correction Captured -> Refunded ==='
update payments set status = 'Refunded' where id = 'PAY-CASE-CAPTURED';

\echo '-- 1) direkte forespørgsel --'
select r.operator_id, p.created_utc::date as revenue_date, sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id=p.ticket_id join trips tr on tr.id=t.trip_id join routes r on r.id=tr.route_id
where p.status='Captured' group by r.operator_id, p.created_utc::date order by 1,2;
\echo '-- 2) funktion --'
select 'OP-METRO' as operator_id, * from captured_revenue_for_day('OP-METRO','2026-04-29')
union all
select 'OP-BUS' as operator_id, * from captured_revenue_for_day('OP-BUS','2026-04-29');
\echo '-- 3a) materialiseret view før refresh (stale) --'
select * from daily_captured_revenue order by operator_id, revenue_date;    -- stale before refresh
\echo '-- 4) trigger-tabel --'
select * from daily_revenue_by_operator order by operator_id, revenue_date; -- never drops: no UPDATE trigger
\echo '-- 3b) materialiseret view efter refresh --'
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;

-- ---------------------------------------------------------------------
\echo '=== CASE 5: deletion of test data ==='
delete from payments where id = 'PAY-CASE-FAILED';

\echo '-- 1) direkte forespørgsel --'
select r.operator_id, p.created_utc::date as revenue_date, sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id=p.ticket_id join trips tr on tr.id=t.trip_id join routes r on r.id=tr.route_id
where p.status='Captured' group by r.operator_id, p.created_utc::date order by 1,2;
\echo '-- 2) funktion --'
select 'OP-METRO' as operator_id, * from captured_revenue_for_day('OP-METRO','2026-04-29')
union all
select 'OP-BUS' as operator_id, * from captured_revenue_for_day('OP-BUS','2026-04-29');
\echo '-- 3a) materialiseret view før refresh (stale) --'
select * from daily_captured_revenue order by operator_id, revenue_date;    -- stale before refresh
\echo '-- 4) trigger-tabel --'
select * from daily_revenue_by_operator order by operator_id, revenue_date; -- never drops: no DELETE trigger
\echo '-- 3b) materialiseret view efter refresh --'
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;

-- ---------------------------------------------------------------------
\echo '=== CASE 6: duplicate delivery of the same external payment reference ==='
insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status, created_utc)
values ('PAY-CASE-DUPLICATE', 'USER-1', 'TICKET-1', 'gateway-capture-0001', 36, 'DKK', 'Captured', '2026-04-29 10:10:00+00');

select external_payment_reference, count(*) from payments where external_payment_reference = 'gateway-capture-0001' group by 1;
\echo '-- 1) direkte forespørgsel --'
select r.operator_id, p.created_utc::date as revenue_date, sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id=p.ticket_id join trips tr on tr.id=t.trip_id join routes r on r.id=tr.route_id
where p.status='Captured' group by r.operator_id, p.created_utc::date order by 1,2; -- also double-counts
\echo '-- 2) funktion --'
select 'OP-METRO' as operator_id, * from captured_revenue_for_day('OP-METRO','2026-04-29')
union all
select 'OP-BUS' as operator_id, * from captured_revenue_for_day('OP-BUS','2026-04-29');
\echo '-- 3a) materialiseret view før refresh (stale) --'
select * from daily_captured_revenue order by operator_id, revenue_date;             -- stale before refresh
\echo '-- 4) trigger-tabel --'
select * from daily_revenue_by_operator order by operator_id, revenue_date;          -- also double-counts
\echo '-- 3b) materialiseret view efter refresh --'
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;

-- ---------------------------------------------------------------------
\echo '=== SIDE-EFFECT TRACE: EXPLAIN ANALYZE on one INSERT INTO payments ==='
explain analyze
insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status, created_utc)
values ('PAY-TRACE-1', 'USER-1', 'TICKET-1', 'gateway-trace-0001', 36, 'DKK', 'Captured', '2026-04-29 10:20:00+00');

\echo '=== ROLLBACK CHECK: trigger writes share the inserting transaction ==='
begin;
insert into payments (id, user_id, ticket_id, external_payment_reference, amount, currency, status, created_utc)
values ('PAY-TRACE-ROLLBACK', 'USER-1', 'TICKET-1', 'gateway-trace-rollback', 999, 'DKK', 'Captured', '2026-04-29 10:25:00+00');
select * from daily_revenue_by_operator order by operator_id, revenue_date; -- visible mid-transaction
rollback;
select * from daily_revenue_by_operator order by operator_id, revenue_date; -- reverted
select count(*) from payments where id = 'PAY-TRACE-ROLLBACK';             -- 0

delete from payments where id = 'PAY-TRACE-1';

-- ---------------------------------------------------------------------
\echo '=== FINAL REBUILD: restore daily_revenue_by_operator from the authority ==='
truncate table daily_revenue_by_operator;
insert into daily_revenue_by_operator (operator_id, revenue_date, captured_amount, captured_payments)
select r.operator_id, p.created_utc::date, sum(p.amount), count(*)
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date;
select * from daily_revenue_by_operator order by operator_id, revenue_date;
refresh materialized view daily_captured_revenue;
select * from daily_captured_revenue order by operator_id, revenue_date;
