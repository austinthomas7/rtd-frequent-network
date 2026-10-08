-- =====================================================================
-- 06_headway_diagnostics.sql
-- Question: GTFS is a schedule, so why do some routes show a wide range
--           of headways within one period (e.g. 4 to 15 minutes), and
--           headways that are not "clock-face" numbers like 10 or 15?
-- Method:   1. list every trip at each route-direction's reference stop
--              (the same stop sql/03 measures at), with the trip's
--              starting stop and time, headsign, and shape
--           2. pair each trip with the one before it and label the gap:
--              which period it sits in, the nearest standard headway, and
--              how far it is from that standard
--           3. give each gap one explanation, testing the usual scheduling
--              reasons in order (see the CASE in route_gap_detail):
--              standard value, within 1 min of one (rounding, estimated
--              stop times, running time), an extra trip, a change in
--              service level, a different starting point, a change in
--              running time, or uneven departures at the start of the route
-- Outputs:  route_gap_detail      one row per gap between consecutive trips
--           route_period_pattern  one row per route, direction, and period
-- Note:     these tables only explain the numbers in sql/03. They do not
--           change which routes or stops count as frequent. Gaps that
--           cross a period boundary are kept here, labelled, so you can
--           see what sql/03 leaves out; sql/03 uses only the gaps wholly
--           inside one period.
-- =====================================================================

-- Standard ("clock-face") headways ---------------------------------------
-- Values that repeat evenly within an hour or three hours, so a rider sees the
-- same minutes past the hour all period. 7.5 min (8 trips an hour) has to
-- be written in whole minutes, so schedules alternate 7 and 8 (8 alone
-- does not fit an hourly cycle, so it is not on the list).
CREATE OR REPLACE TABLE standard_headways AS
SELECT * FROM (VALUES (3.0), (4.0), (5.0), (6.0), (7.5), (10.0), (12.0),
                      (15.0), (20.0), (30.0), (45.0), (60.0), (90.0)) AS t(standard_min);

-- Every trip at the reference stop, with where and when it started -------
CREATE OR REPLACE TABLE ref_stop_trips AS
WITH trip_ends AS (
    SELECT trip_id, min(stop_sequence) AS first_seq, max(stop_sequence) AS last_seq
    FROM stop_times_c
    GROUP BY trip_id
),
trip_origin AS (
    SELECT st.trip_id, st.stop_id AS origin_stop_id, st.dep_sec AS origin_dep_sec
    FROM stop_times_c AS st
    JOIN trip_ends AS e
      ON st.trip_id = e.trip_id
     AND st.stop_sequence = e.first_seq
),
at_ref AS (
    SELECT
        t.route_id,
        t.direction_id,
        st.trip_id,
        t.trip_headsign,
        t.shape_id,
        st.timepoint,
        o.origin_stop_id,
        -- same +24 h shift as sql/03 for trips after midnight
        CASE WHEN st.dep_sec < p.day_start_sec THEN st.dep_sec + 86400 ELSE st.dep_sec END AS dep_sec,
        CASE WHEN o.origin_dep_sec < p.day_start_sec THEN o.origin_dep_sec + 86400 ELSE o.origin_dep_sec END AS origin_dep_sec
    FROM stop_times_c    AS st
    JOIN day_trips       AS t  USING (trip_id)
    JOIN trip_ends       AS e  USING (trip_id)
    JOIN trip_origin     AS o  USING (trip_id)
    JOIN route_ref_stop  AS r
      ON r.route_id = t.route_id
     AND r.direction_id = t.direction_id
     AND r.stop_id = st.stop_id
    CROSS JOIN params    AS p
    WHERE st.stop_sequence < e.last_seq
)
-- one trip per departure second, matching the DISTINCT in sql/03
SELECT *
FROM at_ref
QUALIFY row_number() OVER (PARTITION BY route_id, direction_id, dep_sec ORDER BY trip_id) = 1;

