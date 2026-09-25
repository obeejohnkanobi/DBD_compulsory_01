-- 020_reporting_function.sql
-- Tilgang 2 af 4: en SQL-funktion, der pakker læselogikken ind.
--
-- Funktionen gemmer INGEN aggregeret tilstand selv. Den udfører den
-- samme join + filter + aggregat som base_revenue.sql, blot parametriseret
-- pr. operatør og dato, og udføres forfra ved hvert kald.
--
-- "stable" fortæller planlæggeren at funktionen ikke må ændre databasen og
-- at den kan genbruges inden for én forespørgsel/snapshot, men den
-- garanterer ikke friskhed på tværs af kald - hvert kald ser den tilstand
-- der er committed på kaldetidspunktet (samme MVCC-synlighed som en
-- almindelig SELECT).
--
-- Konsekvens for sammenligningen:
--   - Korrekthed: altid korrekt, fordi den altid regner direkte på
--     kildedataene. Der er intet at rette op på, hvis payments ændres.
--   - Friskhed: fuldstændig frisk - ingen lag, ingen refresh nødvendig.
--   - Skriveomkostning: nul, fordi intet skrives, når payments ændres.
--   - Læseomkostning: fuld pris pr. kald (join over payments/tickets/
--     trips/routes + aggregat), samme som den direkte forespørgsel.
--   - Genopbygning: irrelevant, der er ikke noget lager at genopbygge.
create or replace function captured_revenue_for_day(
    requested_operator_id text,
    requested_date date
)
returns table (
    captured_amount numeric,
    captured_payments bigint
)
language sql
stable
as $$
    select
        coalesce(sum(p.amount), 0),
        count(*)
    from payments p
    join tickets t on t.id = p.ticket_id
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where r.operator_id = requested_operator_id
      and p.created_utc::date = requested_date
      and p.status = 'Captured';
$$;
