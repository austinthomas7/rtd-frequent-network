# =====================================================================
# run_all.R  -  rebuild every result from scratch
# Open the project folder (or rtd-frequent-network.Rproj in RStudio) so
# the working directory is the project root, then run this file.
# =====================================================================
source("R/01_download_gtfs.R")
source("R/02_load_duckdb.R")
source("R/03_run_sql.R")
source("R/04_osm_network.R")     # first run downloads ~300 MB of OpenStreetMap data
source("R/05_walksheds.R")
source("R/06_census_access.R")   # needs a Census API key; see R/00_setup.R

message("\nDone. Now render the site from the terminal:  quarto render")
