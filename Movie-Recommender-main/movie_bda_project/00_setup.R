## =====================================================================
##  00_setup.R  -  install packages + check that the data is in place
##  Run once per computer.
## =====================================================================
if (!file.exists("config.R")) stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)

pkgs <- c("data.table", "jsonlite", "ggplot2", "scales", "recommenderlab", "irlba",
          "caret", "randomForest", "rpart", "pROC", "shiny", "DT")

missing <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(missing)) {
  cat("Installing:", paste(missing, collapse = ", "), "\n")
  install.packages(missing, repos = "https://cloud.r-project.org", type = getOption("pkgType"))
}
still_missing <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(still_missing)) {
  stop("These packages failed to install: ", paste(still_missing, collapse = ", "),
       "\nRun install.packages(\"<name>\") for each and read the error.", call. = FALSE)
}
cat("All", length(pkgs), "packages installed.\n")

source("config.R")

## ---- Check data files ---------------------------------------------------
check <- function(path) {
  ok <- file.exists(path)
  cat(sprintf("  [%s] %s\n", if (ok) "OK" else "MISSING", path))
  ok
}
cat("\nData check:\n")
ok_small <- all(sapply(paste0("data/ml-latest-small/", c("ratings.csv", "movies.csv", "links.csv")), check))
ok_big   <- all(sapply(paste0("data/ml-25m/",          c("ratings.csv", "movies.csv", "links.csv")), check))
ok_tmdb  <- check(TMDB_FILE)

if (USE_BIG_DATA && !ok_big)
  stop("USE_BIG_DATA is TRUE but data/ml-25m/ is incomplete. Copy the ml-25m folder into data/ ",
       "or set USE_BIG_DATA <- FALSE in config.R.", call. = FALSE)
if (!USE_BIG_DATA && !ok_small)
  stop("data/ml-latest-small/ is incomplete. Download https://files.grouplens.org/datasets/movielens/ml-latest-small.zip ",
       "and unzip it into data/.", call. = FALSE)
if (!ok_tmdb)
  cat("\nNOTE: TMDB file missing -> hit/flop prediction will be skipped.\n",
      "Get it from https://www.kaggle.com/datasets/tmdb/tmdb-movie-metadata\n")
if (!ok_big)
  cat("\nNOTE: ml-25m not found -> only small mode available. Download:\n",
      "https://files.grouplens.org/datasets/movielens/ml-25m.zip and unzip into data/\n")

cat("\nSetup complete.\n")
