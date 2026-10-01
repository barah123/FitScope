#!/usr/bin/env Rscript
#
# plot_nirs.R - standard figures for a cleaned NIRS dataset
#
# Reads the output of clean_nirs.R and produces the figure set used in the
# source literature for this method:
#
#   Fig 1  Protocol overview - each signal across the whole recording with the
#          protocol phases shaded.   (Ryan 2012 Fig. 2; Ryan 2014 Fig. 1A,D,G,J)
#   Fig 2  Recovery series - the same signals over the post-exercise occlusion
#          window, occlusions shaded.          (Ryan 2012 Fig. 3A; Ryan 2014 Fig. 1B,E,H,K)
#   Fig 3  Cuff magnification - the final two occlusion/reperfusion cycles.
#                                                          (Ryan 2012 Fig. 3C,D)
#   Fig 4  Resting occlusion - the B1->C1 cuff, where O2Hb should fall and HHb
#          rise. The single clearest check that a recording is physiological.
#   Fig 5  Probe comparison - Rx1, Rx2 and the average they are combined into.
#
# The mVO2 / recovery-fit figure (Ryan 2014 Fig. 1C,F,I,L) is produced by the
# analysis step itself - see ../analysis_STEP/<id>_fig6_mvo2_recovery_fit.png.
#
# Usage:  Rscript plot_nirs.R "Practice12"
#         Rscript plot_nirs.R "Practice12.xlsx"     # extension is ignored

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(patchwork)
})


## ---- Paths ---------------------------------------------------------------
# Cleaned CSVs are read from cleaning_STEP/; figures are written next to this
# script. Works from the project root or from inside plotting_STEP/.
script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  m  <- grep("^--file=", ca, value = TRUE)
  if (!length(m)) return(normalizePath(".", mustWork = FALSE))
  f <- sub("^--file=", "", m[1])
  # Rscript encodes spaces in the script path as "~+~"; this project's path
  # contains spaces, so decode before using the path.
  f <- gsub("~\\+~", " ", f)
  normalizePath(dirname(f), mustWork = FALSE)
}
STEP_DIR     <- script_dir()
PROJECT_ROOT <- normalizePath(file.path(STEP_DIR, ".."), mustWork = FALSE)
OUT_DIR      <- STEP_DIR

find_clean_dir <- function(id) {
  want <- paste0(id, "_cleaned_1s.csv")
  for (d in c(file.path(PROJECT_ROOT, "cleaning_STEP"), PROJECT_ROOT, getwd()))
    if (file.exists(file.path(d, want))) return(normalizePath(d))
  stop(sprintf("No '%s' found - run clean_nirs.R first (looked in %s/cleaning_STEP)",
               want, PROJECT_ROOT))
}
rel <- function(p) sub(paste0("^", PROJECT_ROOT, "/"), "", p)

args <- commandArgs(trailingOnly = TRUE)
subject_id <- tools::file_path_sans_ext(basename(if (length(args) >= 1) args[1] else "Practice12"))

CLEAN_DIR <- find_clean_dir(subject_id)
f_clean <- file.path(CLEAN_DIR, paste0(subject_id, "_cleaned_1s.csv"))
f_occ   <- file.path(CLEAN_DIR, paste0(subject_id, "_occlusion_windows.csv"))
f_ev    <- file.path(CLEAN_DIR, paste0(subject_id, "_events.csv"))

cleaned <- read_csv(f_clean, show_col_types = FALSE)
events  <- if (file.exists(f_ev))  read_csv(f_ev,  show_col_types = FALSE) else tibble()
occ     <- if (file.exists(f_occ)) read_csv(f_occ, show_col_types = FALSE) else tibble()

cat("=== plot_nirs.R :", subject_id, "===\n")
cat("Reading from :", rel(CLEAN_DIR), "\n")
cat("Writing to   :", rel(OUT_DIR), "\n")
cat(sprintf("%d seconds of cleaned data, %d occlusion cycles\n\n", nrow(cleaned), nrow(occ)))

## ---- Style ---------------------------------------------------------------
# NIRS convention: O2Hb red, HHb blue, tHb dark grey, saturation green.
COL <- c(O2Hb = "#C1272D", HHb = "#1F5FA8", tHb = "#4D4D4D", TSI = "#1B7F5C")
LAB <- c(O2Hb = expression(Delta*"[O"[2]*"Hb] ("*mu*"M)"),
         HHb  = expression(Delta*"[HHb] ("*mu*"M)"),
         tHb  = expression(Delta*"[tHb] ("*mu*"M)"),
         TSI  = expression("TSI (%)"))

base_theme <- theme_classic(base_size = 9) +
  theme(axis.line = element_line(linewidth = 0.3),
        axis.ticks = element_line(linewidth = 0.3),
        plot.title = element_text(size = 9, face = "bold"),
        plot.subtitle = element_text(size = 7.5, colour = "grey35"),
        plot.margin = margin(2, 6, 2, 6))

