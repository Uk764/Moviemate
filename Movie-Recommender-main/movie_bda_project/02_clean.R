## =====================================================================
##  02_clean.R  -  clean MovieLens + build the TMDB hit/flop dataset
##  Runs 01_load.R automatically.
## =====================================================================
if (!file.exists("config.R")) stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)
source("01_load.R")
suppressPackageStartupMessages(library(jsonlite))
step("STEP 2: CLEAN DATA")

## ---- 1. Ratings: remove noise (rare movies, inactive users) --------------
before <- c(nrow(ratings), uniqueN(ratings$userId), uniqueN(ratings$movieId))
ratings <- unique(ratings, by = c("userId", "movieId"))
ratings <- ratings[!is.na(rating)]
pop_movies   <- ratings[, .N, by = movieId][N >= MIN_RATINGS_PER_MOVIE, movieId]
ratings      <- ratings[movieId %in% pop_movies]
active_users <- ratings[, .N, by = userId][N >= MIN_RATINGS_PER_USER, userId]
ratings      <- ratings[userId %in% active_users]
after <- c(nrow(ratings), uniqueN(ratings$userId), uniqueN(ratings$movieId))

reduction <- data.table(metric = c("Ratings", "Users", "Movies"),
                        before = before, after = after,
                        kept_pct = round(100 * after / before, 1))
cat("Data reduction:\n"); print(reduction)
fwrite(reduction, paste0(OUT_DIR, "data_reduction.csv"))

## ---- 2. Movies: year, clean title, one-hot genres, rating stats ----------
movies <- movies[movieId %in% unique(ratings$movieId)]
movies[, year := suppressWarnings(as.integer(sub(".*\\((\\d{4})\\)\\s*$", "\\1", title)))]
movies[, clean_title := trimws(sub("\\s*\\(\\d{4}\\)\\s*$", "", title))]

genre_list <- setdiff(sort(unique(unlist(strsplit(movies$genres, "|", fixed = TRUE)))),
                      "(no genres listed)")
genre_cols <- make.names(genre_list)               # "Sci-Fi" -> "Sci.Fi"
for (i in seq_along(genre_list))
  movies[, (genre_cols[i]) := as.integer(grepl(genre_list[i], genres, fixed = TRUE))]

stats <- ratings[, .(avg_rating = round(mean(rating), 2), n_ratings = .N), by = movieId]
movies <- merge(movies, stats, by = "movieId")
movies <- merge(movies, links, by = "movieId", all.x = TRUE)

saveRDS(ratings,    paste0(CLEAN_DIR, "ratings.rds"))
saveRDS(movies,     paste0(CLEAN_DIR, "movies.rds"))
saveRDS(genre_cols, paste0(CLEAN_DIR, "genre_cols.rds"))
cat("Saved clean ratings:", format(nrow(ratings), big.mark = ","),
    "| movies:", nrow(movies), "\n")

## ---- 3. TMDB -> Hit/Flop dataset -----------------------------------------
json_names <- function(x) {
  if (is.na(x) || x == "" || x == "[]") return(character(0))
  x <- gsub('""', '"', x, fixed = TRUE)          # safety: undo CSV double-quote escaping
  out <- tryCatch(fromJSON(x)$name, error = function(e) character(0))
  if (is.null(out)) character(0) else out
}

if (!is.null(tmdb)) {
  n0 <- nrow(tmdb)
  # Remove junk: budget/revenue of 0 or tiny placeholder values, missing runtime
  tmdb <- tmdb[budget >= 10000 & revenue >= 10000 & !is.na(runtime) & runtime > 0 &
               status == "Released"]
  tmdb[, release_date := as.IDate(as.character(release_date))]
  tmdb <- tmdb[!is.na(release_date)]

  g  <- lapply(tmdb$genres, json_names)
  pc <- lapply(tmdb$production_companies, json_names)
  ct <- lapply(tmdb$production_countries, json_names)
  kw <- lapply(tmdb$keywords, json_names)

  tmdb[, `:=`(
    main_genre    = vapply(g, function(v) if (length(v)) v[1] else "Unknown", character(1)),
    num_genres    = lengths(g),
    n_companies   = lengths(pc),
    n_keywords    = lengths(kw),
    us_production = as.integer(vapply(ct, function(v) "United States of America" %in% v, logical(1))),
    has_homepage  = as.integer(!is.na(homepage) & homepage != ""),
    release_month = month(release_date),
    release_year  = year(release_date),
    log_budget    = round(log10(budget), 4)
  )]

  # Group rare genres / languages so models get enough examples per level
  rare_g <- tmdb[, .N, by = main_genre][N < 30, main_genre]
  tmdb[main_genre %in% rare_g, main_genre := "Other"]
  top_lang <- tmdb[, .N, by = original_language][order(-N)][1:4, original_language]
  tmdb[, language := ifelse(original_language %in% top_lang, original_language, "other")]

  tmdb[, hit := factor(ifelse(revenue >= HIT_MULTIPLIER * budget, "Hit", "Flop"),
                       levels = c("Flop", "Hit"))]

  hit_data <- tmdb[, .(id, title, budget, revenue, log_budget, runtime, main_genre, num_genres,
                       release_month, release_year, language, n_companies, n_keywords,
                       us_production, has_homepage,
                       popularity, vote_average, vote_count,   # post-release: EDA only, NOT used in model
                       hit)]
  saveRDS(hit_data, paste0(CLEAN_DIR, "hit_data.rds"))
  cat("TMDB:", n0, "->", nrow(hit_data), "usable movies after cleaning\n")
  print(table(hit_data$hit))
} else {
  cat("TMDB skipped (file missing).\n")
}
