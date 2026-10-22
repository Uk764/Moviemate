# Movie Recommendation System & Hit/Flop Prediction (Big Data Analysis, R)

Mini project: build a movie recommendation system from OTT-style ratings data,
and predict whether a movie will be a hit or a flop ("chalega ya nahi chalega").

## Folder structure

```
movie_bda_project/
├── movie_bda_project.Rproj   <- DOUBLE-CLICK THIS to open the project
├── config.R                  <- settings (USE_BIG_DATA switch)
├── run_all.R                 <- runs everything in order
├── 00_setup.R                <- installs packages, checks data
├── 01_load.R                 <- loads data (fread vs read.csv speed test)
├── 02_clean.R                <- cleaning, filtering, feature engineering
├── 03_eda.R                  <- 9 EDA graphs
├── 04_recommender.R          <- Module A: recommender (5 models + hybrid)
├── 05_prediction.R           <- Module B: hit/flop (3 ML models)
├── app.R                     <- Shiny web app for the live demo
├── R/functions.R             <- recommendation helper functions
├── REPORT_NOTES.md           <- methodology, results, viva questions
└── data/
    ├── ml-latest-small/      <- included (100K ratings)
    ├── ml-25m/               <- NOT included (1.1 GB) - copy it in yourself
    └── tmdb_5000_movies.csv  <- included
```

Generated when you run the project: `data/clean/` (models), `plots/` (graphs), `outputs/` (result tables).

## How to run

1. Unzip the folder anywhere (for example, Documents).
2. Copy your `ml-25m` folder into `data/` (needed only for the big data run).
   Download link if you don't have it: https://files.grouplens.org/datasets/movielens/ml-25m.zip
3. Double-click `movie_bda_project.Rproj`. RStudio opens with the right working folder.
4. Open `run_all.R` and click **Source** (Ctrl + Shift + S).
   First time it installs packages (5-10 min). Then the pipeline takes ~1 minute.
5. Start the app in the Console:
   ```r
   shiny::runApp()
   ```
6. For the final big data run: open `config.R`, set `USE_BIG_DATA <- TRUE`, save,
   run `run_all.R` again (~6-10 min, needs ~4 GB free RAM), then `shiny::runApp()`.

## Data sources

- MovieLens 25M / small: https://grouplens.org/datasets/movielens/
- TMDB 5000 Movie Dataset: https://www.kaggle.com/datasets/tmdb/tmdb-movie-metadata