-- Each gap between consecutive trips, with its neighbours -------------------
CREATE OR REPLACE TABLE route_gap_detail AS
WITH paired AS (
    SELECT
        route_id,
        direction_id,
        LAG(trip_id)        OVER w AS prev_trip_id,
        trip_id,
        LAG(dep_sec)        OVER w AS prev_dep_sec,
        dep_sec,
        LAG(origin_stop_id) OVER w AS prev_origin_stop_id,
        origin_stop_id,
        LAG(origin_dep_sec) OVER w AS prev_origin_dep_sec,
        origin_dep_sec,
        LAG(trip_headsign)  OVER w AS prev_headsign,
        trip_headsign,
        LAG(shape_id)       OVER w AS prev_shape_id,
        shape_id,
        LAG(timepoint)      OVER w AS prev_timepoint,
        timepoint
    FROM ref_stop_trips
    WINDOW w AS (PARTITION BY route_id, direction_id ORDER BY dep_sec)
),
gaps AS (
    SELECT
        *,
        (dep_sec - prev_dep_sec) / 60.0 AS headway_min,
        -- gap between the same two trips where they started their runs
        (origin_dep_sec - prev_origin_dep_sec) / 60.0 AS origin_headway_min,
        -- scheduled minutes from each trip's start to the reference stop
        (prev_dep_sec - prev_origin_dep_sec) / 60.0 AS prev_running_min,
        (dep_sec - origin_dep_sec) / 60.0           AS running_min
    FROM paired
    WHERE prev_dep_sec IS NOT NULL
),
with_neighbours AS (
    SELECT
        *,
        LAG(headway_min, 2)  OVER w AS headway_2_before,
        LAG(headway_min)     OVER w AS headway_before,
        LEAD(headway_min)    OVER w AS headway_after,
        LEAD(headway_min, 2) OVER w AS headway_2_after
    FROM gaps
    WINDOW w AS (PARTITION BY route_id, direction_id ORDER BY dep_sec)
),
-- nearest standard value for this gap, its neighbours, and its origin gap
nearest AS (
    SELECT
        g.route_id, g.direction_id, g.dep_sec,
        arg_min(s.standard_min, abs(s.standard_min - g.headway_min))                   AS nearest_standard_min,
        arg_min(s.standard_min, abs(s.standard_min - g.headway_before))                AS level_before,
        arg_min(s.standard_min, abs(s.standard_min - g.headway_after))                 AS level_after,
        arg_min(s.standard_min, abs(s.standard_min - g.headway_2_before))              AS level_2_before,
        arg_min(s.standard_min, abs(s.standard_min - g.headway_2_after))               AS level_2_after
    FROM with_neighbours AS g
    CROSS JOIN standard_headways AS s
    GROUP BY g.route_id, g.direction_id, g.dep_sec
),
labelled AS (
    SELECT
        g.*,
        n.nearest_standard_min,
        round(g.headway_min - n.nearest_standard_min, 1) AS deviation_min,
        n.level_before, n.level_after, n.level_2_before, n.level_2_after,
        COALESCE(g.origin_stop_id = g.prev_origin_stop_id, FALSE) AS same_origin,
        COALESCE(g.timepoint = 0 OR g.prev_timepoint = 0, FALSE)  AS interpolated_time,
        -- which period holds the whole gap, or which boundary it crosses
        (SELECT p.period FROM periods AS p
          WHERE g.prev_dep_sec >= p.start_sec AND g.dep_sec < p.end_sec)  AS period,
        (SELECT p.period FROM periods AS p
          WHERE g.dep_sec >= p.start_sec AND g.dep_sec < p.end_sec)        AS end_period
    FROM with_neighbours AS g
    JOIN nearest AS n USING (route_id, direction_id, dep_sec)
)
SELECT
    route_id,
    direction_id,
    CASE
        WHEN period IS NOT NULL     THEN period
        WHEN end_period IS NOT NULL THEN 'Crosses into ' || end_period
        ELSE 'Before 6 AM (outside the four periods)'
    END AS period,
    period IS NULL AS crosses_period_boundary,   -- TRUE unless wholly inside one period
    prev_trip_id,
    trip_id,
    prev_dep_sec,
    dep_sec,
    printf('%02d:%02d', (dep_sec // 3600) % 24, (dep_sec % 3600) // 60) AS dep_time,
    round(headway_min, 1)          AS headway_min,
    nearest_standard_min,
    deviation_min,
    abs(deviation_min) <= 1.0      AS near_standard,
    round(headway_before, 1)       AS headway_before,
    round(headway_after, 1)        AS headway_after,
    round(origin_headway_min, 1)   AS origin_headway_min,
    round(prev_running_min, 1)     AS prev_running_min,
    round(running_min, 1)          AS running_min,
    same_origin,
    interpolated_time,
    prev_headsign,
    trip_headsign,
    CASE
        WHEN headway_min = nearest_standard_min
            THEN 'Standard headway'
        WHEN abs(deviation_min) <= 1.0 AND interpolated_time
            THEN 'Within 1 min of standard: interpolated stop time'
        WHEN abs(deviation_min) <= 1.0 AND same_origin AND abs(running_min - prev_running_min) >= 0.5
            THEN 'Within 1 min of standard: running time changed'
        WHEN abs(deviation_min) <= 1.0
            THEN 'Within 1 min of standard: minute rounding'
        -- a short gap plus a neighbouring gap add up to the regular headway,
        -- and the regular headway resumes afterwards: one trip was added
        WHEN (abs(headway_min + headway_after  - level_before) <= 1.0 AND level_2_after  = level_before)
          OR (abs(headway_min + headway_before - level_after)  <= 1.0 AND level_2_before = level_after)
            THEN 'Extra trip added between regular trips'
        -- the regular headway is different before and after this gap
        WHEN level_before IS NOT NULL AND level_after IS NOT NULL AND level_before <> level_after
            THEN 'Transition between service levels'
        WHEN headway_before IS NULL OR headway_after IS NULL
            THEN 'First or last trips of the day'
        WHEN NOT same_origin
            THEN 'Trips start at different places (variant, short turn or pull-out)'
        -- both trips start at the same place. The gap at the reference stop
        -- = gap at the start + change in scheduled running time. Whichever
        -- part is bigger is the main reason the gap is off the pattern.
        WHEN abs(running_min - prev_running_min) >= abs(origin_headway_min - level_before)
            THEN 'Running time changed between trips'
        ELSE 'Uneven departures from the start of the route'
    END AS explanation
FROM labelled
ORDER BY route_id, direction_id, dep_sec;

-- Route x direction x period summary -----------------------------------------
-- Only gaps that start and end inside the period, so the range here is
-- what the schedule does, not an edge effect of how periods are cut.
CREATE OR REPLACE TABLE route_period_pattern AS
SELECT
    g.route_id,
    r.route_short_name,
    g.direction_id,
    p.period_order,
    g.period,
    count(*)                                              AS n_gaps,
    round(min(g.headway_min), 1)                          AS min_inside_headway_min,
    round(max(g.headway_min), 1)                          AS max_inside_headway_min,
    round(median(g.headway_min), 1)                       AS median_inside_headway_min,
    mode(g.nearest_standard_min)                          AS typical_standard_min,
    round(100.0 * avg(CASE WHEN g.near_standard THEN 1 ELSE 0 END), 1) AS pct_near_standard,
    array_to_string(list_sort(list_distinct(list(g.nearest_standard_min))), ', ') AS standards_used,
    count(*) FILTER (WHERE NOT g.near_standard)           AS n_off_standard
FROM route_gap_detail AS g
JOIN periods  AS p ON p.period = g.period
JOIN routes_c AS r USING (route_id)
GROUP BY g.route_id, r.route_short_name, g.direction_id, p.period_order, g.period
ORDER BY g.route_id, g.direction_id, p.period_order;
