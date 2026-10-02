# Lab-rapport: Hvor skal rapporteringslogikken ligge?

Alt output i denne rapport er reelt fanget ved at køre migrationerne og
`database/postgres/experiments/run_all_cases.sql` mod en frisk database.
Den fulde seneste kørsel er gemt i `docs/evidence-run-output.txt`.
Intet er gættet eller konstrueret bagefter; de samme SQL-filer kan køres
igen mod en ren database og giver samme rækkefølge og samme beløb.

## 1. De fire objekter (fulde definitioner)

| # | Tilgang | Fil | Autoritet |
|---|---|---|---|
| 1 | Direkte forespørgsel | `database/postgres/queries/base_revenue.sql` | `payments` (uændret) |
| 2 | SQL-funktion | `database/postgres/migrations/020_reporting_function.sql` | `payments` (uændret) |
| 3 | Materialiseret view | `database/postgres/migrations/022_daily_captured_revenue.sql` | egen lagret kopi, autoritativ kun for sidste `REFRESH` |
| 4 | Trigger-tabel | `database/postgres/migrations/021_daily_revenue_trigger.sql` | egen lagret kopi, vedligeholdt af en **ufuldstændig** `AFTER INSERT`-trigger |

Alle fire regner på samme grundlag:

```sql
select
    r.operator_id,
    p.created_utc::date as revenue_date,
    sum(p.amount)        as captured_amount,
    count(*)             as captured_payments
from payments p
join tickets t on t.id = p.ticket_id
join trips  tr on tr.id = t.trip_id
join routes r  on r.id  = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date;
```

Funktionen (`captured_revenue_for_day`) er en parametriseret indpakning af
præcis denne forespørgsel — se filen for den fulde kode og kommentarer.
Materialiseret view-definitionen og trigger-/tabeldefinitionen er også
fuldt kommenteret direkte i deres migrationsfiler; kommentarerne der
forklarer *hvorfor* hvert designvalg (`with no data`, unikt indeks til
`concurrently`, hvorfor kun `AFTER INSERT` findes) er en del af
besvarelsen og gentages ikke ordret her.

