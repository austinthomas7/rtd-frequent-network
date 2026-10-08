-- =====================================================================
-- 01_clean_tables.sql
-- Purpose: turn the raw GTFS text tables (loaded as all-text columns)
--          into typed, analysis-ready tables.
-- Why:     GTFS times can run past midnight ("25:10:00"), so they can't
--          be stored as a normal TIME. We convert them to seconds after
--          midnight of the service day instead.
-- =====================================================================

-- Routes, with a readable mode label -----------------------------------
CREATE OR REPLACE TABLE routes_c AS
SELECT
    route_id,
    route_short_name,
    route_long_name,
    CAST(route_type AS INTEGER) AS route_type,
    CASE CAST(route_type AS INTEGER)
        WHEN 0 THEN 'Light rail'
        WHEN 2 THEN 'Commuter rail'
        WHEN 3 THEN 'Bus'
        ELSE 'Other'
    END AS mode
FROM routes;

-- Stops, with numeric coordinates ---------------------------------------
CREATE OR REPLACE TABLE stops_c AS
SELECT
    stop_id,
    stop_name,
    CAST(stop_lat AS DOUBLE) AS stop_lat,
    CAST(stop_lon AS DOUBLE) AS stop_lon
FROM stops;

-- Trips ------------------------------------------------------------------
CREATE OR REPLACE TABLE trips_c AS
SELECT
    trip_id,
    route_id,
    service_id,
    COALESCE(TRY_CAST(direction_id AS INTEGER), 0) AS direction_id,
    trip_headsign,                     -- used by sql/06 to spot route variants
    shape_id
FROM trips;

-- Stop times: convert "HH:MM:SS" to seconds after midnight ---------------
CREATE OR REPLACE TABLE stop_times_c AS
SELECT
    trip_id,
    stop_id,
    CAST(stop_sequence AS INTEGER) AS stop_sequence,
    TRY_CAST(timepoint AS INTEGER) AS timepoint,   -- 1 = exact scheduled time, 0 = estimated
    CAST(split_part(trim(departure_time), ':', 1) AS INTEGER) * 3600
  + CAST(split_part(trim(departure_time), ':', 2) AS INTEGER) * 60
  + CAST(split_part(trim(departure_time), ':', 3) AS INTEGER) AS dep_sec
FROM stop_times
WHERE departure_time IS NOT NULL
  AND trim(departure_time) <> '';

-- Regular weekly calendar ------------------------------------------------
CREATE OR REPLACE TABLE calendar_c AS
SELECT
    service_id,
    CAST(monday AS INTEGER)    AS monday,
    CAST(tuesday AS INTEGER)   AS tuesday,
    CAST(wednesday AS INTEGER) AS wednesday,
    CAST(thursday AS INTEGER)  AS thursday,
    CAST(friday AS INTEGER)    AS friday,
    CAST(saturday AS INTEGER)  AS saturday,
    CAST(sunday AS INTEGER)    AS sunday,
    CAST(strptime(start_date, '%Y%m%d') AS DATE) AS start_date,
    CAST(strptime(end_date,   '%Y%m%d') AS DATE) AS end_date
FROM calendar;

-- Exceptions: 1 = service added on this date, 2 = service removed --------
CREATE OR REPLACE TABLE calendar_dates_c AS
SELECT
    service_id,
    CAST(strptime(date, '%Y%m%d') AS DATE) AS service_date,
    CAST(exception_type AS INTEGER) AS exception_type
FROM calendar_dates;
