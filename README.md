# Compulsory Assignment 1 review guide

## Setup and reset instructions:
- Lecture 1: [Start the database](Lecture-1/README.md#start-the-database)
- Lecture 2: [Start the database](Lecture-2/README.md#start-the-database)
- Lecture 3: [Start the database](opg-3/README.md#Start-the-database)
- Lecture 4: [Start the database](opg-4/README.md#Start-the-database)

## Where to find the work
- Lecture 1: model, workload map and queries: [Lecture-1](Lecture-1/)
- Lecture 2: constraints and tests: [Lecture-2](Lecture-2/)
- Lecture 3: reporting experiment and comparison: [Lecture-3](opg-3/)
- Lecture 4: migration stages and verification: [Lecture-4](opg-4/)

## Two decisions worth discussing
**Lecture 1:**

**What did we choose?**

Vi valgte at gøre sådan at en bus/metro kan have flere af de samme stop på en route.

**What was the alternative?**

En route kunne kun ikke have flere af de samme stop.

**Why does our choice fit MobilityTicketing?**

Grundet til at vi valgte at gå med den her løsning var fordi vi tænkte at, ude i den virkelige verden kører metroer igennem de samme stop flere gange på en route og at busser os godt kan ende ud i at gøre det. Så vores valg reflekterede den virkelige verden.

**Which file or result supports it?**

- [001_relational_baseline.sql](Lecture-1/database/postgres/001_relational_baseline.sql)
- [002_seed.sql](Lecture-1/database/postgres/002_seed.sql)

**Lecture 4:**

**What did we choose?**

Vi migrerede fra product_code til et stabilt product_id med en trinvis expand-and-contract migration.

**What was the alternative?**

Alternativet var at fjerne product_code og med det samme erstatte med product_id.

**Why does our choice fit MobilityTicketing?**

Vi valgte den trinvise løsning, da tickets og gammel applikations kode, skulle fungere, mens den nye løsning blev indført.

Vi startede med at tilføje product_id, bagefter backfill af eksisterende tickets og validerede relationer. derefter kunne den gamle product_code reference fjernes.
Vi ændrede database schemaet uden at kræve, at alle dele af systemet blev opdateret på samme tidspunkt.
Et stabilt product_id passer bedre som identity, da product_code kan ændres, uden at produktets identity skal ændres.

**Which file or result supports it?**
- [bad_migration.sql](opg-4/database/postgres/experiments/lecture04/bad_migration.sql)
- [030_expand_product_identity.sql](opg-4/database/postgres/migrations/030_expand_product_identity.sql)
- [031_backfill_ticket_product.sql](opg-4/database/postgres/migrations/031_backfill_ticket_product.sql)
- [032_require_ticket_product_id.sql](opg-4/database/postgres/migrations/032_require_ticket_product_id.sql)
- [034_drop_ticket_product_code.sql](opg-4/database/postgres/migrations/034_drop_ticket_product_code.sql)


## One limitation or open question

**What does our implementation not guarantee?**

Vores migration garanterer ikke at alle gamle application instances er stoppet, før product_id bliver gjort obligatorisk eller product_code bliver fjernet.
En gammel writer, der kun skriver product_code, vil fejle, når databasen kræver product_id.

**Point to the relevant evidence**

- [old_writer.sql](opg-4/database/postgres/experiments/lecture04/old_writer.sql)
- [032_require_ticket_product_id.sql](opg-4/database/postgres/migrations/032_require_ticket_product_id.sql)

**State what we would check next**
Vi ville kontrollere, om alle gamle writers er udfaset, derefter køre den sidste backfill og verificere, at alle tickets har et gyldigt product_id, før den gamle reference fjernes.