# Phase shading, built from runs of the phase column.
phase_runs <- function(df) {
  r <- rle(ifelse(is.na(df$phase), "__na__", df$phase))
  ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1
  tibble(phase = r$values,
         xmin  = df$time_s[starts],
         xmax  = df$time_s[pmin(ends + 1, nrow(df))]) %>%
    filter(phase != "__na__")
}
PHASE_FILL <- c(baseline = "#F2F2F2", rest_occlusion = "#D9E4F0", reperfusion = "#FAF0E0",
                exercise = "#EFE3F2", post_exercise_gap = "#F7F7F7",
                recovery_series = "#E6F0E8", end = "#FAFAFA", post_study = "#FFFFFF")

# One signal panel over one time window.
sig_panel <- function(df, col, key, rects = NULL, rect_fill = "grey60", rect_alpha = 0.30,
                      phase_rect = NULL, show_x = FALSE, pts = FALSE) {
  d <- df %>% select(time_s, y = all_of(col)) %>% filter(!is.na(y))
  p <- ggplot(d, aes(time_s, y))
  if (!is.null(phase_rect) && nrow(phase_rect))
    p <- p + geom_rect(data = phase_rect, inherit.aes = FALSE,
                       aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = phase)) +
      scale_fill_manual(values = PHASE_FILL, guide = "none")
  if (!is.null(rects) && nrow(rects))
    p <- p + geom_rect(data = rects, inherit.aes = FALSE,
                       aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
                       fill = rect_fill, alpha = rect_alpha)
  p <- p + geom_line(colour = COL[[key]], linewidth = 0.42)
  if (pts) p <- p + geom_point(colour = COL[[key]], size = 0.5)
  p + labs(y = LAB[[key]], x = if (show_x) "Time (s)" else NULL) +
    scale_x_continuous(expand = expansion(mult = c(0.012, 0.005))) +
    base_theme +
    theme(axis.title.x = if (show_x) element_text() else element_blank(),
          axis.text.x  = if (show_x) element_text() else element_blank())
}

occ_rects <- function(w) if (!nrow(w)) NULL else
  tibble(xmin = w$occlusion_start_s, xmax = w$occlusion_end_s)

save_png <- function(p, suffix, w, h) {
  f <- file.path(OUT_DIR, paste0(subject_id, "_", suffix, ".png"))
  suppressWarnings(ggsave(f, p, width = w, height = h, dpi = 200))
  cat(sprintf("  %-44s %.0f x %.0f in\n", basename(f), w, h))
  invisible(f)
}

SIGS <- c("HHb", "O2Hb", "tHb")

## ---- Fig 1: protocol overview --------------------------------------------
pr <- phase_runs(cleaned)
ev_lab <- events %>% filter(!is.na(time_s))

panels <- lapply(seq_along(SIGS), function(i)
  sig_panel(cleaned, SIGS[i], SIGS[i], phase_rect = pr, show_x = FALSE))
tsi_panel <- sig_panel(cleaned %>% mutate(TSI = rowMeans(cbind(TSI_rx1, TSI_rx2), na.rm = TRUE)),
                       "TSI", "TSI", phase_rect = pr, show_x = TRUE)

# Event markers go on the top panel only, so the stack stays readable.
panels[[1]] <- panels[[1]] +
  geom_vline(data = ev_lab, aes(xintercept = time_s), colour = "grey35",
             linetype = "dashed", linewidth = 0.25) +
  geom_text(data = ev_lab, aes(x = time_s, y = Inf, label = code), inherit.aes = FALSE,
            vjust = 1.5, size = 2.2, colour = "grey20")

fig1 <- (panels[[1]] / panels[[2]] / panels[[3]] / tsi_panel) +
  plot_annotation(
    title = sprintf("%s - protocol overview", subject_id),
    subtitle = paste("Cleaned to 1 row/s; Tx1-3 averaged within probe, Rx1 and Rx2 averaged.",
                     "Shading = protocol phase, dashed = event marker."),
    theme = base_theme)
f1 <- save_png(fig1, "fig1_protocol_overview", 9, 7)

## ---- Fig 2: recovery occlusion series -------------------------------------
f2 <- NULL
if (nrow(occ)) {
  win <- cleaned %>% filter(phase == "recovery_series")
  rects <- occ_rects(occ)
  rp <- lapply(SIGS, function(s) sig_panel(win, s, s, rects = rects, rect_fill = "#C1272D"))
  rp[[4]] <- sig_panel(win %>% mutate(TSI = rowMeans(cbind(TSI_rx1, TSI_rx2), na.rm = TRUE)),
                       "TSI", "TSI", rects = rects, rect_fill = "#C1272D", show_x = TRUE)
  fig2 <- (rp[[1]] / rp[[2]] / rp[[3]] / rp[[4]]) +
    plot_annotation(
      title = sprintf("%s - post-exercise recovery occlusion series", subject_id),
      subtitle = sprintf("%d cycles of %s s occlusion (shaded) / %s s reperfusion, from the F1 marker",
                         nrow(occ), occ$occlusion_end_s[1] - occ$occlusion_start_s[1],
                         occ$reperfusion_end_s[1] - occ$reperfusion_start_s[1]),
      theme = base_theme)
  f2 <- save_png(fig2, "fig2_recovery_series", 9, 7)
}

