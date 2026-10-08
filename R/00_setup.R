# =====================================================================
# 00_setup.R  -  run ONCE on a new computer
# Installs every package the project uses and stores your Census API key.
# =====================================================================

pkgs <- c(
  "DBI", "duckdb",            # SQL engine that runs inside R, no server needed
  "readr", "dplyr", "tidyr",  # data handling
  "sf", "tidycensus",         # spatial data + Census/ACS downloads
  "osmextract", "igraph",     # OpenStreetMap walk network + shortest paths
  "ggplot2", "scales",        # static charts
  "leaflet", "htmltools",     # interactive map for the Quarto page
  "knitr", "rmarkdown"        # needed for Quarto to run R code
)

missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing) > 0) {
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All packages already installed.")
}

# ---- Census API key (needed for R/06_census_access.R only) ------------
# The OpenStreetMap data and the map background tiles need no key.
# 1. Request a free key: https://api.census.gov/data/key_signup.html
# 2. Paste it below, remove the leading "#", run the line ONCE.
#    install = TRUE saves it to your .Renviron so you never paste it again.
#    Never commit the key itself to GitHub.
#
# tidycensus::census_api_key("YOUR_KEY_HERE", install = TRUE)
#
# Then restart R (RStudio: Session > Restart R).