Bemærk: `payments`-tabellen har **ingen** foreign keys og ingen
`unique`-begrænsning på `external_payment_reference` (bevidst, jf.
`011_ticketing_seed.sql`: *"The absence of constraints is intentional for
this lab."*). Det er præcis dette hul, der gør dublet-levering (case 6)
mulig.

## 2. Baseline (før nogen ændringer)

```
-- direkte forespørgsel / funktion (identisk resultat)
 operator_id | revenue_date | captured_amount | captured_payments
-------------+--------------+-----------------+-------------------
 OP-BUS      | 2026-04-29   |           36.00 |                 1
 OP-METRO    | 2026-04-29   |           36.00 |                 1
```

To observationer, der allerede her adskiller tilgangene:

- **Materialiseret view lige efter `create ... with no data`**: et forsøg
  på at læse det giver `ERROR: materialized view "daily_captured_revenue"
  has not been populated`. Viewet er ikke bare "tomt", det er ikke
  scanbart overhovedet, før første `refresh` er kørt. Scriptet fanger
  fejlen kontrolleret og printer:
  `NOTICE: controlled expected error: materialized view "daily_captured_revenue" has not been populated`.
- **Trigger-tabel lige efter `create table daily_revenue_by_operator`**:
  `select * from daily_revenue_by_operator` giver **0 rækker** — selvom
  der allerede findes to 'Captured'-betalinger i seed-dataet
  (`PAYMENT-1`, `PAYMENT-2`). Triggeren reagerer kun på *fremtidige*
  `INSERT`, den bagudretter aldrig eksisterende data. Dette er
  registreret som issue **ISSUE-1** nedenfor.

Efter et manuelt backfill (`truncate` + `insert ... select` fra
autoriteten) og første `refresh materialized view`, er alle fire enige:

```
 operator_id | revenue_date | captured_amount | captured_payments
-------------+--------------+-----------------+-------------------
 OP-BUS      | 2026-04-29   |           36.00 |                 1
 OP-METRO    | 2026-04-29   |           36.00 |                 1
```

## 3. Testcases — output før/efter, alle fire tilgange

Alle beløb er for `OP-METRO, 2026-04-29`, hvor testdataene rammer
(`OP-BUS` ændrer sig aldrig og bruges derfor som kontrolgruppe — den
forbliver `36.00 / 1` gennem hele forløbet i alle fire tilgange, hvilket
i sig selv bekræfter at ingen af testene har utilsigtede sideeffekter på
andre operatører).

| Case | Direkte forespørgsel | Funktion | Materialiseret view (ingen refresh) | Materialiseret view (efter refresh) | Trigger-tabel |
|---|---|---|---|---|---|
| Baseline | 36.00 / 1 | 36.00 / 1 | — | 36.00 / 1 | 36.00 / 1 |
| 1. Captured insert (+36) | **72.00 / 2** | **72.00 / 2** | 36.00 / 1 (stale) | 72.00 / 2 | **72.00 / 2** |
| 2. Failed insert (+50, ignoreres) | 72.00 / 2 (uændret) | 72.00 / 2 (uændret) | 72.00 / 2 (allerede frisk fra case 1-refresh) | 72.00 / 2 (uændret) | 72.00 / 2 (uændret) |
| 3. Failed→Captured (+50) | **122.00 / 3** | **122.00 / 3** | 72.00 / 2 (stale) | 122.00 / 3 | **72.00 / 2 — driver ikke!** |
| 4. Captured→Refunded (−36) | **86.00 / 2** | **86.00 / 2** | 122.00 / 3 (stale) | 86.00 / 2 | **72.00 / 2 — driver stadig ikke!** |
| 5. Delete testdata (−50) | **36.00 / 1** | **36.00 / 1** | 86.00 / 2 (stale) | 36.00 / 1 | **72.00 / 2 — nu 2× galt** |
| 6. Dublet-levering (+36) | **72.00 / 2** | **72.00 / 2** | 36.00 / 1 (stale) | 72.00 / 2 | **108.00 / 3** (36 for meget + samme dublet-fejl) |

Efter case 6 og det efterfølgende spor-eksperiment (se §5) endte
trigger-tabellen på `144.00 / 4`, mens den sande værdi var `72.00 / 2` —
altså **72 DKK og 2 betalinger for meget**, akkumuleret over fire
uafhængige hændelser (case 3's manglende addition, case 4's manglende
subtraktion, case 5's manglende subtraktion, og en efterfølgende sletning
af en sporingsbetaling). Fejlen **kompounderer** — den er ikke "én case
bagud", den bliver værre for hver korrektion, og retningen (over- eller
undertælling) afhænger tilfældigt af hvilken slags korrektion der sker.

## 4. Ét fanget eksempel hvor to tilgange er uenige

Efter case 3 (`Failed` rettet til `Captured`) og et efterfølgende
`refresh materialized view`:

```
-- direkte forespørgsel OG materialiseret view (efter refresh) er enige:
 operator_id | revenue_date | captured_amount | captured_payments
-------------+--------------+-----------------+-------------------
 OP-METRO    | 2026-04-29   |          122.00 |                 3

-- trigger-tabellen (daily_revenue_by_operator) på samme tidspunkt:
 operator_id | revenue_date | captured_amount | captured_payments
-------------+--------------+-----------------+-------------------
 OP-METRO    | 2026-04-29   |           72.00 |                 2
```

To rapporteringskilder, der begge er "opdaterede" og "committede", giver
**forskellige svar til samme spørgsmål på samme tidspunkt** — uden nogen
fejlmeddelelse, lock-konflikt eller advarsel. Årsagen er strukturel, ikke
tilfældig: triggeren har kun en `AFTER INSERT`-gren, så en `UPDATE` af
`payments.status` udløser intet som helst. Denne uenighed forsvinder
aldrig af sig selv — den kan kun rettes med et manuelt rebuild (§6).

## 5. Sideeffekt-spor for én `INSERT INTO payments`

`EXPLAIN ANALYZE` på en enkelt indsættelse (`PAY-TRACE-1`, 36 DKK,
`Captured`) giver den reelle plan:

```
 Insert on payments  (cost=0.00..0.01 rows=0 width=0) (actual time=0.044..0.044 rows=0 loops=1)
   ->  Result  (cost=0.00..0.01 rows=1 width=232) (actual time=0.002..0.002 rows=1 loops=1)
 Planning Time: 0.030 ms
 Trigger payments_daily_revenue_after_insert: time=0.644 calls=1
 Execution Time: 0.710 ms
```

1. **Begrænsninger tjekket**: kun primærnøgle-unikhed på `payments.id`
   (ingen foreign keys, ingen check-constraints er defineret på
   `payments` — bevidst, jf. `011_ticketing_seed.sql`).
