# FitScope - NIRS mitochondrial oxidative capacity pipeline
#
# A thin Shiny front end over the three validated Rscripts in the repo root's
# cleaning_STEP/, analysis_STEP/, plotting_STEP/ (clean_nirs.R, analyse_nirs.R,
# plot_nirs.R). This app does not reimplement any pipeline logic - it copies
# the unmodified scripts into a working project folder, shells out to Rscript
# for each step, and displays the CSVs/PNGs the scripts already produce. See
# ../CLAUDE.md for the method and the guardrails a "converged fit" still has
# to pass.

suppressMessages({
  library(shiny)
  library(DT)
})

# shiny::runApp() sets the working directory to this file's folder for the
# duration of the app, so relative paths below are reliable.
source("R/pipeline_runner.R")

PIPELINE_ROOT   <- normalizePath("..", mustWork = TRUE)
DEFAULT_PROJECT <- normalizePath(file.path("..", "workspace"), mustWork = FALSE)

fmt_num <- function(x, digits = 3) ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))

ui <- fluidPage(
  title = "FitScope - NIRS oxidative capacity",
  tags$head(tags$style(HTML("
    .flag-bad  { color: #b3261e; font-weight: 600; }
    .flag-ok   { color: #1b6b3a; font-weight: 600; }
    .flag-warn { color: #a15c00; }
    pre.console { background:#0f172a; color:#d1d5db; padding:12px; border-radius:6px;
                  max-height:420px; overflow-y:auto; white-space:pre-wrap; font-size:12px; }
    .console-warning { color:#fca5a5; }
    .console-note    { color:#fcd34d; }
  "))),
  tags$div(
    style = "background:#0f1f2e; margin:-15px -15px 15px -15px; padding:18px 24px;",
    tags$img(src = "fitscope-logo-dark.png",
             alt = "FitScope — NIRS muscle oxidative capacity",
             style = "height:64px; max-width:100%;")
  ),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("Project"),
      textInput("project_dir", "Project directory", value = DEFAULT_PROJECT),
      actionButton("prep_project", "Prepare project folder", icon = icon("folder-plus")),
      helpText("Copies clean_nirs.R / analyse_nirs.R / plot_nirs.R into this ",
               "folder's cleaning_STEP/analysis_STEP/plotting_STEP if not already there. ",
               "Never overwrites a script you've edited."),
      tags$hr(),
      h4("Raw data"),
      fileInput("upload", "Upload a raw Oxysoft .xlsx export", accept = ".xlsx"),
      uiOutput("raw_file_picker"),
      tags$hr(),
      h4("Run"),
      actionButton("run_clean",   "1. Clean",   icon = icon("broom"),      width = "100%"),
      br(), br(),
      actionButton("run_analyse", "2. Analyse", icon = icon("chart-line"), width = "100%"),
      br(), br(),
      actionButton("run_plot",    "3. Plot",    icon = icon("image"),      width = "100%"),
      br(), br(),
      actionButton("run_all", "Run all 3 steps", icon = icon("play"), width = "100%",
                   class = "btn-primary"),
      tags$hr(),
      h4("View existing subject"),
      uiOutput("subject_picker"),
      tags$hr(),
      h4("R package check"),
      tableOutput("pkg_check")
    ),
    mainPanel(
      width = 9,
      tabsetPanel(
        id = "tabs",
        tabPanel("Console",
                 br(), htmlOutput("console")),
        tabPanel("QC report",
                 br(), DTOutput("qc_table")),
        tabPanel("Recovery fit (Tc)",
                 br(),
                 h4("Plausibility"),
                 uiOutput("plausibility"),
                 h4("Fit table"),
                 DTOutput("fit_table"),
                 h4("Figure 6 — mVO2 recovery fit"),
                 uiOutput("fig6_img")),
        tabPanel("Signal figures (1-5)",
                 br(), uiOutput("figs_gallery")),
        tabPanel("Output files",
                 br(), DTOutput("files_table"))
      )
    )
  )
)

server <- function(input, output, session) {

  state <- reactiveValues(log = "", subject_id = NULL, last_step = NULL)

  append_log <- function(header, res) {
    lines <- res$output
    isolate({
      state$log <- paste0(state$log, "\n\n### ", header, " ###\n", lines)
    })
  }

  current_project <- reactive(input$project_dir)

  observeEvent(input$prep_project, {
    dir.create(current_project(), recursive = TRUE, showWarnings = FALSE)
    copied <- ensure_project(current_project(), PIPELINE_ROOT)
    msg <- if (length(copied)) paste("Copied:", paste(copied, collapse = ", "))
           else "Project already has all three step scripts - nothing copied."
    state$log <- paste0(state$log, "\n\n### Prepare project ###\n", msg)
    showNotification(msg, type = "message")
  })

  output$raw_file_picker <- renderUI({
    input$prep_project; input$upload  # re-list after either
    files <- tryCatch(list_raw_files(current_project()), error = function(e) character(0))
    selectInput("raw_file", "Raw .xlsx in project root", choices = files)
  })

  observeEvent(input$upload, {
    req(input$upload)
    dir.create(current_project(), recursive = TRUE, showWarnings = FALSE)
    dest <- file.path(current_project(), input$upload$name)
    file.copy(input$upload$datapath, dest, overwrite = TRUE)
    showNotification(paste("Uploaded", input$upload$name, "into project root."), type = "message")
  })

  subject_from_raw <- reactive({
    req(input$raw_file)
    tools::file_path_sans_ext(input$raw_file)
  })

  output$subject_picker <- renderUI({
    input$run_clean; input$run_all
    subs <- tryCatch(list_cleaned_subjects(current_project()), error = function(e) character(0))
    selectInput("view_subject", "Cleaned subjects", choices = subs)
  })

  observeEvent(input$view_subject, {
    req(input$view_subject)
    state$subject_id <- input$view_subject
  })

  output$pkg_check <- renderTable({
    check_r_packages()
  }, striped = TRUE, spacing = "xs")

  do_clean <- function() {
    req(input$raw_file)
    res <- run_step("clean", input$raw_file, current_project())
    append_log("Clean", res)
    state$subject_id <- subject_from_raw()
    res
  }
  do_analyse <- function() {
    req(state$subject_id)
    res <- run_step("analyse", state$subject_id, current_project())
    append_log("Analyse", res)
    res
  }
  do_plot <- function() {
    req(state$subject_id)
    res <- run_step("plot", state$subject_id, current_project())
    append_log("Plot", res)
    res
  }

  observeEvent(input$run_clean,   { withProgress(message = "Cleaning...",   do_clean())   })
  observeEvent(input$run_analyse, { withProgress(message = "Analysing...",  do_analyse()) })
  observeEvent(input$run_plot,    { withProgress(message = "Plotting...",   do_plot())    })
  observeEvent(input$run_all, {
    withProgress(message = "Running full pipeline...", value = 0, {
      incProgress(0.05, detail = "clean")
      c1 <- do_clean()
      incProgress(0.4, detail = "analyse")
      if (isTRUE(c1$ok)) do_analyse()
      incProgress(0.4, detail = "plot")
      if (!is.null(state$subject_id)) do_plot()
      incProgress(0.15)
    })
  })

  output$console <- renderUI({
    lines <- strsplit(state$log, "\n")[[1]]
    spans <- lapply(lines, function(l) {
      cls <- if (grepl("^\\[WARNING\\]", l)) "console-warning"
             else if (grepl("^\\[NOTE\\]", l)) "console-note"
             else ""
      tags$span(class = cls, paste0(l, "\n"))
    })
    tags$pre(class = "console", spans)
  })

  fit_data <- reactive({
    req(state$subject_id)
    read_recovery_fit(current_project(), state$subject_id)
  })

  qc_data <- reactive({
    req(state$subject_id)
    read_qc_report(current_project(), state$subject_id)
  })

  output$qc_table <- renderDT({
    req(qc_data())
    datatable(qc_data(), options = list(pageLength = 10, dom = "t"))
  })

  output$fit_table <- renderDT({
    req(fit_data())
    d <- fit_data()
    num_cols <- c("Rest", "Delta", "End", "Tc", "k", "r_squared", "resting_mVO2", "beta")
    d[num_cols] <- lapply(d[num_cols], round, 4)
    datatable(d, options = list(pageLength = 10, dom = "t"))
  })

  output$plausibility <- renderUI({
    req(fit_data())
    d <- fit_data()
    primary <- d[d$signal == "HHb" & d$correction == "corrected", ]
    flags <- plausibility_flags(primary)
    tags$ul(lapply(flags, function(f) {
      cls <- if (grepl("negative|below 0.8|implausibly|outside the typical", f)) "flag-bad"
             else if (grepl("Tc = NA", f)) "flag-warn"
             else "flag-ok"
      tags$li(class = cls, f)
    }))
  })

  output$fig6_img <- renderUI({
    req(state$subject_id)
    f <- file.path(current_project(), "analysis_STEP",
                    paste0(state$subject_id, "_fig6_mvo2_recovery_fit.png"))
    if (!file.exists(f)) return(tags$p("Not generated yet - run Analyse."))
    tags$img(src = base64_img(f), style = "max-width:100%;")
  })

  output$figs_gallery <- renderUI({
    req(state$subject_id)
    names <- c("fig1_protocol_overview", "fig2_recovery_series", "fig3_cuff_magnification",
               "fig4_resting_occlusion", "fig5_probe_comparison")
    tagList(lapply(names, function(n) {
      f <- file.path(current_project(), "plotting_STEP", paste0(state$subject_id, "_", n, ".png"))
      if (!file.exists(f)) return(NULL)
      tagList(h5(n), tags$img(src = base64_img(f), style = "max-width:100%; margin-bottom:16px;"))
    }))
  })

  output$files_table <- renderDT({
    req(state$subject_id)
    dirs <- file.path(current_project(), c("cleaning_STEP", "analysis_STEP", "plotting_STEP"))
    files <- unlist(lapply(dirs, function(d) {
      if (!dir.exists(d)) return(character(0))
      f <- list.files(d, pattern = state$subject_id, full.names = TRUE)
      f[grepl(paste0("^", state$subject_id), basename(f))]
    }))
    if (!length(files)) return(datatable(data.frame(file = character(0))))
    info <- file.info(files)
    datatable(data.frame(file = sub(paste0(current_project(), "/"), "", files),
                          bytes = info$size, modified = format(info$mtime)),
              options = list(pageLength = 15, dom = "t"))
  })

  base64_img <- function(path) {
    ext <- tools::file_ext(path)
    raw <- readBin(path, "raw", file.info(path)$size)
    paste0("data:image/", ext, ";base64,", base64enc::base64encode(raw))
  }
}

shinyApp(ui, server)
