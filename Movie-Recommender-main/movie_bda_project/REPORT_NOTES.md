# Report Notes - Movie Recommendation & Hit/Flop Prediction

Use this for the report, PPT and viva. Numbers below are from a test run; your
exact numbers can differ slightly (random sampling). Use the CSVs in `outputs/` from your own run.

## 1. Problem statement
1. Build a movie recommendation system using OTT-platform-style user rating data.
2. Predict whether a movie will be a Hit or a Flop before release.

## 2. Datasets
| Dataset | Size | Used for |
|---|---|---|
| MovieLens 25M | 25,000,095 ratings, 162,541 users, 62,423 movies | Recommender (big data) |
| MovieLens small | 100,836 ratings, 610 users, 9,742 movies | Fast testing |
| TMDB 5000 | 4,803 movies with budget, revenue, genres, cast info | Hit/Flop prediction |

## 3. Big data handling (why this is a Big Data project)
- **Fast loading:** `data.table::fread` (multi-threaded) vs base `read.csv` on 1M rows:
  0.12 s vs 1.64 s, about **13x faster**. Full 25M rows load in ~2 s.
- **Column selection:** only `userId, movieId, rating` are loaded (timestamp dropped) -> 381 MB in RAM.
- **Data reduction:** movies with < 50 ratings and users with < 20 ratings removed
  (25.0M -> 24.6M ratings, 59,047 -> 13,176 movies). Removes noise, keeps 98.6% of ratings.
- **Sparse matrix:** user x movie matrix is ~94% empty. Stored as a sparse matrix:
  7.3 MB instead of 72.9 MB dense (10x saving).
- **Sampling:** 5,000 users x top 2,000 movies used for model training so it runs on an 8 GB laptop.
- **Aggregation before plotting:** never plot 25M raw points; group first, then plot.

## 4. Module A - Recommender system
Models (package `recommenderlab`):
- **RANDOM** - random movies (lower baseline)
- **POPULAR** - most popular movies for everyone (strong baseline)
- **UBCF** - user-based collaborative filtering (similar users, Pearson, 50 neighbours)
- **IBCF** - item-based collaborative filtering (similar movies, 30 neighbours)
- **SVD** - matrix factorisation (20 latent factors)
- **Content-based** - cosine similarity on 19 genre columns
- **Hybrid** - 0.6 x rating similarity (adjusted cosine) + 0.4 x genre similarity
- **Cold start** - new user picks movies they liked, recommendations from hybrid similarity

Evaluation: 80% users train / 20% test; each test user gives 10 known ratings and the
model predicts the rest. A rating >= 4 counts as "liked".

Results (25M run):

| Model | RMSE | MAE | Precision@10 | Recall@10 |
|---|---|---|---|---|
| RANDOM | 1.870 | 1.528 | 0.035 | 0.005 |
| POPULAR | 0.894 | 0.680 | 0.337 | 0.078 |
| UBCF | 1.037 | 0.794 | 0.026 | 0.003 |
| IBCF | 1.060 | 0.765 | 0.162 | 0.030 |
| SVD | 0.891 | 0.677 | 0.108 | 0.023 |

Key findings:
- SVD has the best rating accuracy (lowest RMSE).
- POPULAR has the best precision: movie ratings have strong **popularity bias**,
  so popular movies are a hard baseline to beat. This is a known result in recommender research.
- UBCF is weak with only 10 known ratings per user: finding similar users needs more overlap (sparsity problem).
- Final app model = best personalised model by Precision@10 (chosen automatically).

## 5. Module B - Hit/Flop prediction
- **Target:** Hit if revenue >= 2 x budget (rule of thumb: ~half of box office goes to theatres,
  plus marketing costs). Data: 3,204 cleaned movies, 56% Hit / 44% Flop.
- **Features (pre-release only):** log budget, runtime, main genre, number of genres,
  release month, release year, language, number of production companies,
  number of plot keywords, US production, has official website.
- **Removed on purpose:** popularity, vote_average, vote_count - these exist only after
  release, so using them would be **data leakage**.
- **Models:** Logistic Regression, Decision Tree, Random Forest (5-fold cross-validation, 70/30 split).

| Model | Accuracy | Precision | Recall | F1 | AUC |
|---|---|---|---|---|---|
| Logistic Regression | 0.624 | 0.648 | 0.724 | 0.684 | 0.661 |
| Decision Tree | 0.609 | 0.644 | 0.681 | 0.662 | 0.635 |
| Random Forest | **0.647** | **0.667** | **0.743** | **0.703** | **0.687** |
| Baseline (majority) | 0.562 | - | - | - | 0.500 |

Random Forest beats the baseline by ~9 percentage points. Accuracy is moderate because
a movie's success depends on things not in the data (story quality, star cast, marketing,
competition, word of mouth). Most important features: release year, horror genre, number of keywords, budget.

## 6. Tools
R, data.table, recommenderlab, caret, randomForest, rpart, pROC, ggplot2, Shiny, DT.

## 7. Limitations & future scope
- Hit/Flop uses only 4,803 TMDB movies; add cast/director popularity and trailer views.
- Recommender trained on a 5,000-user sample; full data needs Spark (`sparklyr`) on a cluster.
- Add implicit feedback (watch time, clicks) like real OTT platforms.

## 8. Likely viva questions
1. **What is collaborative filtering?** Recommending using other users' behaviour: users who liked similar things before will like similar things again.
2. **UBCF vs IBCF?** UBCF finds similar users; IBCF finds similar movies. IBCF is more stable because movie similarities change less than user tastes.
3. **What is the cold-start problem?** A new user or new movie has no ratings, so collaborative filtering can't work. We solve it with content-based (genre) similarity.
4. **What is sparsity?** Most users rated very few movies, so ~94% of the user-movie matrix is empty.
5. **What is SVD here?** It compresses the rating matrix into 20 hidden "taste" factors per user and per movie.
6. **RMSE vs Precision@10?** RMSE = how close predicted ratings are to real ones. Precision@10 = of the 10 movies recommended, how many the user actually liked.
7. **Why did POPULAR win precision?** Popularity bias: most users rate well-known movies highly.
8. **What is data leakage?** Using information that wouldn't be available at prediction time. Votes and popularity come after release, so they were excluded.
9. **Why Random Forest?** Many decision trees on random subsets of data and features, then majority vote: less overfitting than a single tree.
10. **What is AUC?** Area under the ROC curve: probability that the model ranks a random hit above a random flop. 0.5 = random, 1 = perfect.
11. **Why fread?** It is multi-threaded and written in C; 13x faster than read.csv on our data.
12. **Why log of budget?** Budgets range from $10K to $380M; the log scale reduces the effect of extreme values.