2. **Trigger-eksekvering**: `payments_daily_revenue_after_insert` kører
   synkront, som en del af samme statement — planen viser den alene
   tager **0.644 ms af 0.710 ms total (~91 %)**. Selve `INSERT`-raden
   koster næsten intet; hele omkostningen ligger i triggerens
   join (tickets → trips → routes) og upsert.
3. **Skriv til opsummeringstabel**: én `INSERT ... ON CONFLICT DO UPDATE`
   mod `daily_revenue_by_operator`, som tager en rad-lås på nøglen
   `(operator_id, revenue_date)` — det betyder at to samtidige
   `Captured`-indsættelser for samme operatør/dato kan blokere hinanden
   kortvarigt (serialiseres på den låste række), selvom deres kildedata i
   `payments` slet ikke overlapper.
4. **Rækker/lås berørt**: 1 ny række i `payments`; enten 1 ny eller 1
   opdateret række i `daily_revenue_by_operator` (upsert).
5. **Commit/rollback-opførsel**: bekræftet eksperimentelt — en
   `INSERT` i en transaktion, der efterfølgende `ROLLBACK`'es, tager
   trigger-skrivningen med sig:
   ```
   BEGIN; INSERT ...;                         -- OP-METRO midlertidigt 1143.00/5
   ROLLBACK;                                  -- OP-METRO tilbage til 144.00/4
   select count(*) from payments where id='PAY-TRACE-ROLLBACK'; -- 0
   ```
   Triggeren kører i samme transaktion som `INSERT`'en, så begge dele er
   atomare sammen — der er ingen "commit af betalingen, men glemt
   opdatering af rapporten"-tilstand for INSERT-vejen.
6. **Hvornår bliver hver rapport aktuel?**
   - Direkte forespørgsel og funktion: **med det samme** efter commit
     (næste `SELECT` ser den nye tilstand).
   - Trigger-tabel: **med det samme** efter commit, men **kun** for rene
     `INSERT`-hændelser hvor status allerede er `Captured` — se §3/§4 for
     hvor galt det går for alt andet.
   - Materialiseret view: **aldrig automatisk** — først ved næste
     eksplicitte `REFRESH MATERIALIZED VIEW`.
7. **Hvad kan applikationen observere?** En applikation, der læser
   `daily_revenue_by_operator` lige efter at have committed en
   betaling, ser altid det korrekte tal for netop den `INSERT` — men kan
   ikke se, om tabellen *også* mangler tidligere korrektioner. Der er
   intet signal (ingen fejl, intet flag) der fortæller forbrugeren at
   tabellen er drevet væk fra sandheden.

## 6. Genopbygning (rebuild path) — demonstreret, ikke kun påstået

Trigger-tabellen blev bragt tilbage i sync to gange i eksperimentet, med
samme genopbygningstrin:

```sql
truncate table daily_revenue_by_operator;
insert into daily_revenue_by_operator (operator_id, revenue_date, captured_amount, captured_payments)
select r.operator_id, p.created_utc::date, sum(p.amount), count(*)
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date;
```

Før: `144.00 / 4` (forkert). Efter: `72.00 / 2` (matcher den direkte
forespørgsel og det opdaterede materialiserede view). Dette er samtidig
selve rebuild-proceduren for det materialiserede view
(`refresh materialized view daily_captured_revenue`) — begge er
"kassér og genberegn fra `payments`", forskellen er kun at Postgres gør
det for viewet, mens det for trigger-tabellen kræver et manuelt/scheduled
script.

## 7. Ansvarsmatrix

