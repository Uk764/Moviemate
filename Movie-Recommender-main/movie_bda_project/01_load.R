## =====================================================================
##  01_load.R  -  load raw data (fast, memory-aware)
##  Big data points shown here:
##   * fread() (multi-threaded) vs base read.csv() speed comparison
##   * reading only needed columns to save RAM
## =====================================================================
if (!file.exists("config.R")) stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)
source("config.R")
suppressPackageStartupMessages(library(data.table))
step("STEP 1: LOAD DATA")

need_file(paste0(ML_PATH, "ratings.csv"),
          "Unzip MovieLens into data/ (see README.md), or change USE_BIG_DATA in config.R.")

## ---- Speed test: base R vs data.table (on the first 1M rows) ------------
n_test <- 1e6
t_base  <- system.time(invisible(read.csv(paste0(ML_PATH, "ratings.csv"), nrows = n_test)))[["elapsed"]]
t_fread <- system.time(invisible(fread(paste0(ML_PATH, "ratings.csv"), nrows = n_test)))[["elapsed"]]
load_benchmark <- data.table(method = c("read.csv (base R)", "fread (data.table)"),
                             seconds = round(c(t_base, t_fread), 2))
cat("Load-speed test (up to 1M rows):\n"); print(load_benchmark)

## ---- Full load (only the columns we need) -------------------------------
t_full <- system.time({
  ratings <- fread(paste0(ML_PATH, "ratings.csv"), select = c("userId", "movieId", "rating"))
  movies  <- fread(paste0(ML_PATH, "movies.csv"), encoding = "UTF-8")
  links   <- fread(paste0(ML_PATH, "links.csv"), select = c("movieId", "tmdbId"))
})[["elapsed"]]

# TMDB has JSON text inside CSV cells; base read.csv handles that quoting correctly
tmdb <- if (file.exists(TMDB_FILE)) {
  as.data.table(read.csv(TMDB_FILE, encoding = "UTF-8", stringsAsFactors = FALSE))
} else NULL

data_summary <- data.table(
  item  = c("Ratings", "Users", "Movies", "TMDB movies", "Ratings RAM (MB)", "Full load time (s)"),
  value = c(format(c(nrow(ratings), uniqueN(ratings$userId), nrow(movies),
                     if (is.null(tmdb)) NA else nrow(tmdb)), big.mark = ",", trim = TRUE),
            round(as.numeric(object.size(ratings)) / 1024^2, 1), round(t_full, 2)))
print(data_summary)
fwrite(load_benchmark, paste0(OUT_DIR, "load_benchmark.csv"))
fwrite(data_summary,   paste0(OUT_DIR, "data_summary.csv"))

if (is.null(tmdb)) cat("TMDB file not found -> hit/flop part will be skipped.\n")
