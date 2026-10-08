# =====================================================================
# config.R  -  settings shared by every script. Change things here only.
# =====================================================================

# RTD's schedule-only GTFS feed. RTD asks users to accept its license
# agreement first: https://www.rtd-denver.com/open-records/open-spatial-information/gtfs
GTFS_URL <- "https://www.rtd-denver.com/files/gtfs/google_transit.zip"

RAW_DIR  <- file.path("data", "raw")
GTFS_ZIP <- file.path(RAW_DIR, "rtd_gtfs.zip")
GTFS_DIR <- file.path(RAW_DIR, "gtfs")
DB_PATH  <- file.path("data", "rtd_gtfs.duckdb")
OUT_DIR  <- "output"

# Counties in the RTD service area (Colorado FIPS 08).
# Adams, Arapahoe, Boulder, Broomfield, Denver, Douglas, Jefferson.
RTD_COUNTIES <- c("001", "005", "013", "014", "031", "035", "059")

ACS_YEAR       <- 2023   # 5-year ACS ending in this year
PROJECTED_CRS  <- 26913   # NAD83 / UTM zone 13N: measures in meters, fits Colorado

# Time-of-day periods, in display order. Must match the `periods` table in
# sql/02_pick_service_day.sql.
PERIODS <- c("AM Peak", "Mid-Day", "PM Peak", "Late Night")
PERIOD_LABELS <- c(
  "AM Peak"    = "AM Peak (6-9 AM)",
  "Mid-Day"    = "Mid-Day (9 AM-3 PM)",
  "PM Peak"    = "PM Peak (3-7 PM)",
  "Late Night" = "Late Night (7 PM-3 AM)"
)

# Standard ("clock-face") headways, in minutes: values that repeat evenly
# within an hour or three hours. Must match the standard_headways table in
# sql/06_headway_diagnostics.sql. Medians not on this list get an asterisk.
STANDARD_HEADWAYS <- c(3, 4, 5, 6, 7.5, 10, 12, 15, 20, 30, 45, 60, 90)

# ---- Walk access (OpenStreetMap street network) -----------------------
# OSM extract for Colorado from Geofabrik (about 300 MB, downloaded once).
OSM_DIR        <- file.path("data", "osm")
OSM_PLACE      <- "Colorado"
WALK_DIST_M    <- 402.336 # a quarter mile, in meters, measured ALONG streets
STOP_SNAP_MAX_M <- 150    # stops farther than this from any walkable street are skipped
WALKSHED_SIDE_M <- 50     # reachable streets are widened by this much on each side
                          # (about the depth of a residential lot) to make an area
WALKSHED_HOLE_M2 <- 40000 # holes smaller than this (block interiors) are filled
NETWORK_PATH   <- file.path("data", "walk_network.rds")

# OSM highway types a person can walk on. Motorways are excluded; ways
# tagged foot=no or access=private/no are dropped in R/04_osm_network.R.
WALKABLE_HIGHWAYS <- c(
  "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link",
  "tertiary", "tertiary_link", "unclassified", "residential", "living_street",
  "service", "pedestrian", "footway", "path", "steps", "cycleway", "track",
  "corridor", "road"
)

dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(OSM_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_DIR, showWarnings = FALSE)

# Run a .sql file that contains several statements separated by ";".
run_sql_file <- function(con, path) {
  sql <- readLines(path, warn = FALSE)
  sql <- sub("--.*$", "", sql)                 # drop comments
  sql <- paste(sql, collapse = "\n")
  statements <- trimws(strsplit(sql, ";")[[1]])
  statements <- statements[nchar(statements) > 0]
  for (s in statements) DBI::dbExecute(con, s)
  message("Ran ", basename(path), " (", length(statements), " statements)")
  invisible(TRUE)
}
