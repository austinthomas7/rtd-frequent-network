# =====================================================================
# 03_run_sql.R  -  run the SQL analysis in order and save results as CSV
# =====================================================================
source("R/config.R")
library(DBI)

con <- dbConnect(duckdb::duckdb(), DB_PATH)

sql_files <- sort(list.files("sql", pattern = "\\.sql$", full.names = TRUE))
for (f in sql_files) run_sql_file(con, f)

outputs <- c("params", "periods", "route_headways", "route_direction_headways",
             "stop_frequency", "headline_metrics",
             "route_gap_detail", "route_period_pattern")   # from sql/06
for (tbl in outputs) {
  df <- dbReadTable(con, tbl)
  readr::write_csv(df, file.path(OUT_DIR, paste0(tbl, ".csv")))
  message("Saved output/", tbl, ".csv (", nrow(df), " rows)")
}

print(dbReadTable(con, "headline_metrics"))
dbDisconnect(con, shutdown = TRUE)
