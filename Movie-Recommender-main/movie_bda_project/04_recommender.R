## =====================================================================
##  04_recommender.R  -  MODULE A: Movie Recommendation System
##  Models compared: RANDOM, POPULAR (baselines), UBCF, IBCF, SVD
##  + content-based (genres) and hybrid "movies like X"
## =====================================================================
if (!file.exists("config.R")) stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)
source("config.R")
suppressPackageStartupMessages({
  library(data.table); library(Matrix); library(recommenderlab); library(ggplot2)
})
source("R/functions.R")
set.seed(SEED)
step("STEP 4: RECOMMENDER SYSTEM")

need_file(paste0(CLEAN_DIR, "ratings.rds"), "Run 02_clean.R first.")
ratings    <- readRDS(paste0(CLEAN_DIR, "ratings.rds"))
movies     <- readRDS(paste0(CLEAN_DIR, "movies.rds"))
genre_cols <- readRDS(paste0(CLEAN_DIR, "genre_cols.rds"))

## ---- 1. Build the user x movie rating matrix -----------------------------
# Keep the most-rated movies and a random sample of users (RAM safety on big data)
if (is.finite(CF_MAX_ITEMS)) {
  top_items <- ratings[, .N, by = movieId][order(-N)][seq_len(min(.N, CF_MAX_ITEMS)), movieId]
  ratings_cf <- ratings[movieId %in% top_items]
} else ratings_cf <- ratings
ratings_cf <- ratings_cf[movieId %in% ratings_cf[, .N, by = movieId][N >= CF_MIN_ITEM_RATINGS, movieId]]
if (is.finite(CF_MAX_USERS) && uniqueN(ratings_cf$userId) > CF_MAX_USERS) {
  keep <- sample(unique(ratings_cf$userId), CF_MAX_USERS)
  ratings_cf <- ratings_cf[userId %in% keep]
}
ratings_cf <- ratings_cf[userId %in% ratings_cf[, .N, by = userId][N >= MIN_RATINGS_PER_USER, userId]]

u <- factor(ratings_cf$userId); i <- factor(ratings_cf$movieId)
sm <- sparseMatrix(i = as.integer(u), j = as.integer(i), x = ratings_cf$rating,
                   dims = c(nlevels(u), nlevels(i)),
                   dimnames = list(paste0("u", levels(u)), levels(i)))
rrm <- as(sm, "realRatingMatrix")

sparsity <- round(100 * (1 - nratings(rrm) / (nrow(rrm) * ncol(rrm))), 2)
matrix_info <- data.table(users = nrow(rrm), movies = ncol(rrm), ratings = nratings(rrm),
                          sparsity_pct = sparsity,
                          dense_size_MB = round(nrow(rrm) * ncol(rrm) * 8 / 1024^2, 1),
                          sparse_size_MB = round(as.numeric(object.size(rrm)) / 1024^2, 1))
cat("Rating matrix:\n"); print(matrix_info)
fwrite(matrix_info, paste0(OUT_DIR, "rating_matrix_info.csv"))

## ---- 2. Evaluation scheme: 80% train users, 10 known ratings per test user -
scheme <- evaluationScheme(rrm, method = "split", train = 0.8, given = 10, goodRating = 4)

methods <- list(
  RANDOM  = list(name = "RANDOM",  param = NULL),
  POPULAR = list(name = "POPULAR", param = NULL),
  UBCF    = list(name = "UBCF", param = list(method = "pearson", nn = 50)),
  IBCF    = list(name = "IBCF", param = list(method = "cosine", k = 30)),
  SVD     = list(name = "SVD",  param = list(k = 20))
)

## ---- 3. Rating prediction accuracy (RMSE / MAE) + training time ----------
acc <- rbindlist(lapply(names(methods), function(m) {
  t <- system.time(rec <- Recommender(getData(scheme, "train"), method = methods[[m]]$name,
                                      parameter = methods[[m]]$param))[["elapsed"]]
  pred <- predict(rec, getData(scheme, "known"), type = "ratings")
  a <- calcPredictionAccuracy(pred, getData(scheme, "unknown"))
  data.table(Model = m, RMSE = round(a[["RMSE"]], 3), MAE = round(a[["MAE"]], 3),
             train_seconds = round(t, 2))
}))
cat("\nRating prediction accuracy (lower RMSE/MAE = better):\n"); print(acc)
fwrite(acc, paste0(OUT_DIR, "recommender_rmse.csv"))

