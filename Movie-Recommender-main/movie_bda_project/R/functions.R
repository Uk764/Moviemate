## =====================================================================
##  R/functions.R  -  recommendation helper functions
##  Used by 04_recommender.R and by the Shiny app (app.R).
##  `rb` = the recommender bundle saved in data/clean/recommender.rds
## =====================================================================

## Find a movie by (part of) its title. Exact title wins, else most-rated match.
find_movie <- function(rb, query) {
  q <- tolower(trimws(query))
  if (q == "") return(NA_integer_)
  exact <- which(tolower(rb$movies$clean_title) == q | tolower(rb$movies$title) == q)
  hits  <- if (length(exact)) exact else grep(q, tolower(rb$movies$title), fixed = TRUE)
  if (!length(hits)) return(NA_integer_)
  hits[which.max(rb$movies$n_ratings[hits])]
}

## Content similarity: cosine similarity of genre vectors (all movies)
genre_similarity <- function(rb, idx) {
  g <- rb$genre_mat
  as.vector(g %*% g[idx, ]) / (rb$genre_norm * rb$genre_norm[idx])
}

## Collaborative similarity: cosine similarity of the movies' rating columns
## (only for movies inside the rating matrix; others get NA)
rating_similarity <- function(rb, idx) {
  out <- rep(NA_real_, nrow(rb$movies))
  col <- match(as.character(rb$movies$movieId[idx]), colnames(rb$R))
  if (is.na(col)) return(out)
  s <- as.vector(Matrix::crossprod(rb$R, rb$R[, col])) / (rb$R_norm * rb$R_norm[col])
  out[match(colnames(rb$R), as.character(rb$movies$movieId))] <- s
  out
}

## "Movies like X"  method = "hybrid" (ratings + genres), "genre" or "ratings"
similar_movies <- function(rb, query, n = 10, method = "hybrid", w_ratings = 0.6) {
  idx <- find_movie(rb, query)
  if (is.na(idx)) return(NULL)
  gs <- genre_similarity(rb, idx)
  rs <- rating_similarity(rb, idx)
  if (method == "ratings" && all(is.na(rs))) method <- "genre"   # cold movie -> fallback
  score <- switch(method,
    genre   = gs,
    ratings = rs,
    hybrid  = if (all(is.na(rs))) gs else w_ratings * rs + (1 - w_ratings) * gs)
  res <- rb$movies[, .(title, genres, avg_rating, n_ratings)]
  res[, `:=`(genre_sim = round(gs, 3), rating_sim = round(rs, 3), score = round(score, 3))]
  res <- res[-idx][!is.na(score)]
  # small popularity tie-breaker so obscure duplicates don't dominate
  res <- res[order(-score, -n_ratings)]
  attr(res, "query_title") <- rb$movies$title[idx]
  head(res, n)
}

## Top-N for an existing user using the trained recommenderlab model
recommend_for_user <- function(rb, uid, n = 10) {
  row <- which(rownames(rb$rrm) == paste0("u", uid))
  if (!length(row)) return(NULL)
  pred <- predict(rb$model, rb$rrm[row, ], n = n)
  ids  <- as.integer(as(pred, "list")[[1]])
  out  <- rb$movies[match(ids, movieId), .(rank = seq_along(ids), title, genres, avg_rating, n_ratings)]
  out
}

## What has this user already rated highly? (for showing context)
user_history <- function(rb, uid, n = 10) {
  row <- which(rownames(rb$rrm) == paste0("u", uid))
  if (!length(row)) return(NULL)
  r <- as(rb$rrm[row, ], "list")[[1]]
  h <- data.table::data.table(movieId = as.integer(names(r)), user_rating = as.numeric(r))
  h <- merge(h, rb$movies[, .(movieId, title, genres)], by = "movieId")
  head(h[order(-user_rating)][, .(title, genres, user_rating)], n)
}

## Cold start: a NEW user picks movies they liked -> recommend
## Score = sum of hybrid similarities to every liked movie (item-based idea)
recommend_from_liked <- function(rb, liked_titles, n = 10, w_ratings = 0.6) {
  idx <- unique(na.omit(vapply(liked_titles, function(t) find_movie(rb, t), integer(1))))
  if (!length(idx)) return(NULL)
  total <- rep(0, nrow(rb$movies))
  for (i in idx) {
    gs <- genre_similarity(rb, i); rs <- rating_similarity(rb, i)
    s  <- if (all(is.na(rs))) gs else w_ratings * ifelse(is.na(rs), 0, rs) + (1 - w_ratings) * gs
    total <- total + s
  }
  res <- rb$movies[, .(title, genres, avg_rating, n_ratings)][, score := round(total / length(idx), 3)]
  res <- res[-idx][order(-score, -avg_rating)]
  head(res[, rank := .I][, .(rank, title, genres, avg_rating, score)], n)
}
