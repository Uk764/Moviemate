## =====================================================================
##  config.R  -  ONE place to control the whole project
##  Every other script runs source("config.R") first.
## =====================================================================

## ---- The only switch you normally change --------------------------------
## FALSE = MovieLens small (100K ratings)  -> runs in ~1-2 min, use for testing
## TRUE  = MovieLens 25M  (25M ratings)    -> "big data" run for final demo
USE_BIG_DATA <- FALSE

## ---- Paths ------------------------------------------------------------
ML_PATH   <- if (USE_BIG_DATA) "data/ml-25m/" else "data/ml-latest-small/"
TMDB_FILE <- "data/tmdb_5000_movies.csv"
CLEAN_DIR <- "data/clean/"
PLOT_DIR  <- "plots/"
OUT_DIR   <- "outputs/"

## ---- Data reduction thresholds -------------------------------------------
MIN_RATINGS_PER_MOVIE <- if (USE_BIG_DATA) 50 else 10   # drop rarely rated movies
MIN_RATINGS_PER_USER  <- 20                              # drop inactive users

## ---- Recommender matrix size (keeps RAM usage safe on 8 GB laptops) -------
CF_MAX_USERS <- if (USE_BIG_DATA) 5000 else Inf   # random sample of users
CF_MAX_ITEMS <- if (USE_BIG_DATA) 2000 else Inf   # most-rated movies only
CF_MIN_ITEM_RATINGS <- 30                          # CF needs well-rated movies

## ---- Hit / Flop definition ---------------------------------------------
HIT_MULTIPLIER <- 2      # Hit = revenue >= 2 x budget

SEED <- 42

## ---- Helpers ------------------------------------------------------------
for (d in c(CLEAN_DIR, PLOT_DIR, OUT_DIR)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

need_file <- function(path, hint) {
  if (!file.exists(path)) {
    stop("\n\nMissing file: ", path, "\n", hint, "\n", call. = FALSE)
  }
}

step <- function(txt) cat("\n==========", txt, "==========\n")

cat(sprintf("[config] Mode: %s | MovieLens folder: %s\n",
            if (USE_BIG_DATA) "BIG DATA (25M)" else "SMALL (testing)", ML_PATH))