| Kriterie | 1. Direkte forespørgsel | 2. SQL-funktion | 3. Materialiseret view | 4. Trigger-tabel (som udleveret) |
|---|---|---|---|---|
| **Autoritet** | `payments` selv | `payments` selv | egen kopi, kun for tidspunktet for sidste refresh | egen kopi, kun for de INSERT den faktisk har set |
| **Korrekthed** | Afspejler altid de aktuelle basistabeller; forhindrer ikke dobbelttælling, hvis `payments` selv indeholder dubletter | Afspejler altid de aktuelle basistabeller; forhindrer ikke dobbelttælling, hvis `payments` selv indeholder dubletter | Korrekt *for det tidspunkt den blev opdateret*; arver også eventuelle dubletter fra `payments` | Kun korrekt indtil første `UPDATE`/`DELETE` på en relevant `payments`-række; driver derefter permanent og kompounderende (§3–4), og tæller også dublet-inserts med |
| **Friskhed** | Realtid | Realtid | Styret og synlig (kun frisk lige efter `REFRESH`) | Synkron, men kun for insert-vejen — "frisk" er misvisende når den samtidig er strukturelt forkert |
| **Skriveomkostning** | Ingen (intet skrives) | Ingen | Ingen ved kilde-ændring; hele prisen betales samlet ved `REFRESH` (fuld genberegning) | Betales ved **hver** `INSERT` i `payments`, uanset om nogen læser rapporten — §5 viser triggeren står for ~91 % af insert-tiden i den gemte kørsel |
| **Læseomkostning** | Fuld join+aggregat pr. kald | Fuld join+aggregat pr. kald | Indeks-opslag på lagret tabel (meget billigt) | Indeks-opslag på lagret tabel (meget billigt), men på et potentielt forkert tal |
| **Skjulte sideeffekter** | Ingen | Ingen | Ingen ved skrivning; læsere kan ikke se, *hvor* stale viewet er uden at tjekke selv | En `payments`-INSERT kan nu låse/fejle pga. en helt anden tabel (`daily_revenue_by_operator`); fejlen forplanter sig til betalingsflowet |
| **Genopbyggelighed** | Triviel — er altid "genopbygget" | Triviel | Indbygget (`REFRESH MATERIALIZED VIEW`) | Findes ikke i den udleverede migration; kræver et separat, dokumenteret script (§6) |
| **Driftskompleksitet** | Ingen ekstra objekter at drifte | Ét funktions-objekt at versionere | Skal have en refresh-strategi (cron/schedule + evt. `CONCURRENTLY`) | Skal have trigger-dækning for INSERT **og** UPDATE **og** DELETE, plus et rebuild-script, plus overvågning af drift — betydeligt mere at vedligeholde end de andre tre til sammen |

## 8. Anbefaling

**Brug den direkte forespørgsel/funktion som den ene autoritative
kilde til rapportering, og drop den trigger-vedligeholdte tabel i sin
nuværende form.** "Autoritativ" betyder her, at rapporten beregnes fra
`payments`, ikke at den løser alle datakvalitetsproblemer. Hvis
`payments` indeholder to rækker med samme eksterne betalingsreference,
afspejler både direkte forespørgsel og funktion den dublet og tæller den
med. Datamængden i dette scenarie (betalinger pr. operatør
pr. dag) er lille nok til, at join+aggregat-omkostningen ved hvert kald
er ubetydelig sammenlignet med risikoen for stille forkerte tal — og §3–4
viser konkret, at "hurtigere" her betyder "forkert på en måde ingen
opdager".

Det er en hybrid-anbefaling, men med hver lagret kopi som en *bevidst*
undtagelse, ikke som en erstatning for autoriteten:

1. **Autoritet for al rapportering**: funktionen
   `captured_revenue_for_day` (tilgang 2). Den afspejler de samme
   basistabeller som den direkte forespørgsel, men giver ét sted at ændre
   logikken (fx nye statusser eller valutaer) uden at opdatere hver eneste
   rapport.
