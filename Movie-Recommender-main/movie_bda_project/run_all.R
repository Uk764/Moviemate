## =====================================================================
##  run_all.R  -  runs the WHOLE project in the right order
if (!file.exists("config.R")) {
  here <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)), error = function(e) NA)
  if (!is.na(here) && file.exists(file.path(here, "config.R"))) setwd(here) else
    stop("Wrong folder. Double-click movie_bda_project.Rproj to open the project, then run again.", call. = FALSE)
}
cat("Working folder:", getwd(), "\n")

t0 <- Sys.time()
timings <- data.frame(script = character(), seconds = numeric())
run <- function(f) {
  s <- Sys.time()
  source(f, echo = FALSE)
  timings[nrow(timings) + 1, ] <<- list(f, round(as.numeric(difftime(Sys.time(), s, units = "secs")), 1))
}

run("00_setup.R")
run("02_clean.R")        # also runs 01_load.R
run("03_eda.R")
run("04_recommender.R")
run("05_prediction.R")

cat("\n========== ALL DONE ==========\n")
print(timings)
cat(sprintf("Total time: %.1f minutes\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("Graphs  -> plots/\nTables  -> outputs/\nModels  -> data/clean/\n")
cat("\nStart the web app with:   shiny::runApp()\n")
