-- =====================================================================
-- 04_stop_frequency.sql
-- Question: which stops get frequent service in each period of the day?
-- Definition: a stop is "frequent" in a period if at least one
--             route-direction serving it has a median headway of
--             15 minutes or less AT THAT STOP, with at least 4
--             departures there in the period (params.min_trips_frequent). (Stacking several
--             infrequent routes does NOT count; riders can't combine
--             them into one wait.)
-- Method:     the same successive-departure logic as sql/03, but at
--             every stop instead of only each route's busiest stop, so a
--             trip that passes a stop at 6:20 counts as AM Peak there
--             even if it started its run at 5:55.
-- =====================================================================

-- stop_departures (every departure at every stop) is built in sql/03.

-- Headways at each stop, between successive trips in the same period ----
-- Same rule as sql/03: both trips must leave the stop inside the period.
CREATE OR REPLACE TABLE stop_route_headways AS
WITH by_period AS (
    SELECT d.stop_id, d.route_id, d.direction_id, p.period_order, p.period, d.dep_sec
    FROM stop_departures AS d
    JOIN periods AS p
      ON d.dep_sec >= p.start_sec
     AND d.dep_sec <  p.end_sec
),
ordered AS (
    SELECT
        *,
        LAG(dep_sec) OVER (
            PARTITION BY stop_id, route_id, direction_id, period
            ORDER BY dep_sec
        ) AS prev_sec
    FROM by_period
)
SELECT
    stop_id,
    route_id,
    direction_id,
    period_order,
    period,
    count(*)                                                AS n_departures,
    -- NULL when the route-direction leaves this stop only once in the period
    round(median((dep_sec - prev_sec) / 60.0), 1)           AS median_headway_min,
    round(quantile_cont((dep_sec - prev_sec) / 60.0, 0.85), 1) AS p85_headway_min
FROM ordered
GROUP BY stop_id, route_id, direction_id, period_order, period;

-- One row per stop and period ---------------------------------------------
-- Every stop served on the analysis day appears in all four periods, so a
-- stop with no service in a period shows up as not frequent (not missing).
CREATE OR REPLACE TABLE stop_frequency AS
WITH served_stops AS (
    SELECT DISTINCT stop_id FROM stop_departures
),
best_route AS (
    SELECT
        s.stop_id,
        s.period,
        count(DISTINCT s.route_id) AS routes_in_period,
        sum(s.n_departures)        AS all_route_departures,
        -- best single route-direction with enough trips to count
        -- (see params.min_trips_frequent in sql/02)
        min(s.median_headway_min) FILTER (WHERE s.n_departures >= p.min_trips_frequent)
                                   AS best_median_headway_min
    FROM stop_route_headways AS s
    CROSS JOIN params AS p
    GROUP BY s.stop_id, s.period
)
SELECT
    s.stop_id,
    s.stop_name,
    s.stop_lat,
    s.stop_lon,
    pr.period_order,
    pr.period,
    COALESCE(b.routes_in_period, 0)      AS routes_in_period,
    COALESCE(b.all_route_departures, 0)  AS all_route_departures,
    b.best_median_headway_min,
    COALESCE(b.best_median_headway_min <= p.frequent_headway_min, FALSE) AS is_frequent
FROM served_stops AS ss
JOIN stops_c AS s USING (stop_id)
CROSS JOIN periods AS pr
CROSS JOIN params  AS p
LEFT JOIN best_route AS b
  ON b.stop_id = ss.stop_id
 AND b.period  = pr.period
ORDER BY s.stop_id, pr.period_order;
