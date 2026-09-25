-- 022_daily_captured_revenue.sql
-- Tilgang 3 af 4: en materialiseret view.
--
-- Definitionen er identisk med base_revenue.sql, men resultatet gemmes
-- fysisk på disk ved oprettelse/refresh og ændrer sig IKKE, når payments
-- ændres - kun "refresh materialized view" opdaterer den.
--
-- "with no data" betyder viewet oprettes tomt (ikke scanbart) indtil
-- første refresh. Det unikke index på (operator_id, revenue_date) er en
-- forudsætning for at kunne bruge "refresh ... concurrently" senere, så
-- refresh ikke tager en exclusive lock, der blokerer samtidige læsere.
--
-- Konsekvens for sammenligningen:
--   - Korrekthed: korrekt for den tilstand af payments, der var
--     committed på tidspunktet for sidste refresh - aldrig for "lige nu".
--   - Friskhed: styret eksplicit og synligt (en refresh er en observerbar
--     handling), i modsætning til triggerens stille, indbyggede drift.
--   - Skriveomkostning: nul ved hver payments-ændring; hele omkostningen
--     ligger samlet i det øjeblik nogen kører refresh (fuld genberegning).
--   - Læseomkostning: meget lav (indeks-opslag på den lagrede tabel).
--   - Genopbygning: triviel og indbygget i motoren - "refresh materialized
--     view daily_captured_revenue" er selve genopbygningen.
create materialized view daily_captured_revenue as
select
    r.operator_id,
    p.created_utc::date as revenue_date,
    sum(p.amount) as captured_amount,
    count(*) as captured_payments
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date
with no data;

create unique index daily_captured_revenue_key
    on daily_captured_revenue (operator_id, revenue_date);

-- Run explicitly when the source data should become visible:
-- refresh materialized view daily_captured_revenue;
-- eller uden at blokere samtidige læsere (kræver det unikke index ovenfor):
-- refresh materialized view concurrently daily_captured_revenue;
