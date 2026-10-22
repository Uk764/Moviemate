## =====================================================================
##  app.R  -  Shiny web app for the live demo
##  Run AFTER run_all.R:   shiny::runApp()
## =====================================================================
if (!file.exists("config.R")) stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)
source("config.R")
suppressPackageStartupMessages({
  library(shiny); library(DT); library(data.table); library(Matrix)
  library(recommenderlab); library(caret); library(randomForest); library(rpart)
})
source("R/functions.R")

need_file(paste0(CLEAN_DIR, "recommender.rds"), "Run run_all.R first (it builds the models).")
rb <- readRDS(paste0(CLEAN_DIR, "recommender.rds"))
pb_file <- paste0(CLEAN_DIR, "prediction.rds")
pb <- if (file.exists(pb_file)) readRDS(pb_file) else NULL

read_out <- function(f) { p <- paste0(OUT_DIR, f); if (file.exists(p)) fread(p) else data.table(note = "not generated yet") }
titles   <- rb$movies[order(-n_ratings), title]
user_ids <- sub("u", "", rownames(rb$rrm))
plot_files <- list.files(PLOT_DIR, pattern = "\\.png$")
lang_names <- c(en = "English", es = "Spanish", fr = "French", ja = "Japanese", de = "German",
                hi = "Hindi", zh = "Chinese", it = "Italian", other = "Other")

dt <- function(x, n = 10) datatable(x, rownames = FALSE, options = list(pageLength = n, dom = "tip", scrollX = TRUE))
img <- function(f) renderImage(list(src = file.path(PLOT_DIR, f), width = "100%"), deleteFile = FALSE)

