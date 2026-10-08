-- =====================================================================
-- 03_route_headways.sql
-- Question: how often does each route run in each period of the day
--           (AM Peak, Mid-Day, PM Peak, Late Night)?
-- Method:   1. list every departure at every stop on the analysis day
--           2. for each route and direction, pick the stop it serves most
--              often and take each trip's departure time there
--           3. headway = time between successive trips of the same
--              route and direction, found with the LAG() window function
--           4. for each route, direction, and period, summarise those
--              headways as the minimum, maximum, median, and 85th percentile
--           5. a route is "frequent" in a period if its MEDIAN headway is
--              15 minutes or less in every direction it runs. The median
--              is the typical scheduled gap: half the gaps are shorter and
--              half are longer, so one odd gap (a service change, an extra
--              trip) doesn't decide the result.
-- Edges:    only gaps between two successive trips that BOTH leave inside
--           the period count. A gap that straddles two periods (8:55 ->
--           9:10) counts in neither, and there is no gap from the period
--           start to the first trip or from the last trip to the period
--           end (or to 3 AM). A route-direction needs at least 4 trips
--           in the period to count as frequent (params.min_trips_frequent). Departures between
--           3 and 6 AM fall outside the four periods and are not used.
-- =====================================================================

-- Every departure at every stop on the analysis day ----------------------
-- The last stop of a trip is drop-off only, so it is not a departure.
-- Departures before 3:00 AM are the end of the previous night's service,
-- so they are moved +24 h to sit after the 11 PM-midnight trips.
-- DISTINCT drops departures at the exact same second on the same route and
-- direction: two buses at once don't shorten anyone's wait.
CREATE OR REPLACE TABLE stop_departures AS
WITH last_stop AS (
    SELECT trip_id, max(stop_sequence) AS last_seq
    FROM stop_times_c
    GROUP BY trip_id
)
SELECT DISTINCT
    st.stop_id,
    t.route_id,
    t.direction_id,
    CASE WHEN st.dep_sec < p.day_start_sec THEN st.dep_sec + 86400 ELSE st.dep_sec END AS dep_sec
FROM stop_times_c AS st
JOIN day_trips    AS t  USING (trip_id)
JOIN last_stop    AS ls USING (trip_id)
CROSS JOIN params AS p
WHERE st.stop_sequence < ls.last_seq;

-- Where to measure each route ----------------------------------------------
-- Measuring at each trip's FIRST stop is misleading when some trips start
-- partway along the route (short turns): their start times interleave with
-- full-length trips and create fake 1-minute and 30-minute gaps. Instead,
-- each route-direction is measured at the stop it serves most often.
CREATE OR REPLACE TABLE route_ref_stop AS
SELECT route_id, direction_id, stop_id, count(*) AS n_departures
FROM stop_departures
GROUP BY route_id, direction_id, stop_id
QUALIFY row_number() OVER (
    PARTITION BY route_id, direction_id
    ORDER BY count(*) DESC, stop_id
) = 1;

CREATE OR REPLACE TABLE route_departures AS
SELECT d.route_id, d.direction_id, d.dep_sec
FROM stop_departures AS d
JOIN route_ref_stop  AS r USING (route_id, direction_id, stop_id);

-- Every departure at the reference stop, tagged with its period ---------
-- A departure at exactly 9:00 belongs to Mid-Day, not AM Peak.
CREATE OR REPLACE TABLE route_departures_by_period AS
SELECT d.route_id, d.direction_id, p.period_order, p.period, d.dep_sec
FROM route_departures AS d
JOIN periods AS p
  ON d.dep_sec >= p.start_sec
 AND d.dep_sec <  p.end_sec;

-- Every headway between successive trips in the same period -------------
-- Partitioning LAG() by period as well means the first trip in each period
-- has no previous trip, so no gap ever crosses a period boundary.
CREATE OR REPLACE TABLE route_direction_gaps AS
WITH ordered AS (
    SELECT
        route_id,
        direction_id,
        period_order,
        period,
        dep_sec,
        LAG(dep_sec) OVER (
            PARTITION BY route_id, direction_id, period
            ORDER BY dep_sec
        ) AS prev_sec                    -- NULL for the first trip in the period
    FROM route_departures_by_period
)
SELECT
    route_id,
    direction_id,
    period_order,
    period,
    (dep_sec - prev_sec) / 60.0 AS headway_min
FROM ordered
WHERE prev_sec IS NOT NULL;

-- Route x direction x period summary ------------------------------------
-- Every route-direction with at least one trip in the period is kept. With
-- only one trip there is no gap, so the headway columns are NULL.
CREATE OR REPLACE TABLE route_direction_headways AS
WITH trips_in_period AS (
    SELECT route_id, direction_id, period_order, period, count(*) AS n_trips
    FROM route_departures_by_period
    GROUP BY route_id, direction_id, period_order, period
),
gap_stats AS (
    SELECT
        route_id,
        direction_id,
        period,
        round(min(headway_min), 1)                AS min_headway_min,
        round(max(headway_min), 1)                AS max_headway_min,
        round(median(headway_min), 1)             AS median_headway_min,
        round(quantile_cont(headway_min, 0.85), 1) AS p85_headway_min   -- kept for reference
    FROM route_direction_gaps
    GROUP BY route_id, direction_id, period
)
SELECT
    n.route_id,
    n.direction_id,
    n.period_order,
    n.period,
    n.n_trips,
    g.min_headway_min,
    g.max_headway_min,
    g.median_headway_min,
    g.p85_headway_min
FROM trips_in_period AS n
LEFT JOIN gap_stats AS g USING (route_id, direction_id, period);

-- One row per route and period: report the weaker direction, so
-- "frequent" means frequent both ways. ----------------------------------
CREATE OR REPLACE TABLE route_headways AS
SELECT
    r.route_id,
    r.route_short_name,
    r.route_long_name,
    r.mode,
    h.period_order,
    h.period,
    sum(h.n_trips)              AS trips_both_dirs,
    min(h.min_headway_min)      AS min_headway_min,
    max(h.max_headway_min)      AS max_headway_min,
    max(h.median_headway_min)   AS median_headway_min,   -- weaker direction
    max(h.p85_headway_min)      AS p85_headway_min,      -- reference only
    -- frequent = in every direction, the median headway is 15 minutes or
    -- less and there are at least min_trips_frequent trips in the period.
    -- (max() skips NULLs, so a direction with one trip and no headway is
    -- caught by the trip-count check.)
    min(h.n_trips) >= any_value(p.min_trips_frequent)
      AND COALESCE(max(h.median_headway_min) <= any_value(p.frequent_headway_min), FALSE) AS is_frequent
FROM route_direction_headways AS h
JOIN routes_c AS r USING (route_id)
CROSS JOIN params AS p
GROUP BY r.route_id, r.route_short_name, r.route_long_name, r.mode, h.period_order, h.period
ORDER BY h.period_order, median_headway_min;
