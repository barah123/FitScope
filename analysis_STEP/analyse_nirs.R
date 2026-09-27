#!/usr/bin/env Rscript
#
# analyse_nirs.R - mVO2 per occlusion and the monoexponential recovery fit
#
# Step 2 of 3. Consumes the output of cleaning_STEP/clean_nirs.R and produces
# the numbers behind the third row of Ryan 2014 Fig. 1.
#
#   1. For each occlusion, apply the blood-volume correction of Ryan et al.
#      2012 (Method 1):
#
#         dtHb  = dO2Hb + dHHb
#         beta  = mean over t of |dO2Hb| / (|dO2Hb| + |dHHb|)
#         dO2Hb_corrected = dO2Hb - dtHb * (1 - beta)
#         dHHb_corrected  = dHHb  - dtHb * beta
#
#   2. mVO2 = the slope of the (corrected) signal over the FIRST 3 s of the
#      occlusion. Ryan 2012 measured slopes over the first 3 s because beta is
#      stable there and drifts during the final 1-2 s of the cuff (their Fig. 5).
#
#   3. Fit the recovery series against time since exercise end (E1):
#
#         mVO2(t) = Rest + Delta * exp(-t / Tc)
#
#      Tc is the index of mitochondrial oxidative capacity; k = 1/Tc.
#      A smaller Tc (larger k) means faster recovery and greater capacity.
#
# Signals: HHb, O2Hb, tHb and TSI, each uncorrected and (where the correction
# applies) blood-volume corrected - Ryan 2014 Fig. 1 rows C/F/I/L.
#
# Also draws that figure: <id>_fig6_mvo2_recovery_fit.png, built directly from
# the results computed above (Ryan 2014 Fig. 1C/F/I/L, with the corrected /
# uncorrected pairing of Ryan 2012 Fig. 3E/F overlaid in each panel).
#
# Usage:  Rscript analysis_STEP/analyse_nirs.R "Practice12"

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(patchwork)
})

## ---- Paths ---------------------------------------------------------------
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
  stop(sprintf("No '%s' found - run cleaning_STEP/clean_nirs.R first", want))
}
rel <- function(p) sub(paste0("^", PROJECT_ROOT, "/"), "", p)

args       <- commandArgs(trailingOnly = TRUE)
subject_id <- tools::file_path_sans_ext(basename(if (length(args) >= 1) args[1] else "Practice12"))
CLEAN_DIR  <- find_clean_dir(subject_id)

## ---- Settings (Ryan defaults) --------------------------------------------
SLOPE_WINDOW_S <- 3     # Ryan 2012: slopes over the first 3 s of each occlusion
MIN_POINTS     <- 3     # fewer than this cannot support a slope
MIN_OCCLUSIONS <- 4     # a 3-parameter exponential needs more than 3 points

cleaned <- read_csv(file.path(CLEAN_DIR, paste0(subject_id, "_cleaned_1s.csv")),
                    show_col_types = FALSE)
occ     <- read_csv(file.path(CLEAN_DIR, paste0(subject_id, "_occlusion_windows.csv")),
                    show_col_types = FALSE)
events  <- read_csv(file.path(CLEAN_DIR, paste0(subject_id, "_events.csv")),
                    show_col_types = FALSE)

cleaned$TSI <- rowMeans(cbind(cleaned$TSI_rx1, cleaned$TSI_rx2), na.rm = TRUE)

t_E1 <- events$time_s[events$code == "E1"][1]
t_B1 <- events$time_s[events$code == "B1"][1]

cat("=== analyse_nirs.R :", subject_id, "===\n")
cat("Reading from :", rel(CLEAN_DIR), "\n")
cat("Writing to   :", rel(OUT_DIR), "\n")
cat(sprintf("Slope window : first %d s of each occlusion (Ryan 2012)\n", SLOPE_WINDOW_S))
cat(sprintf("Occlusions   : %d recovery cycles; exercise ends (E1) at %.0f s\n\n",
            nrow(occ), t_E1))

notes <- character(0)
note <- function(...) { m <- sprintf(...); notes <<- c(notes, m); cat("[NOTE] ", m, "\n", sep = "") }

