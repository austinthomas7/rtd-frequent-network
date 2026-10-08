# =====================================================================
# 06_census_access.R
# Question: in each time-of-day period, what share of residents, and of
#           households without a car, live within a quarter-mile WALK of
#           a frequent stop?
# Method:   1. read the network walksheds from R/05_walksheds.R
#           2. download ACS block groups for the RTD counties
#           3. areal weighting: if 40% of a block group's land falls in
#              a walkshed, count 40% of its people and households
# Needs a Census API key (see R/00_setup.R). This is the ONLY step in the
# project that needs a key.
# =====================================================================
source("R/config.R")
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(sf); library(tidycensus)
})

walksheds <- st_read(file.path(OUT_DIR, "frequent_walksheds.geojson"), quiet = TRUE) |>
  st_transform(PROJECTED_CRS) |>
  st_make_valid()

# ACS variables
#   B01003_001 total population
#   B25044_001 occupied households
#   B25044_003 owner households with no vehicle
#   B25044_010 renter households with no vehicle
acs <- get_acs(
  geography = "block group",
  state = "CO",
  county = RTD_COUNTIES,
  year = ACS_YEAR,
  survey = "acs5",
  variables = c(pop = "B01003_001", hh = "B25044_001",
                zero_own = "B25044_003", zero_rent = "B25044_010"),
  output = "wide",
  geometry = TRUE
) |>
  transmute(
    GEOID,
    pop     = popE,
    hh      = hhE,
    zero_hh = zero_ownE + zero_rentE
  ) |>
  st_transform(PROJECTED_CRS) |>
  st_make_valid()

acs$bg_area <- as.numeric(st_area(acs))
st_agr(acs) <- "constant"        # attributes are area-wide totals (silences a warning)
st_agr(walksheds) <- "constant"

# Area of each block group inside each walkshed (one row per pair)
inside <- st_intersection(acs, walksheds)
inside$in_area <- as.numeric(st_area(inside))

share <- inside |>
  st_drop_geometry() |>
  group_by(GEOID, walkshed) |>
  summarise(in_area = sum(in_area), .groups = "drop")

# Every block group x every walkshed, so places outside a walkshed count as 0
bg <- acs |>
  st_drop_geometry() |>
  tidyr::crossing(walkshed = walksheds$walkshed) |>
  left_join(share, by = c("GEOID", "walkshed")) |>
  mutate(
    share_in   = pmin(coalesce(in_area / bg_area, 0), 1),
    pop_in     = pop * share_in,
    zero_hh_in = zero_hh * share_in,
    hh_in      = hh * share_in
  )

walkshed_order <- c(PERIODS, "Every period", "AM Peak (straight-line)")

access <- bg |>
  group_by(walkshed) |>
  summarise(
    total_pop          = sum(pop, na.rm = TRUE),
    pop_near_frequent  = round(sum(pop_in, na.rm = TRUE)),
    pct_pop_near       = round(100 * sum(pop_in, na.rm = TRUE) / sum(pop, na.rm = TRUE), 1),
    zero_car_hh        = sum(zero_hh, na.rm = TRUE),
    zero_car_hh_near   = round(sum(zero_hh_in, na.rm = TRUE)),
    pct_zero_car_near  = round(100 * sum(zero_hh_in, na.rm = TRUE) / sum(zero_hh, na.rm = TRUE), 1),
    pct_all_hh_near    = round(100 * sum(hh_in, na.rm = TRUE) / sum(hh, na.rm = TRUE), 1),
    .groups = "drop"
  ) |>
  mutate(walkshed = factor(walkshed, levels = walkshed_order)) |>
  arrange(walkshed)

readr::write_csv(access, file.path(OUT_DIR, "access_by_period.csv"))

# Block group shares, one column per walkshed (for mapping or checking)
bg |>
  select(GEOID, pop, zero_hh, walkshed, share_in) |>
  mutate(walkshed = paste0("share_", gsub("^_+|_+$", "", gsub("[^a-z]+", "_", tolower(walkshed))))) |>
  pivot_wider(names_from = walkshed, values_from = share_in) |>
  readr::write_csv(file.path(OUT_DIR, "blockgroup_access.csv"))

print(access)
