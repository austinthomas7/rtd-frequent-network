-- =====================================================================
-- 02_pick_service_day.sql
-- Purpose: decide which single day to analyze, and set the analysis
--          parameters (time-of-day periods, what counts as "frequent").
-- Method:  a GTFS feed covers months of service. We expand it into one
--          row per date, apply the weekly calendar plus the exceptions,
--          and pick the Wednesday with the most scheduled trips (a
--          typical weekday that is not a holiday).
-- =====================================================================

-- Every date the feed covers ---------------------------------------------
CREATE OR REPLACE TABLE feed_dates AS
WITH bounds AS (
    SELECT min(d0) AS d0, max(d1) AS d1
    FROM (
        SELECT start_date AS d0, end_date AS d1 FROM calendar_c
        UNION ALL
        SELECT service_date, service_date FROM calendar_dates_c
    ) AS all_ranges
)
SELECT CAST(unnest(generate_series(d0, d1, INTERVAL 1 DAY)) AS DATE) AS service_date
FROM bounds;

-- Which service_ids run on which dates --------------------------------------
-- isodow(): 1 = Monday ... 7 = Sunday, so it indexes the weekday list directly.
CREATE OR REPLACE TABLE active_services AS
(
    SELECT f.service_date, c.service_id
    FROM feed_dates AS f
    JOIN calendar_c AS c
      ON f.service_date BETWEEN c.start_date AND c.end_date
     AND list_extract(
            [c.monday, c.tuesday, c.wednesday, c.thursday, c.friday, c.saturday, c.sunday],
            isodow(f.service_date)
         ) = 1
    UNION
    SELECT service_date, service_id
    FROM calendar_dates_c
    WHERE exception_type = 1
)
EXCEPT
SELECT service_date, service_id
FROM calendar_dates_c
WHERE exception_type = 2;

-- Analysis parameters ---------------------------------------------------------
-- To force a specific date, replace the subquery with:  SELECT DATE '2026-10-07' AS service_date
CREATE OR REPLACE TABLE params AS
SELECT
    service_date,
    15        AS frequent_headway_min,  -- "frequent" = median headway of 15 min or less
    0.5       AS headway_percentile,    -- documented here; the SQL uses median()
    4         AS min_trips_frequent,    -- a route-direction needs 4+ trips in the period
                                        -- (an hour of service at 15 min) to count as
                                        -- frequent, so 2 buses a few minutes apart
                                        -- (e.g. a school tripper) don't qualify.
                                        -- Set to 2 to turn this off.
    3 * 3600  AS day_start_sec          -- 3:00 AM. Departures before this are the tail of
                                        -- the previous night, so they are shifted +24 h
                                        -- and counted in Late Night (see sql/03).
FROM (
    SELECT a.service_date, count(*) AS n_trips
    FROM active_services AS a
    JOIN trips_c AS t USING (service_id)
    WHERE isodow(a.service_date) = 3          -- Wednesdays only
    GROUP BY a.service_date
    ORDER BY n_trips DESC, a.service_date
    LIMIT 1
) AS busiest_wednesday;

-- Time-of-day periods -----------------------------------------------------------
-- Seconds after midnight of the service day. GTFS lets times run past 24:00,
-- so Late Night ends at 27:00 (3:00 AM the next morning).
CREATE OR REPLACE TABLE periods AS
SELECT * FROM (VALUES
    (1, 'AM Peak',     6 * 3600,  9 * 3600),   --  6:00 AM to  9:00 AM
    (2, 'Mid-Day',     9 * 3600, 15 * 3600),   --  9:00 AM to  3:00 PM
    (3, 'PM Peak',    15 * 3600, 19 * 3600),   --  3:00 PM to  7:00 PM
    (4, 'Late Night', 19 * 3600, 27 * 3600)    --  7:00 PM to  3:00 AM
) AS t(period_order, period, start_sec, end_sec);

-- Trips that actually run on the analysis day -----------------------------------
CREATE OR REPLACE TABLE day_trips AS
SELECT t.*
FROM trips_c AS t
JOIN active_services AS a USING (service_id)
JOIN params AS p ON a.service_date = p.service_date;