## ---- Fig 3: magnification of the final two cuffs --------------------------
f3 <- NULL
if (nrow(occ) >= 2) {
  last2 <- tail(occ, 2)
  zwin <- cleaned %>% filter(time_s >= last2$occlusion_start_s[1] - 4,
                             time_s <= last2$reperfusion_end_s[nrow(last2)] + 4)
  rects <- occ_rects(last2)
  zp <- lapply(seq_along(SIGS), function(i)
    sig_panel(zwin, SIGS[i], SIGS[i], rects = rects, rect_fill = "#C1272D",
              show_x = (i == length(SIGS)), pts = TRUE))
  fig3 <- (zp[[1]] / zp[[2]] / zp[[3]]) +
    plot_annotation(
      title = sprintf("%s - final two occlusion/reperfusion cycles", subject_id),
      subtitle = "Shaded = occlusion. Points are individual 1-s samples - the resolution the slope is fitted to.",
      theme = base_theme)
  f3 <- save_png(fig3, "fig3_cuff_magnification", 7.5, 5.5)
}

## ---- Fig 4: resting occlusion ---------------------------------------------
f4 <- NULL
rest <- cleaned %>% filter(phase == "rest_occlusion")
if (nrow(rest) > 2) {
  pad <- cleaned %>% filter(time_s >= min(rest$time_s) - 10, time_s <= max(rest$time_s) + 10)
  rr <- tibble(xmin = min(rest$time_s), xmax = max(rest$time_s) + 1)
  r_cor <- suppressWarnings(cor(rest$O2Hb, rest$HHb))
  rp <- lapply(seq_along(SIGS), function(i)
    sig_panel(pad, SIGS[i], SIGS[i], rects = rr, rect_fill = "#1F5FA8",
              show_x = (i == length(SIGS)), pts = TRUE))
  fig4 <- (rp[[1]] / rp[[2]] / rp[[3]]) +
    plot_annotation(
      title = sprintf("%s - resting arterial occlusion (B1 to C1)", subject_id),
      subtitle = sprintf(paste("Expected during occlusion: O2Hb falls, HHb rises.",
                               "Combined O2Hb/HHb correlation r = %+.3f%s"),
                         r_cor, if (!is.na(r_cor) && r_cor > 0) "  <- positive, not expected" else ""),
      theme = base_theme)
  f4 <- save_png(fig4, "fig4_resting_occlusion", 7.5, 5.5)
}

## ---- Fig 5: probe comparison ----------------------------------------------
f5 <- NULL
if (all(c("O2Hb_rx1", "O2Hb_rx2") %in% names(cleaned))) {
  long <- cleaned %>%
    select(time_s, phase,
           O2Hb_Rx1 = O2Hb_rx1, O2Hb_Rx2 = O2Hb_rx2, O2Hb_Average = O2Hb,
           HHb_Rx1  = HHb_rx1,  HHb_Rx2  = HHb_rx2,  HHb_Average  = HHb) %>%
    pivot_longer(-c(time_s, phase), names_to = c("signal", "source"),
                 names_sep = "_", values_to = "value")
  mk <- function(sig) {
    d <- long %>% filter(signal == sig)
    ggplot(d, aes(time_s, value, colour = source, linewidth = source)) +
      geom_rect(data = pr, inherit.aes = FALSE,
                aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = phase)) +
      scale_fill_manual(values = PHASE_FILL, guide = "none") +
      geom_line() +
      scale_colour_manual(values = c(Rx1 = "#1F5FA8", Rx2 = "#C1272D", Average = "black"),
                          name = NULL) +
      scale_linewidth_manual(values = c(Rx1 = 0.35, Rx2 = 0.35, Average = 0.6), guide = "none") +
      labs(y = LAB[[sig]], x = "Time (s)") + base_theme +
      theme(legend.position = "top", legend.key.size = unit(0.4, "cm"))
  }
  fig5 <- (mk("O2Hb") / mk("HHb")) +
    plot_layout(guides = "collect") &
    theme(legend.position = "top")
  fig5 <- fig5 +
    plot_annotation(
      title = sprintf("%s - probe comparison", subject_id),
      subtitle = "Rx1 and Rx2 are averaged unconditionally into the analysis signal (black).",
      theme = base_theme)
  f5 <- save_png(fig5, "fig5_probe_comparison", 9, 6)
}


## ---- Combined sheet --------------------------------------------------------
# fig 1 (overview), fig 2 (recovery series) and fig 3 (cuff detail) on one sheet.
parts <- list(); hts <- c()
if (exists("fig1")) { parts <- c(parts, list(wrap_elements(fig1))); hts <- c(hts, 1.0) }
if (exists("fig2")) { parts <- c(parts, list(wrap_elements(fig2))); hts <- c(hts, 1.0) }
if (exists("fig3")) { parts <- c(parts, list(wrap_elements(fig3))); hts <- c(hts, 0.8) }
if (length(parts)) {
  combined <- Reduce(`/`, parts) + plot_layout(heights = hts)
  invisible(save_png(combined, "plots", 10, 4.6 * sum(hts)))
}

cat("\nDone.\n")