2. **Materialiseret view (tilgang 3), kun hvis** et dashboard reelt ikke
   kan tåle join-omkostningen ved hvert opslag (fx et
   operatør-vendt dashboard med mange samtidige læsere). Brug den kun
   med en eksplicit, dokumenteret friskheds-kontrakt ("data er højst 5
   minutter gammel, se `refreshed_at`") og `REFRESH ... CONCURRENTLY`
   (indekset er allerede oprettet til det). Rebuild-path er allerede
   indbygget: en ny `REFRESH` retter alt.
3. **Trigger-tabellen (tilgang 4) frarådes i den udleverede form.** Den
   må kun bruges hvis der er et hårdt, målt krav om et
   forespørgselsfrit, synkront tal (fx en betalingsbekræftelse, der skal
   vise "i dag har vi indtjent X" uden en join), OG kun hvis den udvides
   med:
   - `AFTER UPDATE`-trigger, der lægger den nye rækkes bidrag til og
     trækker den gamle fra baseret på statusændringen (delta, ikke kun
     "hvis Captured, adder"),
   - `AFTER DELETE`-trigger, der trækker fra,
   - en unik/idempotent nøgle på `external_payment_reference` (løser
     dublet-problemet ved kilden — se ISSUE-1 nedenfor — for alle fire
     tilgange på én gang, ikke kun for triggeren),
   - og det samme rebuild-script som i §6, kørt på et fast skema (fx
     natligt) som et sikkerhedsnet mod drift, der stadig snyder sig ind.

   Uden alle fire punkter er tabellen strengt taget farligere end ingen
   rapport overhovedet, fordi den ser autoritativ ud uden at være det.

Denne anbefaling er drevet af rapporteringsbelastningen i denne case
(lav skrivefrekvens, moderat læsefrekvens, korrektioner og refunderinger
er en normal del af betalingsflowet) — ikke af en generel præference for
"færre triggere". Havde `payments` haft betydeligt højere
skrive-volumen og rapporten skullet læses tusindvis af gange i sekundet,
ville en **korrekt udvidet** trigger-tabel eller et hyppigt refreshet
view være det rigtige svar; det er stadig ikke tilfældet med den
udleverede, ufuldstændige trigger.

## 9. Issue-register

**ISSUE-1 — `daily_revenue_by_operator` bliver stille forkert ved
korrektioner, refusioner, sletninger og dubletter**

- **Alvorlighed**: Høj (stille datakorruption i en rapporteringskilde
  operatører kan finansielt handle på).
- **Beskrivelse**: `payments_daily_revenue_after_insert` reagerer kun på
  `INSERT` og kun grenen "ny række er allerede `Captured`". Der findes
  ingen `AFTER UPDATE`- eller `AFTER DELETE`-trigger og ingen backfill
  ved oprettelse. Bekræftet i §2–4: tabellen starter tom trods
  eksisterende data, og driver 72 DKK / 2 betalinger forkert efter blot
  fire realistiske korrektioner.
- **Reproduktion**: kør
  `database/postgres/experiments/run_all_cases.sql` mod en frisk database
  og sammenlign case 3–6's output for
  `daily_revenue_by_operator` med den direkte forespørgsel.
- **Foreslået løsning**: se §8, punkt 3 (fuld trigger-dækning +
  idempotent nøgle + planlagt rebuild), eller — anbefalet her — drop
  tabellen til fordel for funktionen/viewet.

## 10. Beslutningsregistrering (decision record)

- **Beslutning**: Daily captured revenue rapporteres via
  `captured_revenue_for_day(operator_id, date)` (funktionen) som
  autoritativ kilde. Et materialiseret view kan tilføjes senere for
  specifikke højtlæste dashboards, med eksplicit refresh-plan. Den
  trigger-vedligeholdte `daily_revenue_by_operator`-tabel bevares **ikke**
  i produktion i sin nuværende form.
- **Kontekst**: `payments` er den eneste autoritet; status kan ændres
  efter oprettelse (refusion, korrektion), og eksterne
  betalingsreferencer kan leveres mere end én gang. Ingen af de fire
  tilgange løser dublet-levering i sig selv (§3, case 6) — det er et
  data-integritetsproblem, ikke et rapporteringsproblem.
- **Alternativer overvejet**:
  - *Udvid triggeren fuldt ud nu* — afvist for nu: øger
    driftskompleksiteten (tre trigger-grene + rebuild-job) for en
    rapport, hvor lav latency ikke er et dokumenteret krav i dette
    scenarie.
  - *Kun det materialiserede view, ingen direkte forespørgsel* — afvist:
    viewet kan ikke være autoritet, fordi det pr. definition kan være
    vilkårligt stale; der skal altid findes en kilde, der er sand *lige
    nu*, til afstemning og fejlretning.
- **Konsekvenser**: Rapporteringslæsninger koster en join+aggregat pr.
  kald, indtil et view eventuelt indføres. Til gengæld er der ingen ekstra
  skriveomkostning på betalingsflowet, ingen ekstra objekter at holde i
  sync, og ingen risiko for at et "opdateret" tal reelt er forkert.
  Beslutningen genvurderes, hvis betalingsvolumen eller læsefrekvens
  ændrer sig markant.

## Bilag: sådan genskabes evidensen

```bash
docker compose down
docker compose up -d
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/020_reporting_function.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/021_daily_revenue_trigger.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/022_daily_captured_revenue.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/experiments/run_all_cases.sql
```

Den gemte evidensfil `docs/evidence-run-output.txt` er lavet med samme
filrækkefølge i en separat midlertidig PostgreSQL-container.