## ---- Blood-volume correction ---------------------------------------------
# Returns the corrected deltas and the single beta for this occlusion. Note
# that corrected tHb is identically zero by construction (it is the sum of the
# two corrected signals) - that is the point of the correction, and Ryan 2012
# Fig. 3B/D shows exactly this flat line.
bv_correct <- function(o2, hh) {
  d_o2 <- o2 - o2[1]
  d_hh <- hh - hh[1]
  d_th <- d_o2 + d_hh
  bp   <- abs(d_o2) / (abs(d_o2) + abs(d_hh))
  beta <- mean(bp[-1], na.rm = TRUE)          # drop t = 0, where it is 0/0
  list(O2Hb = d_o2 - d_th * (1 - beta),
       HHb  = d_hh - d_th * beta,
       tHb  = (d_o2 - d_th * (1 - beta)) + (d_hh - d_th * beta),
       beta = beta)
}

# Sign convention: mVO2 is reported so that POSITIVE always means oxygen
# consumption. HHb rises during occlusion, O2Hb and TSI fall. tHb has no
# consumption interpretation - it is a control that should sit near zero.
SIGN <- c(HHb = 1, O2Hb = -1, tHb = 1, TSI = -1)

slope_of <- function(y, t) {
  if (length(y) < MIN_POINTS || all(is.na(y)) || sd(t) == 0) return(c(NA_real_, NA_real_))
  fit <- lm(y ~ t)
  c(unname(coef(fit)[2]), suppressWarnings(summary(fit)$r.squared))
}

## ---- mVO2 for one occlusion window ---------------------------------------
occlusion_mvo2 <- function(start_s, label, phase, id) {
  w <- cleaned %>% filter(time_s >= start_s, time_s <= start_s + SLOPE_WINDOW_S)
  if (nrow(w) < MIN_POINTS) return(NULL)
  t <- w$time_s - w$time_s[1]
  cc <- bv_correct(w$O2Hb, w$HHb)

  raw <- list(HHb = w$HHb - w$HHb[1], O2Hb = w$O2Hb - w$O2Hb[1],
              tHb = w$tHb - w$tHb[1], TSI = w$TSI - w$TSI[1])
  cor_ <- list(HHb = cc$HHb, O2Hb = cc$O2Hb, tHb = cc$tHb, TSI = NULL)

  rows <- list()
  for (sig in names(raw)) {
    for (corr in c("uncorrected", "corrected")) {
      y <- if (corr == "uncorrected") raw[[sig]] else cor_[[sig]]
      if (is.null(y)) next                     # TSI has no blood-volume correction
      sl <- slope_of(y, t)
      rows[[length(rows) + 1]] <- tibble(
        occlusion_id = id, phase = phase, occ_label = label,
        start_s = start_s,
        time_since_exercise_s = start_s - t_E1,
        signal = sig, correction = corr,
        slope = sl[1],
        mVO2 = SIGN[[sig]] * sl[1],
        beta = if (corr == "corrected") cc$beta else NA_real_,
        slope_r2 = sl[2], n_points = nrow(w))
    }
  }
  bind_rows(rows)
}

## ---- Run over the resting occlusion and the recovery series ---------------
all_rows <- list()

if (!is.na(t_B1)) {
  r <- occlusion_mvo2(t_B1, "rest_occlusion", "rest", 0L)
  if (!is.null(r)) { r$time_since_exercise_s <- NA_real_; all_rows[["rest"]] <- r }
} else note("No B1 marker - resting mVO2 not computed.")

for (i in seq_len(nrow(occ))) {
  r <- occlusion_mvo2(occ$occlusion_start_s[i], sprintf("occlusion_%02d", occ$cycle[i]),
                      "recovery", as.integer(occ$cycle[i]))
  if (!is.null(r)) all_rows[[paste0("occ", i)]] <- r
}

mvo2 <- bind_rows(all_rows)
stopifnot("No occlusions could be analysed" = nrow(mvo2) > 0)

npts <- unique(mvo2$n_points)
cat(sprintf("Slope fitted to %s point(s) per occlusion.\n", paste(npts, collapse = "/")))
if (max(npts) <= 4)
  note(paste0("Only %d point(s) per slope at this sampling rate. Ryan's 3 s window assumes ",
              "a higher sample rate; individual mVO2 values here carry wide uncertainty."),
       max(npts))

# The correction is meant to zero tHb - confirm it did.
ct <- mvo2 %>% filter(signal == "tHb", correction == "corrected")
if (nrow(ct) && max(abs(ct$slope), na.rm = TRUE) > 1e-8)
  note("Corrected tHb slope is not zero (max %.2e) - check the correction.",
       max(abs(ct$slope), na.rm = TRUE))

# After the correction, O2Hb and HHb carry the same information with opposite
# sign (corrected tHb is zero), so their mVO2 - and their time constant - must
# be identical. Ryan 2012 Fig. 3F shows exactly this (Tc = 125.5 s for both).
chk <- mvo2 %>% filter(correction == "corrected", signal %in% c("HHb", "O2Hb")) %>%
  select(occlusion_id, signal, mVO2) %>%
  pivot_wider(names_from = signal, values_from = mVO2)
