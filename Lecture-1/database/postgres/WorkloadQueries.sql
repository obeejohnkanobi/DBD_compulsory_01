-- Query 1. Show the next 20 scheduled trips for a route after a supplied timestamp.
SELECT
    t.id,
    t.scheduled_departure_utc,
    t.status
FROM trips t
WHERE t.route_id = :route_id
  AND t.scheduled_departure_utc >= :after_utc
ORDER BY t.scheduled_departure_utc
    LIMIT 20;

-- Query 2. Show the ordered stops belonging to a route.
SELECT
    rs.route_id, rs.stop_id,
    city_id, name
FROM route_stops rs
         INNER JOIN stops s on s.id = rs.stop_id
WHERE rs.route_id = :route_id
ORDER BY rs.stop_sequence;

-- Query 3. Show all routes and the number of scheduled trips on a supplied service date, including routes with no trips.
SELECT
    r.id, r.short_name, r.mode,
    COUNT(t.id) AS scheduled_trip_count
FROM routes r
         LEFT JOIN trips t on t.route_id = r.id AND t.service_date = :service_date
GROUP BY r.id, r.short_name, r.mode
ORDER BY r.id;
