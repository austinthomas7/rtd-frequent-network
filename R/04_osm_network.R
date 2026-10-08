# =====================================================================
# 04_osm_network.R  -  build a walkable street network from OpenStreetMap
# Question: a quarter mile "as the crow flies" overstates walk access
#           wherever streets don't connect (rail lines, highways, cul-de-
#           sacs, rivers). To measure distance ALONG streets and paths we
#           need the walking network itself.
# Method:   1. download the OpenStreetMap extract for Colorado (Geofabrik,
#              no API key) and keep only ways near frequent stops
#           2. keep ways a person can walk on (streets, sidewalks, paths,
#              stairs; not motorways or private/no-foot ways)
#           3. break every way into straight segments between consecutive
#              OSM nodes. Two ways connect only where they share a node,
#              so a bridge over a street is correctly NOT a connection.
#           4. save the network as a plain node + edge table (data/,
#              not committed to GitHub; rebuild any time with this script)
# Runs once; the download is about 300 MB and the first conversion takes
# a few minutes. Later runs reuse data/osm/.
# =====================================================================
source("R/config.R")
suppressPackageStartupMessages({
  library(dplyr); library(sf); library(osmextract)
})

# ---- 1. Study area: every stop that is frequent in any period, plus a margin
stops <- readr::read_csv(file.path(OUT_DIR, "stop_frequency.csv"), show_col_types = FALSE)

study_area <- stops |>
  filter(is_frequent) |>
  distinct(stop_id, stop_lon, stop_lat) |>
  st_as_sf(coords = c("stop_lon", "stop_lat"), crs = 4326) |>
  st_transform(PROJECTED_CRS) |>
  st_bbox() |>
  st_as_sfc() |>
  st_buffer(2 * WALK_DIST_M) |>      # room for walks that leave the box
  st_transform(4326)

# ---- 2. Download (first run only) and read the walkable ways -------------
osm_lines <- oe_get(
  place                 = OSM_PLACE,
  provider              = "geofabrik",
  layer                 = "lines",
  extra_tags            = c("foot", "access"),
  boundary              = study_area,
  boundary_type         = "spat",        # keep whole ways that touch the area
  download_directory    = OSM_DIR,
  force_vectortranslate = TRUE,          # re-filter if the study area changes
  quiet                 = FALSE
)

walk_ways <- osm_lines |>
  filter(
    highway %in% WALKABLE_HIGHWAYS,
    is.na(foot) | foot != "no",
    is.na(access) | !access %in% c("no", "private") |
      foot %in% c("yes", "designated", "permissive")
  ) |>
  st_transform(PROJECTED_CRS) |>
  st_cast("LINESTRING", warn = FALSE)

message(format(nrow(walk_ways), big.mark = ","), " walkable OSM ways")

# ---- 3. Ways -> segments between consecutive nodes ----------------------
xy <- st_coordinates(walk_ways)            # columns X, Y, L1 (= which way)
n  <- nrow(xy)
same_way <- xy[-1, "L1"] == xy[-n, "L1"]   # consecutive vertices on the same way

x1 <- xy[-n, "X"][same_way];  y1 <- xy[-n, "Y"][same_way]
x2 <- xy[-1, "X"][same_way];  y2 <- xy[-1, "Y"][same_way]

# Identical coordinates = the same OSM node (shared by every way through it).
# Rounding to 10 cm gives each node one numeric key.
node_key <- function(x, y) round(x * 10) * 1e8 + round(y * 10)
k1 <- node_key(x1, y1)
k2 <- node_key(x2, y2)
keys <- unique(c(k1, k2))

nodes <- data.frame(
  x = c(x1, x2)[match(keys, c(k1, k2))],
  y = c(y1, y2)[match(keys, c(k1, k2))]
)
edges <- data.frame(
  from   = match(k1, keys),
  to     = match(k2, keys),
  len_m  = sqrt((x2 - x1)^2 + (y2 - y1)^2)
) |>
  filter(from != to)

saveRDS(list(nodes = nodes, edges = edges, crs = PROJECTED_CRS), NETWORK_PATH)
message(sprintf("Saved %s: %s nodes, %s segments, %s km of walkable network",
                NETWORK_PATH,
                format(nrow(nodes), big.mark = ","),
                format(nrow(edges), big.mark = ","),
                format(round(sum(edges$len_m) / 1000), big.mark = ",")))
