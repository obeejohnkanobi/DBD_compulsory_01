begin;

alter table tickets
  drop column product_code;

alter table tickets
  add column product_id uuid not null;

commit;
