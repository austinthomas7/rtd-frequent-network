-- =====================================================================
-- 05_headline_metrics.sql
-- Purpose: the numbers that go on the resume and in the README.
--          One row per time-of-day period.
-- Note:    pct_stops_frequent uses every stop served at any point on the
--          analysis day as the denominator, so the four periods are
--          directly comparable.
-- =====================================================================

CREATE OR REPLACE TABLE headline_metrics AS
WITH day_totals AS (
    SELECT
        (SELECT count(DISTINCT route_id) FROM day_trips)          AS routes_all_day,
        (SELECT count(DISTINCT stop_id)  FROM stop_frequency)     AS stops_served_all_day
),
route_stats AS (
    SELECT
        period,
        count(*)                             AS routes_running,
        count(*) FILTER (WHERE is_frequent)  AS routes_frequent,
        -- system median headway: each route's median gap in the period
        -- (weaker direction), then the median across all routes running.
        -- Every route counts once, however often it runs. Routes with a
        -- single trip in the period have no headway and are left out.
        round(median(median_headway_min), 1) AS system_median_headway_min
    FROM route_headways
    GROUP BY period
),
stop_stats AS (
    SELECT
        period,
        count(*) FILTER (WHERE routes_in_period > 0) AS stops_served,
        count(*) FILTER (WHERE is_frequent)          AS stops_frequent
    FROM stop_frequency
    GROUP BY period
)
SELECT
    p.period_order,
    p.period,
    (SELECT service_date FROM params)                       AS service_date,
    d.routes_all_day,
    COALESCE(r.routes_running, 0)                           AS routes_running,
    COALESCE(r.routes_frequent, 0)                          AS routes_frequent,
    d.stops_served_all_day,
    COALESCE(s.stops_served, 0)                             AS stops_served,
    COALESCE(s.stops_frequent, 0)                           AS stops_frequent,
    round(100.0 * COALESCE(s.stops_frequent, 0) / d.stops_served_all_day, 1) AS pct_stops_frequent,
    r.system_median_headway_min
FROM periods AS p
CROSS JOIN day_totals AS d
LEFT JOIN route_stats AS r USING (period)
LEFT JOIN stop_stats  AS s USING (period)
ORDER BY p.period_order;