if (nrow(chk)) {
  dmax <- max(abs(chk$HHb - chk$O2Hb), na.rm = TRUE)
  cat(sprintf("Check: corrected O2Hb and HHb mVO2 agree to %.1e (Ryan 2012 Fig. 3F) - %s\n",
              dmax, if (dmax < 1e-9) "as expected" else "UNEXPECTED, review the correction"))
}

## ---- Monoexponential recovery fit ----------------------------------------
fit_recovery <- function(d) {
  d <- d %>% filter(phase == "recovery", !is.na(mVO2), !is.na(time_since_exercise_s))
  out <- tibble(n_occlusions = nrow(d), converged = FALSE,
                Rest = NA_real_, Delta = NA_real_, End = NA_real_,
                Tc = NA_real_, k = NA_real_, r_squared = NA_real_, note = NA_character_)
  if (nrow(d) < MIN_OCCLUSIONS) {
    out$note <- sprintf("only %d usable occlusions (need >= %d)", nrow(d), MIN_OCCLUSIONS)
    return(out)
  }
  y <- d$mVO2; tt <- d$time_since_exercise_s
  # Corrected tHb is zero by construction, so there is nothing to fit; without
  # this guard nls happily returns a time constant fitted to rounding noise.
  if (max(abs(y), na.rm = TRUE) < 1e-9 || sd(y, na.rm = TRUE) < 1e-9) {
    out$note <- "series is zero/constant by construction - no decay to fit"
    return(out)
  }
  # Several starting time constants are tried because nls is start-sensitive;
  # the first that converges to a positive Tc is kept.
  for (tc0 in c(20, 40, 80, 160, diff(range(tt)) / 2)) {
    f <- tryCatch(
      nls(y ~ Rest + Delta * exp(-tt / Tc),
          start = list(Rest = min(y), Delta = max(y) - min(y), Tc = tc0),
          control = nls.control(maxiter = 500, warnOnly = FALSE)),
      error = function(e) NULL, warning = function(w) NULL)
    if (is.null(f)) next
    p <- coef(f)
    if (!all(is.finite(p)) || p[["Tc"]] <= 0) next
    r2 <- 1 - sum(resid(f)^2) / sum((y - mean(y))^2)
    return(tibble(n_occlusions = nrow(d), converged = TRUE,
                  Rest = p[["Rest"]], Delta = p[["Delta"]],
                  End = p[["Rest"]] + p[["Delta"]],
                  Tc = p[["Tc"]], k = 1 / p[["Tc"]], r_squared = r2,
                  note = NA_character_))
  }
  out$note <- "no convergence to a positive time constant"
  out
}

fits <- mvo2 %>%
  group_by(signal, correction) %>%
  group_modify(~ fit_recovery(.x)) %>%
  ungroup()

## ---- Resting mVO2 ---------------------------------------------------------
rest_tbl <- mvo2 %>% filter(phase == "rest") %>%
  select(signal, correction, resting_mVO2 = mVO2, beta)

## ---- Report ---------------------------------------------------------------
cat("\nResting mVO2 (from the B1 occlusion, same 3 s window):\n")
for (i in seq_len(nrow(rest_tbl)))
  cat(sprintf("  %-5s %-12s %+8.4f%s\n", rest_tbl$signal[i], rest_tbl$correction[i],
              rest_tbl$resting_mVO2[i],
              if (!is.na(rest_tbl$beta[i])) sprintf("   (beta = %.3f)", rest_tbl$beta[i]) else ""))

cat("\nMonoexponential recovery fit  mVO2(t) = Rest + Delta * exp(-t/Tc):\n")
cat(sprintf("  %-5s %-12s %5s %9s %9s %8s %8s  %s\n",
            "sig", "correction", "n", "Tc (s)", "k (1/s)", "Rest", "R2", "note"))
for (i in seq_len(nrow(fits))) {
  f <- fits[i, ]
  cat(sprintf("  %-5s %-12s %5d %9s %9s %8s %8s  %s\n",
              f$signal, f$correction, f$n_occlusions,
              if (is.na(f$Tc)) "NA" else sprintf("%.1f", f$Tc),
              if (is.na(f$k))  "NA" else sprintf("%.4f", f$k),
              if (is.na(f$Rest)) "NA" else sprintf("%.4f", f$Rest),
              if (is.na(f$r_squared)) "NA" else sprintf("%.3f", f$r_squared),
              ifelse(is.na(f$note), "", f$note)))
}

