## =====================================================================
##  03_eda.R  -  Exploratory Data Analysis (all graphs saved in plots/)
## =====================================================================
if (!file.exists("config.R")) stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)
source("config.R")
suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(scales) })
step("STEP 3: EDA")

need_file(paste0(CLEAN_DIR, "ratings.rds"), "Run 02_clean.R first.")
ratings    <- readRDS(paste0(CLEAN_DIR, "ratings.rds"))
movies     <- readRDS(paste0(CLEAN_DIR, "movies.rds"))
genre_cols <- readRDS(paste0(CLEAN_DIR, "genre_cols.rds"))
hit_file   <- paste0(CLEAN_DIR, "hit_data.rds")
hit_data   <- if (file.exists(hit_file)) readRDS(hit_file) else NULL

theme_set(theme_minimal(base_size = 13))
save_plot <- function(p, name) {
  ggsave(paste0(PLOT_DIR, name, ".png"), p, width = 9, height = 5.5, dpi = 110, bg = "white")
  cat("  saved", name, "\n")
}

## 1. Rating distribution (aggregate first - never plot millions of raw rows)
p <- ggplot(ratings[, .N, by = rating], aes(factor(rating), N)) +
  geom_col(fill = "#2C7FB8") + scale_y_continuous(labels = comma) +
  labs(title = "Rating Distribution", x = "Rating (stars)", y = "Number of ratings")
save_plot(p, "eda_01_rating_distribution")

## 2. Movies per genre
gc <- data.table(genre = genre_cols, n = colSums(movies[, ..genre_cols]))
p <- ggplot(gc, aes(reorder(genre, n), n)) + geom_col(fill = "#F28E2B") + coord_flip() +
  labs(title = "Movies per Genre", x = NULL, y = "Number of movies")
save_plot(p, "eda_02_movies_per_genre")

## 3. Average rating by release year
yr <- movies[!is.na(year), .(avg = weighted.mean(avg_rating, n_ratings), n = .N), by = year][n >= 5]
p <- ggplot(yr[order(year)], aes(year, avg)) + geom_line(colour = "#6A3D9A", linewidth = 1) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, colour = "grey50", linetype = 2) +
  labs(title = "Average Rating by Release Year", x = "Release year", y = "Average rating")
save_plot(p, "eda_03_rating_by_year")

## 4. Ratings per user - the "long tail" typical of big data
upu <- ratings[, .N, by = userId]
p <- ggplot(upu, aes(N)) + geom_histogram(bins = 40, fill = "#1B9E77") + scale_x_log10(labels = comma) +
  labs(title = "Ratings per User (log scale)", subtitle = "Few users rate a lot, most rate a little",
       x = "Ratings given by a user", y = "Users")
save_plot(p, "eda_04_ratings_per_user")

## 5. Top 15 most-rated movies
top <- movies[order(-n_ratings)][1:15]
p <- ggplot(top, aes(reorder(clean_title, n_ratings), n_ratings)) + geom_col(fill = "#E15759") +
  coord_flip() + scale_y_continuous(labels = comma) +
  labs(title = "Top 15 Most-Rated Movies", x = NULL, y = "Number of ratings")
save_plot(p, "eda_05_top_movies")

if (!is.null(hit_data)) {
  ## 6. Budget vs revenue
  p <- ggplot(hit_data, aes(budget, revenue, colour = hit)) + geom_point(alpha = 0.45) +
    geom_abline(slope = 1, intercept = log10(HIT_MULTIPLIER), linetype = 2) +
    scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
    scale_y_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
    scale_colour_manual(values = c(Flop = "#E15759", Hit = "#59A14F")) +
    labs(title = "Budget vs Revenue (log scale)", subtitle = "Dashed line = Hit threshold (revenue = 2 x budget)",
         x = "Budget", y = "Revenue", colour = NULL)
  save_plot(p, "eda_06_budget_vs_revenue")

  ## 7. Hit rate by genre
  hr <- hit_data[, .(hit_rate = mean(hit == "Hit"), n = .N), by = main_genre]
  p <- ggplot(hr, aes(reorder(main_genre, hit_rate), hit_rate)) + geom_col(fill = "#59A14F") +
    geom_text(aes(label = paste0("n=", n)), hjust = -0.1, size = 3.3) + coord_flip() +
    scale_y_continuous(labels = percent, limits = c(0, 1)) +
    labs(title = "Hit Rate by Main Genre", x = NULL, y = "Hit rate")
  save_plot(p, "eda_07_hit_rate_by_genre")

  ## 8. Hit rate by release month
  hm <- hit_data[, .(hit_rate = mean(hit == "Hit")), by = release_month][order(release_month)]
  p <- ggplot(hm, aes(factor(month.abb[release_month], levels = month.abb), hit_rate)) +
    geom_col(fill = "#4E79A7") + scale_y_continuous(labels = percent) +
    labs(title = "Hit Rate by Release Month", x = NULL, y = "Hit rate")
  save_plot(p, "eda_08_hit_rate_by_month")

  ## 9. Correlation heatmap
  num <- hit_data[, .(log_budget, log_revenue = log10(revenue), runtime, num_genres, n_companies,
                      n_keywords, release_year, popularity, vote_average, vote_count)]
  cm <- as.data.table(as.table(cor(num, use = "complete.obs")))
  p <- ggplot(cm, aes(V1, V2, fill = N)) + geom_tile(colour = "white") +
    geom_text(aes(label = round(N, 2)), size = 3) +
    scale_fill_gradient2(low = "#E15759", mid = "white", high = "#4E79A7", limits = c(-1, 1)) +
    labs(title = "Correlation of Numeric Movie Features", x = NULL, y = NULL, fill = "r") +
    theme(axis.text.x = element_text(angle = 40, hjust = 1))
  save_plot(p, "eda_09_correlation")
}

cat("EDA plots saved to", PLOT_DIR, "\n")
