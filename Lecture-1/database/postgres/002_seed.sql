insert into operators (id, name) values
    ('OP-METRO', 'City Metro'),
    ('OP-BUS', 'City Bus')
on conflict do nothing;

insert into routes (id, operator_id, city_id, mode, short_name) values
    ('LINE-M2', 'OP-METRO', 'CPH', 'metro', 'M2'),
    ('LINE-5C', 'OP-BUS', 'CPH', 'bus', '5C')
on conflict do nothing;

insert into stops (id, city_id, name) values
    ('STOP-NORREPORT', 'CPH', 'Nørreport'),
    ('STOP-KONGENS-NYTORV', 'CPH', 'Kongens Nytorv'),
    ('STOP-AIRPORT', 'CPH', 'Copenhagen Airport'),
    ('STOP-CENTRAL', 'CPH', 'Copenhagen Central Station')
on conflict do nothing;

-- Add route_stops rows after deciding the key.
-- Add at least two trips per route on the same service date.

insert into route_stops (route_id, stop_id, stop_sequence) values
    ('LINE-M2', 'STOP-CENTRAL', 1),
    ('LINE-M2', 'STOP-NORREPORT', 2),
    ('LINE-M2', 'STOP-KONGENS-NYTORV', 3),
    ('LINE-M2', 'STOP-AIRPORT', 4),
    ('LINE-M2', 'STOP-KONGENS-NYTORV', 5),
    ('LINE-M2', 'STOP-NORREPORT', 6),
    ('LINE-M2', 'STOP-CENTRAL', 7),
    ('LINE-5C', 'STOP-CENTRAL', 1),
    ('LINE-5C', 'STOP-NORREPORT', 2),
    ('LINE-5C', 'STOP-KONGENS-NYTORV', 3),
    ('LINE-5C', 'STOP-AIRPORT', 4)
on conflict do nothing;

insert into trips (id, route_id, service_date, scheduled_departure_utc, status) values
    ('Trip-1',  'LINE-M2', '2026-08-28', '2026-08-28 05:00:00+02', 'scheduled'),
    ('Trip-2',  'LINE-M2', '2026-08-28', '2026-08-28 05:15:00+02', 'scheduled'),
    ('Trip-3',  'LINE-M2', '2026-08-28', '2026-08-28 05:30:00+02', 'scheduled'),
    ('Trip-4',  'LINE-M2', '2026-08-28', '2026-08-28 05:45:00+02', 'scheduled'),
    ('Trip-5',  'LINE-M2', '2026-08-28', '2026-08-28 06:00:00+02', 'scheduled'),
    ('Trip-6',  'LINE-M2', '2026-08-28', '2026-08-28 06:15:00+02', 'scheduled'),
    ('Trip-7',  'LINE-M2', '2026-08-28', '2026-08-28 06:30:00+02', 'scheduled'),
    ('Trip-8',  'LINE-M2', '2026-08-28', '2026-08-28 06:45:00+02', 'scheduled'),
    ('Trip-9',  'LINE-M2', '2026-08-28', '2026-08-28 07:00:00+02', 'scheduled'),
    ('Trip-10', 'LINE-M2', '2026-08-28', '2026-08-28 07:15:00+02', 'scheduled'),
    ('Trip-11', 'LINE-M2', '2026-08-28', '2026-08-28 07:30:00+02', 'scheduled'),
    ('Trip-12', 'LINE-M2', '2026-08-28', '2026-08-28 07:45:00+02', 'scheduled'),
    ('Trip-13', 'LINE-M2', '2026-08-28', '2026-08-28 08:00:00+02', 'scheduled'),
    ('Trip-14', 'LINE-M2', '2026-08-28', '2026-08-28 08:15:00+02', 'scheduled'),
    ('Trip-15', 'LINE-M2', '2026-08-28', '2026-08-28 08:30:00+02', 'scheduled'),
    ('Trip-16', 'LINE-M2', '2026-08-28', '2026-08-28 08:45:00+02', 'scheduled'),
    ('Trip-17', 'LINE-M2', '2026-08-28', '2026-08-28 09:00:00+02', 'scheduled'),
    ('Trip-18', 'LINE-M2', '2026-08-28', '2026-08-28 09:15:00+02', 'scheduled'),
    ('Trip-19', 'LINE-M2', '2026-08-28', '2026-08-28 09:30:00+02', 'scheduled'),
    ('Trip-20', 'LINE-M2', '2026-08-28', '2026-08-28 09:45:00+02', 'scheduled'),
    ('Trip-21', 'LINE-5C', '2026-08-28', '2026-08-28 06:00:00+02', 'scheduled'),
    ('Trip-22', 'LINE-5C', '2026-08-28', '2026-08-28 06:30:00+02', 'scheduled'),
    ('Trip-23', 'LINE-5C', '2026-08-28', '2026-08-28 07:00:00+02', 'scheduled'),
    ('Trip-24', 'LINE-5C', '2026-08-28', '2026-08-28 07:30:00+02', 'scheduled'),
    ('Trip-25', 'LINE-5C', '2026-08-28', '2026-08-28 08:00:00+02', 'scheduled')
on conflict do nothing;