## ---- 4. Top-N recommendation quality (precision / recall) ---------------
topn_res <- evaluate(scheme, methods, type = "topNList", n = c(1, 3, 5, 10, 15, 20),
                     progress = FALSE)

png(paste0(PLOT_DIR, "rec_01_roc.png"), 900, 600)
plot(topn_res, annotate = c(1, 3), legend = "topleft"); title("ROC Curve - Recommender Models")
dev.off()
png(paste0(PLOT_DIR, "rec_02_precision_recall.png"), 900, 600)
plot(topn_res, "prec/rec", annotate = c(1, 3), legend = "topright"); title("Precision vs Recall")
dev.off()

topn <- rbindlist(lapply(names(topn_res), function(m) {
  x <- avg(topn_res[[m]]); r <- x[x[, "n"] == 10, ]
  data.table(Model = m, Precision_at_10 = round(r[["precision"]], 4),
             Recall_at_10 = round(r[["recall"]], 4), TPR_at_10 = round(r[["TPR"]], 4))
}))
cat("\nTop-10 recommendation quality (higher = better):\n"); print(topn)
fwrite(topn, paste0(OUT_DIR, "recommender_topn.csv"))

cmp <- melt(merge(acc[, .(Model, RMSE)], topn[, .(Model, Precision_at_10)]), id.vars = "Model")
p <- ggplot(cmp, aes(Model, value, fill = Model)) + geom_col(show.legend = FALSE) +
  facet_wrap(~variable, scales = "free_y") +
  geom_text(aes(label = round(value, 3)), vjust = -0.3, size = 3.5) +
  labs(title = "Recommender Model Comparison", subtitle = "RMSE: lower is better | Precision@10: higher is better",
       x = NULL, y = NULL) + theme_minimal(base_size = 13)
ggsave(paste0(PLOT_DIR, "rec_03_model_comparison.png"), p, width = 10, height = 5, dpi = 110, bg = "white")

## ---- 5. Pick the best personalised model and train it on ALL data --------
best <- topn[Model %in% c("UBCF", "IBCF", "SVD")][which.max(Precision_at_10), Model]
cat("\nBest personalised model by Precision@10:", best, "-> training final model on full matrix\n")
final_model <- Recommender(rrm, method = methods[[best]]$name, parameter = methods[[best]]$param)

## ---- 6. Bundle everything the app needs -------------------------------
# Adjusted-cosine matrix: each user's ratings centred on their own mean
Rt <- as(rrm@data, "TsparseMatrix")
user_mean <- rowSums(rrm@data) / pmax(rowCounts(rrm), 1)
Rt@x <- Rt@x - user_mean[Rt@i + 1]
R <- drop0(as(Rt, "CsparseMatrix"))

genre_mat  <- as.matrix(movies[, ..genre_cols])
genre_norm <- sqrt(rowSums(genre_mat^2)); genre_norm[genre_norm == 0] <- 1

rb <- list(model = final_model, model_name = best, rrm = rrm,
           R = R, R_norm = pmax(sqrt(colSums(R^2)), 1e-9),
           movies = movies, genre_cols = genre_cols,
           genre_mat = genre_mat, genre_norm = genre_norm,
           mode = if (USE_BIG_DATA) "MovieLens 25M" else "MovieLens small")
saveRDS(rb, paste0(CLEAN_DIR, "recommender.rds"))

## ---- 7. Demo in the console -----------------------------------------------
demo_user <- as.integer(sub("u", "", rownames(rrm)[1]))
cat("\nUser", demo_user, "liked:\n");               print(user_history(rb, demo_user, 5))
cat("\nTop 10 recommendations for user", demo_user, ":\n"); print(recommend_for_user(rb, demo_user))
cat("\nMovies like Toy Story (hybrid):\n");          print(similar_movies(rb, "toy story"))
cat("\nNew user who liked Matrix, Inception, Interstellar:\n")
print(recommend_from_liked(rb, c("matrix", "inception", "interstellar")))
cat("\nSaved recommender bundle to", paste0(CLEAN_DIR, "recommender.rds"), "\n")
