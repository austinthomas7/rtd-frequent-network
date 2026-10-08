# How much of Denver can walk to frequent transit?

**[Read the full write-up →](https://YOUR-USERNAME.github.io/rtd-frequent-network/)**

A SQL and R analysis of how RTD's weekday service changes from the morning peak to late night, using the public GTFS feed, the OpenStreetMap walking network, and Census ACS data.

<!-- EDIT: replace [XX] with your results from output/headline_metrics.csv and output/access_by_period.csv -->

## Key findings

- **[XX] of [XX] routes** are frequent (median headway of 15 minutes or less, both directions) in the AM peak, **[XX]** at mid-day, and only **[XX]** after 7 PM.
- **[XX]% of stops** have a frequent route in the AM peak, falling to **[XX]%** late at night.
- **[XX]% of residents** and **[XX]% of households without a car** in the seven-county RTD area live within a quarter-mile walk of a frequent stop in the AM peak; late at night it is **[XX]%** and **[XX]%**.

![Headway distribution](images/headways.png)
<!-- EDIT: after `quarto render`, copy a chart into images/ (right-click the chart on the page > Save image) -->

## Questions

1. How often does each RTD route run in the AM Peak (6–9 AM), Mid-Day (9 AM–3 PM), PM Peak (3–7 PM), and Late Night (7 PM–3 AM)?
2. Which stops get frequent service (a median gap of 15 minutes or less between buses) in each period?
3. Who lives within a quarter-mile walk of that service, especially people without a car, and how does that change for people who travel outside the peaks?
4. Why do scheduled headways vary within a period, and when do they stray from round numbers like 10 or 15?

## Data

| Source | Use |
|---|---|
| [RTD GTFS](https://www.rtd-denver.com/open-records/open-spatial-information/gtfs) | Routes, stops, trips, and scheduled departure times |
| ACS 5-year 2019–2023, tables B01003 and B25044 | Population and zero-vehicle households by block group |
| [OpenStreetMap](https://www.openstreetmap.org/copyright) (Geofabrik Colorado extract) | Streets, sidewalks, and paths for network walk distances |

## Skills demonstrated

- **SQL (DuckDB):** CTEs, `LAG()` and `row_number()` window functions, `QUALIFY`, medians and percentiles (`median`, `quantile_cont`), window partitions by time period, `FILTER` aggregates, calendar expansion with `generate_series`, set operations (`UNION` / `EXCEPT`), type casting and cleaning
- **R:** OpenStreetMap network analysis (`osmextract`, `igraph` shortest paths), `sf` areal interpolation, `tidycensus`, `ggplot2`, `leaflet`
- **Reproducible reporting:** Quarto website published with GitHub Pages

## Project structure

```
sql/                      the analysis, in run order
  01_clean_tables.sql       cast raw text to typed tables, times to seconds
  02_pick_service_day.sql   choose a typical Wednesday, define the four periods
  03_route_headways.sql     min / max / median headways with LAG(), gaps inside each period only
  04_stop_frequency.sql     flag frequent stops in each period
  05_headline_metrics.sql   one row of key numbers per period
  06_headway_diagnostics.sql  classify every gap between trips (why headways vary)
R/
  00_setup.R                install packages (run once)
  config.R                  shared settings and helper
  01_download_gtfs.R ... 03_run_sql.R
  04_osm_network.R          OpenStreetMap walking network
  05_walksheds.R            quarter-mile network walksheds by period
  06_census_access.R        who lives inside each walkshed
run_all.R                 rebuild everything
index.qmd                 the write-up (renders to docs/)
additional-data.qmd       supporting tables: min/median/max headway by route and period
output/                   CSV results
```

## Reproduce

1. Get a free [Census API key](https://api.census.gov/data/key_signup.html) and follow `R/00_setup.R`. It is the only key the project needs.
2. Run `run_all.R` from the project root. The first run downloads about 300 MB of OpenStreetMap data into `data/osm/`.
3. In a terminal: `quarto render`

## Author

Austin Foster · [LinkedIn](https://www.linkedin.com/in/austin-foster-4a6506159/)
