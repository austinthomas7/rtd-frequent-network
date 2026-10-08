# =====================================================================
# 02_load_duckdb.R  -  load each GTFS .txt file into a DuckDB database
# Everything is loaded as text on purpose. The SQL in sql/01 then casts
# each column to the right type, which is where data cleaning happens.
# =====================================================================
source("R/config.R")
library(DBI)

con <- dbConnect(duckdb::duckdb(), DB_PATH)

tables <- c("routes", "stops", "trips", "stop_times", "calendar", "calendar_dates")

for (tbl in tables) {
  f <- file.path(GTFS_DIR, paste0(tbl, ".txt"))
  if (file.exists(f)) {
    dbExecute(con, sprintf(
      "CREATE OR REPLACE TABLE %s AS SELECT * FROM read_csv('%s', header = true, all_varchar = true)",
      tbl, normalizePath(f, winslash = "/")
    ))
    n <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s", tbl))$n
    message(sprintf("%-15s %10s rows", tbl, format(n, big.mark = ",")))
  }
}

# calendar.txt and calendar_dates.txt are each optional in GTFS.
# Create an empty version of whichever is missing so the SQL still runs.
if (!dbExistsTable(con, "calendar")) {
  dbExecute(con, "CREATE TABLE calendar (service_id VARCHAR, monday VARCHAR, tuesday VARCHAR,
    wednesday VARCHAR, thursday VARCHAR, friday VARCHAR, saturday VARCHAR, sunday VARCHAR,
    start_date VARCHAR, end_date VARCHAR)")
}
if (!dbExistsTable(con, "calendar_dates")) {
  dbExecute(con, "CREATE TABLE calendar_dates (service_id VARCHAR, date VARCHAR, exception_type VARCHAR)")
}
# direction_id is optional in trips.txt
if (!"direction_id" %in% dbListFields(con, "trips")) {
  dbExecute(con, "ALTER TABLE trips ADD COLUMN direction_id VARCHAR DEFAULT '0'")
}
# Other optional columns used by sql/06_headway_diagnostics.sql
for (col in c("trip_headsign", "shape_id")) {
  if (!col %in% dbListFields(con, "trips")) {
    dbExecute(con, sprintf("ALTER TABLE trips ADD COLUMN %s VARCHAR", col))
  }
}
if (!"timepoint" %in% dbListFields(con, "stop_times")) {
  dbExecute(con, "ALTER TABLE stop_times ADD COLUMN timepoint VARCHAR")
}

dbDisconnect(con, shutdown = TRUE)
