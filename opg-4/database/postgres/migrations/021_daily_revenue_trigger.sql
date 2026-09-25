-- 021_daily_revenue_trigger.sql
-- Tilgang 4 af 4: en trigger-vedligeholdt opsummeringstabel.
--
-- VIGTIGT: denne trigger er BEVIDST ufuldstændig og er anvendt uændret,
-- som den blev udleveret. Den håndterer kun INSERT, og kun grenen hvor den
-- nye række allerede er 'Captured'. Formålet med laboratoriet er at gøre
-- konsekvenserne af det observerbare, FØR man forsøger at udvide triggeren
-- med flere grene - se docs/lab-report.md for den fulde analyse.
--
-- Det denne trigger IKKE gør (bekræftet ved eksperimenterne i
-- database/postgres/experiments/run_all_cases.sql):
--   1. UPDATE på payments.status udløser INGEN trigger overhovedet, fordi
--      der kun er oprettet en AFTER INSERT-trigger. En rettelse fra
--      'Failed' til 'Captured' bliver derfor ALDRIG lagt til tabellen
--      (permanent undertælling), og en rettelse fra 'Captured' til
--      'Refunded' bliver ALDRIG trukket fra (permanent overtælling).
--   2. DELETE på payments udløser heller ingen trigger, så en slettet
--      betaling forbliver i den akkumulerede sum for evigt.
--   3. Dubletlevering (samme external_payment_reference, ny payments.id)
--      rammer den samme INSERT-gren som en ægte betaling og bliver talt
--      med igen - triggeren har ingen viden om, hvad der er "samme"
--      betaling. Det gør de tre andre tilgange heller ikke: dubletter er
--      et data-integritetsproblem (mangler unik/idempotent nøgle på
--      external_payment_reference), ikke et rapporteringsproblem.
--
-- Konsekvens for sammenligningen:
--   - Korrekthed: kun korrekt for den simple "ny betaling, allerede
--     Captured, aldrig rettet eller slettet"-vej. Alt andet driver stille
--     væk fra sandheden uden fejl eller advarsel.
--   - Friskhed: synkron og med det samme for de tilfælde den håndterer,
--     fordi triggeren kører i samme transaktion som INSERT'en.
--   - Skriveomkostning: en ekstra join (tickets/trips/routes) plus en
--     UPSERT-lås på (operator_id, revenue_date) for hver INSERT i
--     payments - betales selv når ingen læser rapporten.
--   - Skjulte sideeffekter: en enkelt INSERT i payments kan nu fejle eller
--     blokere på grund af lås-konflikt i en helt anden tabel
--     (daily_revenue_by_operator), og fejlen forplanter sig tilbage til
--     kaldestedet for betalingen.
--   - Genopbygning: findes ikke i denne migration. Se decision-record i
--     docs/lab-report.md for det anbefalede genopbygningstrin
--     (TRUNCATE + INSERT ... SELECT fra basisforespørgslen).
create table daily_revenue_by_operator (
    operator_id text not null references operators(id),
    revenue_date date not null,
    captured_amount numeric not null default 0,
    captured_payments bigint not null default 0,
    primary key (operator_id, revenue_date)
);

create or replace function add_inserted_payment_to_daily_revenue()
returns trigger
language plpgsql
as $$
declare
    payment_operator_id text;
begin
    if new.status is distinct from 'Captured' then
        return new;
    end if;

    select r.operator_id
    into payment_operator_id
    from tickets t
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where t.id = new.ticket_id;

    insert into daily_revenue_by_operator (
        operator_id, revenue_date, captured_amount, captured_payments
    ) values (
        payment_operator_id, new.created_utc::date, new.amount, 1
    )
    on conflict (operator_id, revenue_date)
    do update set
        captured_amount = daily_revenue_by_operator.captured_amount + excluded.captured_amount,
        captured_payments = daily_revenue_by_operator.captured_payments + 1;

    return new;
end;
$$;

create trigger payments_daily_revenue_after_insert
after insert on payments
for each row
execute function add_inserted_payment_to_daily_revenue();

-- TODO: analyse corrections, refunds, deletes, initial backfill, and duplicate delivery.
-- Do not add more trigger branches before documenting the behaviour.
-- (Dokumenteret i docs/lab-report.md - triggeren er med vilje IKKE udvidet,
-- da hele pointen med opgaven er at gøre driften synlig og målbar.)