primary <- fits %>% filter(signal == "HHb", correction == "corrected")
cat("\nPrimary result (HHb, blood-volume corrected - Ryan's recommended signal):\n")
if (isTRUE(primary$converged)) {
  cat(sprintf("  Tc = %.1f s    k = %.4f s^-1    R2 = %.3f\n",
              primary$Tc, primary$k, primary$r_squared))
  if (primary$r_squared < 0.8)
    note("Recovery fit R2 = %.3f is below the 0.8-0.9 normally required before Tc is trusted.",
         primary$r_squared)
  if (primary$Tc < 10 || primary$Tc > 60)
    note("Tc = %.1f s falls outside the typical healthy-adult range of about 20-40 s.", primary$Tc)
  # A converged fit is not the same as a trustworthy one. These two checks catch
  # the case where nls has described a drift rather than a recovery, which can
  # still return a Tc that looks entirely normal.
  if (!is.na(primary$Rest) && primary$Rest < 0)
    note(paste0("Fitted resting mVO2 is %.4f - negative oxygen consumption is physiologically ",
                "impossible, so this Tc describes drift in the signal rather than a recovery. ",
                "Do not report it."), primary$Rest)
  if (!is.na(primary$End) && abs(primary$End) > 2)
    note(paste0("Fitted end-exercise mVO2 is %.2f, far outside the physiological range of about ",
                "0.3-0.6. The exponential is being stretched to fit a non-decaying series."),
         primary$End)
} else {
  cat("  Tc = NA - the recovery series does not fit a monoexponential decay.\n")
  mv <- mvo2 %>% filter(phase == "recovery", signal == "HHb", correction == "corrected")
  if (nrow(mv) > 1) {
    trend <- unname(coef(lm(mVO2 ~ time_since_exercise_s, mv))[2])
    cat(sprintf("  Recovery mVO2 trend over the series: %+.5f per s (%d of %d values positive)\n",
                trend, sum(mv$mVO2 > 0, na.rm = TRUE), nrow(mv)))
    if (trend >= 0)
      note(paste0("Recovery mVO2 does not decline over the series, so no time constant exists ",
                  "to fit. Check the delay between exercise end (E1) and the first recovery ",
                  "cuff - if it is long relative to a 20-40 s time constant, recovery is ",
                  "largely over before measurement begins."))
  }
}
gap <- occ$occlusion_start_s[1] - t_E1
if (!is.na(gap) && gap > 30)
  note("First recovery cuff is %.0f s after exercise end (E1) - roughly %.1f time constants at Tc = 30 s.",
       gap, gap / 30)


## ---- Figure: mVO2 per occlusion + recovery fit ----------------------------
# Ryan 2014 Fig. 1 row C/F/I/L. Drawn from the objects computed above, so it
# always matches the CSVs written alongside it.
MLAB <- c(HHb  = expression("mV"*O[2]*" ("*mu*"M HHb"%.%"s"^-1*")"),
          O2Hb = expression("mV"*O[2]*" ("*mu*"M O"[2]*"Hb"%.%"s"^-1*")"),
          tHb  = expression("tHb slope ("*mu*"M"%.%"s"^-1*")"),
          TSI  = expression("mV"*O[2]*" (TSI %"%.%"s"^-1*")"))
CORR_COL <- c(uncorrected = "grey45", corrected = "#C1272D")

fig_theme <- theme_classic(base_size = 9) +
  theme(axis.line = element_line(linewidth = 0.3),
        axis.ticks = element_line(linewidth = 0.3),
        plot.title = element_text(size = 9, face = "bold"),
        plot.subtitle = element_text(size = 7.5, colour = "grey35"),
        plot.margin = margin(2, 6, 2, 6))

mv_rec <- mvo2 %>% filter(phase == "recovery", !is.na(mVO2))

