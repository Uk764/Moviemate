## =====================================================================
##  05_prediction.R  -  MODULE B: Will the movie be a HIT or FLOP?
##  ("movie chalega ya nahi chalega")
##  Hit = revenue >= 2 x budget (see config.R)
##  Models: Logistic Regression, Decision Tree, Random Forest
##  Only PRE-RELEASE features are used (no popularity / votes -> no data leakage)
## =====================================================================
if (!file.exists("config.R")) stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)
source("config.R")
suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(caret); library(pROC)
  library(randomForest); library(rpart)
})
set.seed(SEED)
step("STEP 5: HIT / FLOP PREDICTION")

hit_file <- paste0(CLEAN_DIR, "hit_data.rds")
if (!file.exists(hit_file)) {
  cat("hit_data.rds not found (TMDB file missing). Skipping prediction module.\n",
      "Put tmdb_5000_movies.csv in data/ and run 02_clean.R again.\n")
} else {

hit_data <- readRDS(hit_file)
features <- c("log_budget", "runtime", "main_genre", "num_genres", "release_month",
              "release_year", "language", "n_companies", "n_keywords",
              "us_production", "has_homepage")
df <- as.data.frame(hit_data[, c(features, "hit"), with = FALSE])
df$main_genre <- factor(df$main_genre)
df$language   <- factor(df$language)

## ---- 1. Train / test split (70/30, keeps Hit/Flop ratio) -------------------
idx   <- createDataPartition(df$hit, p = 0.7, list = FALSE)
train <- df[idx, ]; test <- df[-idx, ]
cat("Train:", nrow(train), "| Test:", nrow(test), "\n")
baseline_acc <- max(prop.table(table(test$hit)))
cat("Baseline accuracy (always predict majority class):", round(baseline_acc, 3), "\n")

## ---- 2. Train 3 models with 5-fold cross validation ------------------------
ctrl <- trainControl(method = "cv", number = 5, classProbs = TRUE,
                     summaryFunction = twoClassSummary)
fml <- hit ~ .
models <- list(
  "Logistic Regression" = train(fml, data = train, method = "glm", family = "binomial",
                                metric = "ROC", trControl = ctrl),
  "Decision Tree"       = train(fml, data = train, method = "rpart", tuneLength = 10,
                                metric = "ROC", trControl = ctrl),
  "Random Forest"       = train(fml, data = train, method = "rf", ntree = 300,
                                tuneGrid = data.frame(mtry = c(2, 4, 6)),
                                metric = "ROC", trControl = ctrl, importance = TRUE)
)

## ---- 3. Evaluate on the unseen test set -----------------------------------
rocs <- list()
results <- rbindlist(lapply(names(models), function(m) {
  prob <- predict(models[[m]], test, type = "prob")[, "Hit"]
  pred <- factor(ifelse(prob >= 0.5, "Hit", "Flop"), levels = c("Flop", "Hit"))
  cm   <- confusionMatrix(pred, test$hit, positive = "Hit")
  rocs[[m]] <<- roc(test$hit, prob, levels = c("Flop", "Hit"), direction = "<", quiet = TRUE)
  data.table(Model = m,
             Accuracy  = round(cm$overall[["Accuracy"]], 3),
             Precision = round(cm$byClass[["Precision"]], 3),
             Recall    = round(cm$byClass[["Recall"]], 3),
             F1        = round(cm$byClass[["F1"]], 3),
             AUC       = round(as.numeric(auc(rocs[[m]])), 3))
}))
results <- rbind(results, data.table(Model = "Baseline (majority)", Accuracy = round(baseline_acc, 3),
                                     Precision = NA, Recall = NA, F1 = NA, AUC = 0.5))
cat("\nTest-set results:\n"); print(results)
fwrite(results, paste0(OUT_DIR, "prediction_results.csv"))

best <- results[Model != "Baseline (majority)"][which.max(AUC), Model]
cat("\nBest model by AUC:", best, "\n")
best_pred <- factor(ifelse(predict(models[[best]], test, type = "prob")[, "Hit"] >= 0.5, "Hit", "Flop"),
                    levels = c("Flop", "Hit"))
best_cm <- confusionMatrix(best_pred, test$hit, positive = "Hit")
print(best_cm$table)

## ---- 4. Plots ---------------------------------------------------------------
theme_set(theme_minimal(base_size = 13))

roc_df <- rbindlist(lapply(names(rocs), function(m)
  data.table(Model = sprintf("%s (AUC %.3f)", m, auc(rocs[[m]])),
             FPR = 1 - rocs[[m]]$specificities, TPR = rocs[[m]]$sensitivities)))
p <- ggplot(roc_df[order(Model, FPR, TPR)], aes(FPR, TPR, colour = Model)) + geom_path(linewidth = 1) +
  geom_abline(linetype = 2, colour = "grey60") +
  labs(title = "ROC Curves - Hit/Flop Models (test set)", x = "False Positive Rate",
       y = "True Positive Rate", colour = NULL) + theme(legend.position = "bottom")
ggsave(paste0(PLOT_DIR, "pred_01_roc.png"), p, width = 8, height = 6, dpi = 110, bg = "white")

cm_df <- as.data.table(best_cm$table)
p <- ggplot(cm_df, aes(Reference, Prediction, fill = N)) + geom_tile(colour = "white") +
  geom_text(aes(label = N), size = 8) + scale_fill_gradient(low = "#EAF2FB", high = "#2C7FB8") +
  labs(title = paste("Confusion Matrix -", best), x = "Actual", y = "Predicted") +
  theme(legend.position = "none")
ggsave(paste0(PLOT_DIR, "pred_02_confusion_matrix.png"), p, width = 6, height = 5, dpi = 110, bg = "white")

imp <- varImp(models[["Random Forest"]])$importance
imp <- data.table(feature = rownames(imp), importance = if ("Overall" %in% names(imp)) imp$Overall else imp$Hit)
imp <- imp[order(-importance)][1:min(15, .N)]
p <- ggplot(imp, aes(reorder(feature, importance), importance)) + geom_col(fill = "#59A14F") + coord_flip() +
  labs(title = "Feature Importance - Random Forest", x = NULL, y = "Importance (scaled 0-100)")
ggsave(paste0(PLOT_DIR, "pred_03_feature_importance.png"), p, width = 8, height = 6, dpi = 110, bg = "white")

p <- ggplot(melt(results[Model != "Baseline (majority)", .(Model, Accuracy, F1, AUC)], id.vars = "Model"),
            aes(variable, value, fill = Model)) + geom_col(position = "dodge") +
  geom_hline(yintercept = baseline_acc, linetype = 2) +
  geom_text(aes(label = value), position = position_dodge(0.9), vjust = -0.3, size = 3.2) +
  labs(title = "Hit/Flop Model Comparison", subtitle = "Dashed line = baseline accuracy",
       x = NULL, y = NULL, fill = NULL) + theme(legend.position = "bottom")
ggsave(paste0(PLOT_DIR, "pred_04_model_comparison.png"), p, width = 9, height = 5.5, dpi = 110, bg = "white")

## ---- 5. Save for the Shiny app -------------------------------------------
pb <- list(model = models[[best]], model_name = best, results = results,
           genres = levels(df$main_genre), languages = levels(df$language),
           defaults = lapply(df[, sapply(df, is.numeric)], median))
saveRDS(pb, paste0(CLEAN_DIR, "prediction.rds"))

## ---- 6. Demo prediction -------------------------------------------------
demo <- data.frame(log_budget = log10(150e6), runtime = 140,
                   main_genre = factor("Action", levels = pb$genres), num_genres = 3,
                   release_month = 5, release_year = 2015,
                   language = factor("en", levels = pb$languages),
                   n_companies = 4, n_keywords = 15, us_production = 1, has_homepage = 1)
pr <- predict(pb$model, demo, type = "prob")[, "Hit"]
cat(sprintf("\nDemo: $150M Action film, May release -> P(Hit) = %.1f%% -> %s\n",
            100 * pr, ifelse(pr >= 0.5, "CHALEGA (Hit)", "NAHI CHALEGA (Flop)")))
cat("Saved prediction bundle to", paste0(CLEAN_DIR, "prediction.rds"), "\n")
}