## ---------------------------------------------------------------- UI ----
ui <- navbarPage(
  title = "Movie BDA: Recommend & Predict",
  header = tags$style(HTML("
    body{font-size:15px} .verdict{font-size:30px;font-weight:700;padding:18px;border-radius:10px;text-align:center}
    .hit{background:#E3F4E1;color:#2E7D32} .flop{background:#FBE4E4;color:#C62828}
    .note{color:#666;font-size:13px} .shiny-html-output{overflow-x:auto}")),

  tabPanel("Overview",
    fluidRow(
      column(4, h4("Dataset"), tableOutput("t_summary"),
             h4("Data reduction"), tableOutput("t_reduce"),
             h4("Rating matrix"), tableOutput("t_matrix"),
             h4("Load speed: base R vs data.table"), tableOutput("t_bench")),
      column(8, selectInput("plot", "Choose a graph", plot_files, width = "100%"), imageOutput("eda_img", height = "auto"))
    )),

  tabPanel("Recommend for a User",
    sidebarLayout(
      sidebarPanel(selectizeInput("uid", "User ID", choices = NULL),
                   sliderInput("n_user", "How many recommendations", 5, 20, 10),
                   p(class = "note", textOutput("model_used"))),
      mainPanel(h4("Recommended movies"), DTOutput("t_user_recs"),
                h4("Movies this user rated highest"), DTOutput("t_user_hist"))
    )),

  tabPanel("Movies Like This",
    sidebarLayout(
      sidebarPanel(selectizeInput("movie", "Pick a movie", choices = NULL),
                   radioButtons("method", "Method",
                                c("Hybrid (ratings + genres)" = "hybrid",
                                  "Collaborative (ratings only)" = "ratings",
                                  "Content-based (genres only)" = "genre")),
                   sliderInput("n_sim", "How many", 5, 20, 10)),
      mainPanel(h4(textOutput("sim_title")), DTOutput("t_similar"))
    )),

  tabPanel("New User (Cold Start)",
    sidebarLayout(
      sidebarPanel(selectizeInput("liked", "Pick 2-5 movies you liked", choices = NULL, multiple = TRUE),
                   p(class = "note", "A brand-new user has no rating history, so the recommender ",
                     "combines rating similarity and genre similarity to the movies you picked.")),
      mainPanel(h4("Recommended for you"), DTOutput("t_cold"))
    )),

  tabPanel("Hit or Flop?",
    if (is.null(pb)) h4("Prediction model not built - add data/tmdb_5000_movies.csv and run run_all.R") else
    sidebarLayout(
      sidebarPanel(
        numericInput("budget", "Budget (USD million)", 50, min = 0.1, max = 400, step = 1),
        sliderInput("runtime", "Runtime (minutes)", 70, 200, 110),
        selectInput("genre", "Main genre", pb$genres, selected = "Action"),
        sliderInput("ngen", "Number of genres", 1, 6, 3),
        selectInput("month", "Release month", setNames(1:12, month.name), selected = 5),
        sliderInput("year", "Release year", 1980, 2030, 2026, sep = ""),
        selectInput("lang", "Language", setNames(pb$languages, ifelse(pb$languages %in% names(lang_names),
                                                    lang_names[pb$languages], pb$languages))),
        sliderInput("ncomp", "Production companies", 0, 10, 3),
        sliderInput("nkw", "Number of plot keywords", 0, 40, 8),
        checkboxInput("us", "US production", TRUE),
        checkboxInput("home", "Has official website", TRUE)),
      mainPanel(uiOutput("verdict"),
                p(class = "note", "Hit = worldwide revenue at least 2x budget. Model: ",
                  pb$model_name, " trained on TMDB 5000 using only pre-release features."),
                br(), imageOutput("imp_img", height = "auto"))
    )),

  tabPanel("Model Results",
    fluidRow(
      column(6, h4("Recommender: rating accuracy"), tableOutput("t_rmse"),
             h4("Recommender: top-10 quality"), tableOutput("t_topn"),
             imageOutput("rec_cmp", height = "auto")),
      column(6, h4("Hit/Flop: test-set results"), tableOutput("t_pred"),
             imageOutput("pred_roc", height = "auto"))
    ))
)

## ------------------------------------------------------------ SERVER ----
server <- function(input, output, session) {
  updateSelectizeInput(session, "uid",   choices = user_ids, selected = user_ids[1], server = TRUE)
  updateSelectizeInput(session, "movie", choices = titles, selected = grep("^Toy Story \\(", titles, value = TRUE)[1], server = TRUE)
  updateSelectizeInput(session, "liked", choices = titles, server = TRUE,
                       options = list(maxItems = 5, placeholder = "Type a title..."))

  output$t_summary <- renderTable(read_out("data_summary.csv"))
  output$t_reduce  <- renderTable(read_out("data_reduction.csv"))
  output$t_matrix  <- renderTable(read_out("rating_matrix_info.csv"))
  output$t_bench   <- renderTable(read_out("load_benchmark.csv"))
  output$eda_img   <- renderImage(list(src = file.path(PLOT_DIR, input$plot), width = "100%"), deleteFile = FALSE)

  output$model_used  <- renderText(paste0("Model: ", rb$model_name, " trained on ", rb$mode,
                                          " (", nrow(rb$rrm), " users x ", ncol(rb$rrm), " movies)"))
  output$t_user_recs <- renderDT({ req(input$uid); dt(recommend_for_user(rb, input$uid, input$n_user), 20) })
  output$t_user_hist <- renderDT({ req(input$uid); dt(user_history(rb, input$uid, 10)) })

  sim <- reactive({ req(input$movie); similar_movies(rb, input$movie, input$n_sim, input$method) })
  output$sim_title <- renderText({ s <- sim(); if (is.null(s)) "Movie not found" else paste("Movies like", attr(s, "query_title")) })
  output$t_similar <- renderDT({ s <- sim(); req(s); dt(s[, .(title, genres, avg_rating, genre_sim, rating_sim, score)], 20) })

  output$t_cold <- renderDT({
    req(length(input$liked) >= 1)
    dt(recommend_from_liked(rb, input$liked, 15), 15)
  })

  if (!is.null(pb)) {
    output$verdict <- renderUI({
      nd <- data.frame(log_budget = log10(max(input$budget, 0.01) * 1e6), runtime = input$runtime,
                       main_genre = factor(input$genre, levels = pb$genres), num_genres = input$ngen,
                       release_month = as.integer(input$month), release_year = input$year,
                       language = factor(input$lang, levels = pb$languages),
                       n_companies = input$ncomp, n_keywords = input$nkw,
                       us_production = as.integer(input$us), has_homepage = as.integer(input$home))
      p_hit <- predict(pb$model, nd, type = "prob")[, "Hit"]
      hit <- p_hit >= 0.5
      div(class = paste("verdict", if (hit) "hit" else "flop"),
          if (hit) "CHALEGA! (Hit)" else "NAHI CHALEGA (Flop)", br(),
          span(style = "font-size:18px;font-weight:400", sprintf("Probability of hit: %.1f%%", 100 * p_hit)))
    })
    output$imp_img <- img("pred_03_feature_importance.png")
  }

  output$t_rmse   <- renderTable(read_out("recommender_rmse.csv"), digits = 3)
  output$t_topn   <- renderTable(read_out("recommender_topn.csv"), digits = 4)
  output$t_pred   <- renderTable(read_out("prediction_results.csv"), digits = 3)
  output$rec_cmp  <- img("rec_03_model_comparison.png")
  output$pred_roc <- img("pred_01_roc.png")
}

shinyApp(ui, server)
