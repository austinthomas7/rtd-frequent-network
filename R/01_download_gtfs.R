# =====================================================================
# 01_download_gtfs.R  -  download and unzip RTD's GTFS feed
# If the download fails (network, firewall), download the zip in your
# browser from GTFS_URL, save it as data/raw/rtd_gtfs.zip, and rerun.
# =====================================================================
source("R/config.R")

if (!file.exists(GTFS_ZIP)) {
  message("Downloading ", GTFS_URL)
  options(timeout = 300)
  download.file(GTFS_URL, GTFS_ZIP, mode = "wb")
} else {
  message("Using existing ", GTFS_ZIP, " (delete it to force a fresh download)")
}

unzip(GTFS_ZIP, exdir = GTFS_DIR, overwrite = TRUE)
message("Files in feed: ", paste(list.files(GTFS_DIR), collapse = ", "))

# Record when you pulled the data. GTFS changes about three times a year,
# so your write-up must say which feed version it describes.
writeLines(format(Sys.Date()), file.path(RAW_DIR, "download_date.txt"))