mvo2_panel <- function(sig) {
  d <- mv_rec %>% filter(signal == sig)
  if (!nrow(d)) return(NULL)
  # TSI has no corrected series. Give every panel both levels - as an unplotted
  # NA row where one is absent - so all four guides are structurally identical
  # and patchwork merges them into a single legend instead of one per shape.
  gap <- setdiff(c("uncorrected", "corrected"), unique(d$correction))
  if (length(gap))
    d <- bind_rows(d, tibble(correction = gap,
                             time_since_exercise_s = NA_real_, mVO2 = NA_real_))
  fs_all <- fits %>% filter(signal == sig)
  fs_ok  <- fs_all %>% filter(converged)
  curves <- NULL
  if (nrow(fs_ok)) {
    # na.rm: the panel data may carry an unplotted NA row added above to keep
    # the legends consistent.
    tg <- seq(min(d$time_since_exercise_s, na.rm = TRUE),
              max(d$time_since_exercise_s, na.rm = TRUE), length.out = 200)
    curves <- bind_rows(lapply(seq_len(nrow(fs_ok)), function(i)
      tibble(correction = fs_ok$correction[i], time_since_exercise_s = tg,
             mVO2 = fs_ok$Rest[i] + fs_ok$Delta[i] * exp(-tg / fs_ok$Tc[i]))))
  }
  cap <- paste(vapply(seq_len(nrow(fs_all)), function(i)
    sprintf("%s: %s", fs_all$correction[i],
            if (isTRUE(fs_all$converged[i]))
              sprintf("Tc = %.1f s, R\u00b2 = %.2f", fs_all$Tc[i], fs_all$r_squared[i])
            else "no fit"), character(1)), collapse = "   |   ")

  p <- ggplot(d, aes(time_since_exercise_s, mVO2, colour = correction)) +
    geom_hline(yintercept = 0, colour = "grey80", linewidth = 0.3)
  if (!is.null(curves))
    # show.legend = FALSE: only panels with a converged fit carry this layer, so
    # letting it into the guide gives patchwork three different legends to merge.
    p <- p + geom_line(data = curves, aes(colour = correction), linewidth = 0.55,
                       show.legend = FALSE)
  p + geom_point(aes(shape = correction), size = 1.6, na.rm = TRUE) +
    # Identical scale levels in every panel (TSI has no corrected variant), so
    # patchwork can collapse the guides into a single legend.
    scale_colour_manual(values = CORR_COL, name = NULL,
                        limits = c("uncorrected", "corrected"), drop = FALSE) +
    scale_shape_manual(values = c(uncorrected = 1, corrected = 16), name = NULL,
                       limits = c("uncorrected", "corrected"), drop = FALSE) +
    labs(x = "Time since end of exercise (s)", y = MLAB[[sig]], subtitle = cap) +
    fig_theme + theme(plot.subtitle = element_text(size = 6.5, colour = "grey30"))
}

f_fig <- NULL
panels <- Filter(Negate(is.null), lapply(c("HHb", "O2Hb", "tHb", "TSI"), mvo2_panel))
if (length(panels)) {
  sub <- if (isTRUE(primary$converged))
    sprintf("Primary (HHb, blood-volume corrected): Tc = %.1f s, k = %.4f s\u207b\u00b9, R\u00b2 = %.3f",
            primary$Tc, primary$k, primary$r_squared)
  else paste("Primary (HHb, blood-volume corrected): no converged fit -",
             "recovery mVO2 does not decay over the series")
  fig <- wrap_plots(panels, ncol = 2) + plot_layout(guides = "collect") &
    theme(legend.position = "top")
  fig <- fig + plot_annotation(
    title = sprintf("%s - mVO2 per occlusion and monoexponential recovery fit", subject_id),
    subtitle = paste0(sub, sprintf("\nSlope over the first %d s of each occlusion (Ryan 2012).",
                                   SLOPE_WINDOW_S)),
    theme = fig_theme)
  f_fig <- file.path(OUT_DIR, paste0(subject_id, "_fig6_mvo2_recovery_fit.png"))
  suppressWarnings(ggsave(f_fig, fig, width = 9, height = 7, dpi = 200))
}

## ---- Write ---------------------------------------------------------------
f_mvo2 <- file.path(OUT_DIR, paste0(subject_id, "_mvo2.csv"))
f_fit  <- file.path(OUT_DIR, paste0(subject_id, "_recovery_fit.csv"))
write_csv(mvo2, f_mvo2)
write_csv(fits %>% left_join(rest_tbl, by = c("signal", "correction")), f_fit)

cat("\nOutputs:\n")
cat(sprintf("  %-34s %d rows (occlusion x signal x correction)\n", basename(f_mvo2), nrow(mvo2)))
cat(sprintf("  %-34s %d rows (signal x correction)\n", basename(f_fit), nrow(fits)))
if (!is.null(f_fig))
  cat(sprintf("  %-34s Ryan 2014 Fig. 1C/F/I/L\n", basename(f_fig)))

if (length(notes)) {
  cat(sprintf("\n%d note(s):\n", length(notes)))
  for (n in notes) cat("  - ", n, "\n", sep = "")
}
cat("\nDone.\n")
