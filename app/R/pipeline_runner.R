# pipeline_runner.R - shells out to the bundled Rscript pipeline and reports.
#
# The three scripts under the repo root's cleaning_STEP/, analysis_STEP/,
# plotting_STEP/ are unmodified copies of clean_nirs.R, analyse_nirs.R and
# plot_nirs.R. They self-locate relative to their own file and write outputs
# into their own folder (see ../CLAUDE.md) - so this runner never
# re-implements pipeline logic, it only invokes Rscript and reads back the
# CSVs/PNGs the scripts already produce.

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Run one pipeline step via Rscript, capturing combined stdout+stderr.
#'
#' @param step "clean", "analyse", or "plot"
#' @param arg the argument each script takes: a raw file path (clean) or a
#'   subject id (analyse, plot)
#' @param project_dir the working project directory - must contain (or will
#'   contain) cleaning_STEP/, analysis_STEP/, plotting_STEP/ as siblings, plus
#'   the raw .xlsx files at its root, exactly like the reference pipeline.
run_step <- function(step, arg, project_dir) {
  script <- switch(step,
    clean   = file.path(project_dir, "cleaning_STEP", "clean_nirs.R"),
    analyse = file.path(project_dir, "analysis_STEP", "analyse_nirs.R"),
    plot    = file.path(project_dir, "plotting_STEP", "plot_nirs.R"),
    stop("Unknown step: ", step)
  )
  if (!file.exists(script)) {
    return(list(ok = FALSE, status = 1L,
                output = sprintf("Script not found: %s\nRun ensure_project() first.", script)))
  }
  res <- tryCatch(
    system2("Rscript", shQuote(c(script, arg)), stdout = TRUE, stderr = TRUE),
    error = function(e) paste("Rscript failed to launch:", conditionMessage(e))
  )
  status <- attr(res, "status") %||% 0L
  list(ok = identical(status, 0L) || is.null(attr(res, "status")), status = status,
       output = paste(res, collapse = "\n"))
}

#' Copy the bundled, unmodified pipeline scripts into a project directory if
#' they are not already there. Never overwrites a script the user may have
#' customized - it only fills in what's missing. src_root is FitScope's own
#' repo root, passed in by app.R via PIPELINE_ROOT.
ensure_project <- function(project_dir, src_root) {
  dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)
  steps <- c("cleaning_STEP", "analysis_STEP", "plotting_STEP")
  copied <- character(0)
  for (s in steps) {
    dst_dir <- file.path(project_dir, s)
    dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
    for (f in list.files(file.path(src_root, s), pattern = "\\.R$", full.names = FALSE)) {
      dst <- file.path(dst_dir, f)
      if (!file.exists(dst)) {
        file.copy(file.path(src_root, s, f), dst)
        copied <- c(copied, file.path(s, f))
      }
    }
  }
  copied
}

#' Parse [WARNING]/[NOTE] lines out of captured Rscript output.
parse_flags <- function(output) {
  lines <- strsplit(output, "\n")[[1]]
  list(
    warnings = grep("^\\[WARNING\\]", lines, value = TRUE),
    notes    = grep("^\\[NOTE\\]",    lines, value = TRUE)
  )
}

#' Read back <id>_recovery_fit.csv if it exists.
read_recovery_fit <- function(project_dir, subject_id) {
  f <- file.path(project_dir, "analysis_STEP", paste0(subject_id, "_recovery_fit.csv"))
  if (!file.exists(f)) return(NULL)
  readr::read_csv(f, show_col_types = FALSE)
}

#' Read back <id>_qc_report.csv if it exists.
read_qc_report <- function(project_dir, subject_id) {
  f <- file.path(project_dir, "cleaning_STEP", paste0(subject_id, "_qc_report.csv"))
  if (!file.exists(f)) return(NULL)
  readr::read_csv(f, show_col_types = FALSE)
}

#' Plausibility flags on the primary result (HHb, blood-volume corrected),
#' mirroring analyse_nirs.R's own guards (never relax these - see
#' ../CLAUDE.md "Handling results that look wrong").
plausibility_flags <- function(fit_row) {
  if (is.null(fit_row) || nrow(fit_row) == 0) return("No fit row found.")
  flags <- character(0)
  if (isTRUE(fit_row$converged)) {
    if (!is.na(fit_row$r_squared) && fit_row$r_squared < 0.8)
      flags <- c(flags, sprintf("R^2 = %.3f is below 0.8 - fit quality is poor.", fit_row$r_squared))
    if (!is.na(fit_row$Rest) && fit_row$Rest < 0)
      flags <- c(flags, sprintf("Fitted resting mVO2 = %.4f is negative - not physiologically possible.", fit_row$Rest))
    if (!is.na(fit_row$End) && abs(fit_row$End) > 2)
      flags <- c(flags, sprintf("Fitted end-exercise value = %.3f is implausibly large (expect ~0.3-0.6).", fit_row$End))
    if (!is.na(fit_row$Tc) && (fit_row$Tc < 20 || fit_row$Tc > 60))
      flags <- c(flags, sprintf("Tc = %.1f s is outside the typical 20-60 s range.", fit_row$Tc))
    if (!length(flags)) flags <- "Converged fit passes all plausibility checks."
  } else {
    flags <- paste0("Tc = NA (no convergence). This can be a correct result about the protocol - e.g. ",
                     "recovery measurement starting too late relative to Tc - not a bug. Do not relax the fit to force a number.")
  }
  flags
}

#' List subject ids already cleaned in a project (have a *_cleaned_1s.csv).
list_cleaned_subjects <- function(project_dir) {
  f <- list.files(file.path(project_dir, "cleaning_STEP"), pattern = "_cleaned_1s\\.csv$")
  sub("_cleaned_1s\\.csv$", "", f)
}

#' List raw .xlsx files sitting at the project root.
list_raw_files <- function(project_dir) {
  list.files(project_dir, pattern = "\\.xlsx$", full.names = FALSE)
}

check_r_packages <- function() {
  need <- c("readxl", "dplyr", "tidyr", "readr", "ggplot2", "patchwork")
  have <- need %in% rownames(installed.packages())
  data.frame(package = need, installed = have)
}
