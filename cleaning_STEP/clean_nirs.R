#!/usr/bin/env Rscript
#
# clean_nirs.R - Artinis Oxysoft export -> cleaned, analysis-ready dataset
#
# Implements the cleaning procedure specified by C. Ortega-Santos, as recorded in
# data_cleaning_transcript.md and NIRS_Pipeline_Questions_and_Challenges.docx:
#
#   Step 1  Delete every row above the A1 baseline marker (Event column).
#   Step 2  Convert Hz -> seconds: average every <sample_rate> rows into one row,
#           so one output row = one second. Everything downstream is in seconds.
#   Step 3  Check signal quality: TSI Fit Factor (Rx1, Rx2) should be >= 95.
#   Step 4  Average the three transmitter distances within each probe
#           (O2Hb, HHb, tHb, HbDiff), then average Rx1 and Rx2 into one signal.
#   Step 5  Label protocol phases from the event codes, and split the recovery
#           series into alternating 8 s occlusion / 8 s reperfusion blocks.
#
# Usage:  Rscript clean_nirs.R "Practice12.xlsx"
#         Rscript clean_nirs.R                     # defaults to Practice12.xlsx

suppressMessages({
  library(readxl)
  library(dplyr)
  library(readr)
})


## ---- Paths ---------------------------------------------------------------
# The script resolves its own location, so it behaves the same whether it is
# run from the project root ("Rscript cleaning_STEP/clean_nirs.R ...") or from
# inside cleaning_STEP/. Raw exports live in the project root; every output is
# written next to this script.
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

resolve_raw <- function(f) {
  for (cand in c(f, file.path(PROJECT_ROOT, f), file.path(getwd(), f)))
    if (file.exists(cand)) return(normalizePath(cand))
  stop(sprintf("Raw export not found: '%s' (looked in the working directory and in %s)",
               f, PROJECT_ROOT))
}
out_path <- function(...) file.path(OUT_DIR, ...)
rel <- function(p) sub(paste0("^", PROJECT_ROOT, "/"), "", p)

args       <- commandArgs(trailingOnly = TRUE)
raw_file   <- resolve_raw(if (length(args) >= 1) args[1] else "Practice12.xlsx")
subject_id <- tools::file_path_sans_ext(basename(raw_file))
sheet_name <- "Export 1"

# Protocol constants (per the data owner's annotation of the study design)
OCCLUSION_S    <- 8     # each recovery occlusion
REPERFUSION_S  <- 8     # each recovery reperfusion
RECOVERY_MAX_S <- 180   # nominal length of the recovery series (3 minutes)
FIT_FACTOR_MIN <- 95    # TSI Fit Factor quality threshold

# Nominal phase durations, used for reporting only - a deviation is flagged,
# never corrected or enforced.
PHASE_TARGETS <- c("A1->B1" = 120, "B1->C1" = 30, "D1->E1" = 60, "F1->G1" = 180)

warnings_log <- character(0)
warn <- function(...) {
  msg <- sprintf(...)
  warnings_log <<- c(warnings_log, msg)
  cat("[WARNING] ", msg, "\n", sep = "")
}

cat("=== clean_nirs.R :", basename(raw_file), "===\n")
cat("Output folder:", rel(OUT_DIR), "\n\n")

## ---- Parse metadata ---------------------------------------------------
meta <- read_excel(raw_file, sheet = sheet_name, range = "A1:C33",
                   col_names = c("key", "value", "unit"))
get_meta <- function(key) meta$value[which(!is.na(meta$key) & meta$key == key)[1]]

sample_rate <- as.numeric(get_meta("Data file sample rate"))
n_samples   <- as.integer(get_meta("Data file total number of samples"))
duration_s  <- as.numeric(get_meta("Data file duration"))

stopifnot("Could not read sample rate from the metadata block" = !is.na(sample_rate),
          "Could not read sample count from the metadata block" = !is.na(n_samples))

# The sample rate is read per file, never assumed: these exports are not all 10 Hz.
rows_per_second <- round(sample_rate)
cat(sprintf("Sample rate : %g Hz  (%d raw row(s) = 1 second)\n", sample_rate, rows_per_second))
cat(sprintf("Samples     : %d  (%.1f s)\n", n_samples, duration_s))

## ---- Parse the column legend ------------------------------------------
# The legend maps column number -> what that column measures. Parsed from the
# file rather than hardcoded so a differently-laid-out export fails loudly
# instead of being silently mis-read.
legend <- read_excel(raw_file, sheet = sheet_name, range = "A34:B70",
                     col_names = c("id", "name")) %>%
  filter(!is.na(id), !is.na(name), grepl("^[0-9]+$", trimws(as.character(id))))
legend$id <- as.integer(legend$id)

run_len <- 0
for (i in seq_len(nrow(legend))) if (legend$id[i] == i) run_len <- i else break
legend <- legend[seq_len(run_len), ]
n_cols <- nrow(legend)

stopifnot("Legend did not parse - check the raw file's row layout" =
            n_cols > 0 && all(legend$id == seq_len(n_cols)))

event_col <- legend$name[grepl("Event", legend$name, ignore.case = TRUE)]
stopifnot("No Event column found in the legend" = length(event_col) == 1)
cat(sprintf("Legend      : %d columns parsed\n\n", n_cols))

## ---- Load the data table ------------------------------------------------
excel_col <- function(n) {
  s <- ""
  while (n > 0) { r <- (n - 1) %% 26; s <- paste0(LETTERS[r + 1], s); n <- (n - r - 1) %/% 26 }
  s
}

# The header row is the row of literal column numbers (1, 2, 3, ...) just above
# the data. Located by scanning rather than assumed, for the same reason.
probe <- read_excel(raw_file, sheet = sheet_name, range = "A60:A80",
                    col_names = "v", col_types = "text")
hdr <- 59 + which(trimws(probe$v) == "1")[1]
stopifnot("Could not locate the numeric header row" = !is.na(hdr))

raw <- suppressMessages(read_excel(
  raw_file, sheet = sheet_name,
  range = paste0("A", hdr + 1, ":", excel_col(n_cols), hdr + n_samples),
  col_names = FALSE,
  col_types = c(rep("numeric", n_cols - 1), "text")))
names(raw) <- legend$name
raw$.sample <- raw[[1]]                       # column 1 is the sample number
raw$.t_raw  <- raw$.sample / sample_rate
raw$.event <- trimws(raw[[event_col]])
raw$.event[!nzchar(raw$.event)] <- NA_character_

cat(sprintf("Loaded      : %d rows x %d columns\n\n", nrow(raw), ncol(raw)))

# Look up a signal column by (probe, transmitter, signal) rather than rebuilding
# the legend string: the parenthetical suffix echoes the file name and is not
# always spelled the same as the file (e.g. "(Pracice12)" in Practice12.xlsx).
find_col <- function(df, rx, tx, signal) {
  hits <- names(df)[grepl(paste0("^", rx, " - ", tx, " ", signal, " "), names(df))]
  stopifnot("Signal column lookup was ambiguous or missing" = length(hits) == 1)
  df[[hits]]
}
find_one <- function(df, pattern) {
  hits <- names(df)[grepl(pattern, names(df))]
  stopifnot("Column lookup was ambiguous or missing" = length(hits) == 1)
  df[[hits]]
}

## ---- Events -------------------------------------------------------------
CANONICAL <- c("A1", "B1", "C1", "D1", "E1", "F1", "G1", "H1")

events_raw <- raw %>%
  filter(!is.na(.event)) %>%
  transmute(code = .event, sample = .sample, t_raw = .t_raw)

cat("Events in file:\n")
print(as.data.frame(events_raw), row.names = FALSE)
cat("\n")

stopifnot("No A1 marker found - cannot establish the start of the recording" =
            "A1" %in% events_raw$code)

missing_codes <- setdiff(CANONICAL, events_raw$code)
extra_codes   <- setdiff(events_raw$code, CANONICAL)
if (length(missing_codes))
  warn("Missing expected event code(s): %s", paste(missing_codes, collapse = ", "))
if (length(extra_codes))
  warn("Unexpected event code(s) present - confirm the marker convention for this session: %s",
       paste(extra_codes, collapse = ", "))
if (any(duplicated(events_raw$code)))
  warn("Duplicate event code(s): %s",
       paste(unique(events_raw$code[duplicated(events_raw$code)]), collapse = ", "))

## ---- Step 1: trim everything above A1 -----------------------------------
sample_A1 <- events_raw$sample[events_raw$code == "A1"][1]
t_A1_raw  <- sample_A1 / sample_rate
n_before  <- sum(raw$.sample < sample_A1)

trimmed <- raw %>% filter(.sample >= sample_A1)
cat(sprintf("Step 1  Trimmed %d row(s) above A1; %d row(s) remain (A1 is now t = 0 s).\n",
            n_before, nrow(trimmed)))

# All times are expressed as seconds since A1 from here on.
trimmed$.second <- (trimmed$.sample - sample_A1) %/% rows_per_second
ev <- events_raw %>%
  mutate(time_s = (sample - sample_A1) %/% rows_per_second) %>%
  select(code, sample, time_s)
ev_time <- function(code) { v <- ev$time_s[ev$code == code]; if (length(v)) v[1] else NA_real_ }

## ---- Step 2: Hz -> seconds (average every <rows_per_second> rows) -------
# Blocks are anchored at A1 (computed above from integer sample offsets, so the
# boundaries are exact), meaning block 0 is the first second of the baseline.
signal_cols <- legend$name[-c(1, n_cols)]   # drop sample number and Event

per_second <- trimmed %>%
  group_by(time_s = .second) %>%
  summarise(across(all_of(signal_cols), ~ mean(.x, na.rm = TRUE)),
            n_raw = n(), .groups = "drop") %>%
  arrange(time_s)

short_blocks <- sum(per_second$n_raw != rows_per_second)
cat(sprintf("Step 2  Averaged %d raw rows into %d one-second rows.\n",
            nrow(trimmed), nrow(per_second)))
if (short_blocks > 0)
  cat(sprintf("        (%d block(s) hold fewer than %d raw rows - see n_raw; normally just the last block)\n",
              short_blocks, rows_per_second))

## ---- Step 3: signal quality (TSI Fit Factor >= 95) ----------------------
ff_rx1  <- find_one(per_second, "^Rx1 - .*TSI Fit Factor")
ff_rx2  <- find_one(per_second, "^Rx2 - .*TSI Fit Factor")
tsi_rx1 <- find_one(per_second, "^Rx1 - .*TSI% ")
tsi_rx2 <- find_one(per_second, "^Rx2 - .*TSI% ")

cat("\nStep 3  Signal quality (TSI Fit Factor, threshold >= 95):\n")
qc_rows <- list()
for (p in list(list("Rx1", ff_rx1, tsi_rx1), list("Rx2", ff_rx2, tsi_rx2))) {
  nm <- p[[1]]; ff <- p[[2]]; tsi <- p[[3]]
  below <- sum(ff < FIT_FACTOR_MIN, na.rm = TRUE)
  cat(sprintf("        %s  Fit Factor min %.2f / median %.2f   TSI%% median %.1f%%   (%d s below %d)\n",
              nm, min(ff, na.rm = TRUE), median(ff, na.rm = TRUE),
              median(tsi, na.rm = TRUE), below, FIT_FACTOR_MIN))
  if (below > 0)
    warn("%s TSI Fit Factor drops below %d for %d second(s) of the recording.",
         nm, FIT_FACTOR_MIN, below)
  qc_rows[[nm]] <- tibble(probe = nm,
                          fit_factor_min = min(ff, na.rm = TRUE),
                          fit_factor_median = median(ff, na.rm = TRUE),
                          seconds_below_threshold = below,
                          tsi_pct_median = median(tsi, na.rm = TRUE))
}

## ---- Step 4: average Tx1/Tx2/Tx3, then average Rx1 and Rx2 --------------
TX <- list(Rx1 = c("Tx1a", "Tx2a", "Tx3a"), Rx2 = c("Tx1b", "Tx2b", "Tx3b"))
SIGNALS <- c("O2Hb", "HHb", "tHb", "HbDiff")

probe_mean <- function(signal, rx)
  rowMeans(sapply(TX[[rx]], function(tx) find_col(per_second, rx, tx, signal)), na.rm = TRUE)

# Per-probe Tx-averages are kept alongside the combined signal. The analysis
# signal is still the unconditional Rx1/Rx2 mean; these columns exist so the
# probe QC reported below can be seen rather than taken on trust.
by_probe <- list(Rx1 = lapply(SIGNALS, probe_mean, rx = "Rx1"),
                 Rx2 = lapply(SIGNALS, probe_mean, rx = "Rx2"))
by_probe <- lapply(by_probe, setNames, SIGNALS)

muscle <- lapply(SIGNALS, function(s) {
  rowMeans(cbind(by_probe$Rx1[[s]], by_probe$Rx2[[s]]), na.rm = TRUE)
})
names(muscle) <- SIGNALS

cat("\nStep 4  Averaged Tx1/Tx2/Tx3 within each probe, then averaged Rx1 and Rx2.\n")
cat("        Both probes are combined unconditionally, as specified.\n")

# Informational only - reported, never acted on. During a true arterial
# occlusion O2Hb and HHb move in opposite directions, so a positive correlation
# here is worth checking against the session notes before the values are used.
t_B1 <- ev_time("B1"); t_C1 <- ev_time("C1")
if (!is.na(t_B1) && !is.na(t_C1)) {
  in_rest <- per_second$time_s >= t_B1 & per_second$time_s <= t_C1
  for (rx in names(TX)) {
    r <- suppressWarnings(cor(by_probe[[rx]]$O2Hb[in_rest], by_probe[[rx]]$HHb[in_rest]))
    qc_rows[[rx]]$o2hb_hhb_cor_rest <- r
    cat(sprintf("        %s O2Hb/HHb correlation during the resting occlusion: r = %+.3f%s\n",
                rx, r, if (!is.na(r) && r > 0) "  <- positive; expected negative" else ""))
    if (!is.na(r) && r > 0)
      warn(paste0("%s shows a POSITIVE O2Hb/HHb correlation during the resting occlusion ",
                  "(r = %+.3f). Both probes are still averaged as specified, but this probe's ",
                  "signal does not behave like oxygen consumption - check placement/coupling ",
                  "for this session before reporting results."), rx, r)
  }
}

## ---- Step 5: phase labels ------------------------------------------------
PHASES <- tribble(
  ~from, ~to,  ~label,
  "A1",  "B1", "baseline",
  "B1",  "C1", "rest_occlusion",
  "C1",  "D1", "reperfusion",
  "D1",  "E1", "exercise",
  "E1",  "F1", "post_exercise_gap",
  "F1",  "G1", "recovery_series",
  "G1",  "H1", "end"
)

phase <- rep(NA_character_, nrow(per_second))
for (i in seq_len(nrow(PHASES))) {
  a <- ev_time(PHASES$from[i]); b <- ev_time(PHASES$to[i])
  if (is.na(a)) next
  # An absent closing marker leaves the phase running to the end of the file.
  b <- if (is.na(b)) max(per_second$time_s) + 1 else b
  phase[per_second$time_s >= a & per_second$time_s < b] <- PHASES$label[i]
}
phase[per_second$time_s >= (if (is.na(ev_time("H1"))) Inf else ev_time("H1"))] <- "post_study"

## ---- Step 5b: 8 s occlusion / 8 s reperfusion across the recovery series -
t_F1 <- ev_time("F1"); t_G1 <- ev_time("G1")
occ_label <- rep(NA_character_, nrow(per_second))
occ_windows <- tibble()

if (is.na(t_F1)) {
  warn("No F1 marker - the recovery occlusion series could not be labelled.")
} else {
  series_end <- min(c(if (is.na(t_G1)) Inf else t_G1,
                      t_F1 + RECOVERY_MAX_S,
                      max(per_second$time_s) + 1))
  window_s <- series_end - t_F1
  cycle_s  <- OCCLUSION_S + REPERFUSION_S
  n_cycles <- floor(window_s / cycle_s)

  rows <- list()
  for (k in seq_len(n_cycles)) {
    o_start <- t_F1 + (k - 1) * cycle_s
    r_start <- o_start + OCCLUSION_S
    occ_label[per_second$time_s >= o_start & per_second$time_s < r_start] <-
      sprintf("occlusion_%02d", k)
    occ_label[per_second$time_s >= r_start & per_second$time_s < r_start + REPERFUSION_S] <-
      sprintf("reperfusion_%02d", k)
    rows[[length(rows) + 1]] <- tibble(
      cycle = k,
      occlusion_start_s = o_start, occlusion_end_s = r_start,
      reperfusion_start_s = r_start, reperfusion_end_s = r_start + REPERFUSION_S)
  }
  occ_windows <- bind_rows(rows)
  leftover <- window_s - n_cycles * cycle_s

  cat(sprintf("\nStep 5  Recovery series F1->%s = %.0f s -> %d complete %d s/%d s cycles",
              if (is.na(t_G1)) "end" else "G1", window_s, n_cycles, OCCLUSION_S, REPERFUSION_S))
  cat(sprintf(" (%.0f s left over)\n", leftover))

  if (!is.na(t_G1) && abs((t_G1 - t_F1) - RECOVERY_MAX_S) > 10)
    warn("Recovery series F1->G1 is %.0f s, not the nominal %d s. The 8 s/8 s pattern was applied across %.0f s.",
         t_G1 - t_F1, RECOVERY_MAX_S, window_s)
}

## ---- Assemble the cleaned table ------------------------------------------
cleaned <- tibble(
  time_s      = per_second$time_s,
  phase       = phase,
  occ_label   = occ_label,
  O2Hb        = muscle$O2Hb,
  HHb         = muscle$HHb,
  tHb         = muscle$tHb,
  HbDiff      = muscle$HbDiff,
  O2Hb_rx1    = by_probe$Rx1$O2Hb,
  O2Hb_rx2    = by_probe$Rx2$O2Hb,
  HHb_rx1     = by_probe$Rx1$HHb,
  HHb_rx2     = by_probe$Rx2$HHb,
  tHb_rx1     = by_probe$Rx1$tHb,
  tHb_rx2     = by_probe$Rx2$tHb,
  TSI_rx1     = tsi_rx1,
  TSI_rx2     = tsi_rx2,
  FitFactor_rx1 = ff_rx1,
  FitFactor_rx2 = ff_rx2,
  n_raw       = per_second$n_raw
)

## ---- Phase duration report ----------------------------------------------
cat("\nPhase durations (nominal in brackets; deviations are reported, not corrected):\n")
dur_rows <- list()
for (i in seq_len(nrow(PHASES))) {
  a <- ev_time(PHASES$from[i]); b <- ev_time(PHASES$to[i])
  if (is.na(a) || is.na(b)) next
  key <- paste0(PHASES$from[i], "->", PHASES$to[i])
  tgt <- unname(PHASE_TARGETS[key])
  cat(sprintf("  %-9s %-18s %6.0f s   [%s]\n", key, PHASES$label[i], b - a,
              if (is.na(tgt)) "-" else sprintf("%d", tgt)))
  if (!is.na(tgt) && abs((b - a) - tgt) > 10)
    warn("%s (%s) is %.0f s, nominal %d s.", key, PHASES$label[i], b - a, tgt)
  dur_rows[[key]] <- tibble(interval = key, phase = PHASES$label[i],
                            duration_s = b - a, nominal_s = tgt)
}

## ---- Write outputs --------------------------------------------------------
f_clean <- out_path(paste0(subject_id, "_cleaned_1s.csv"))
f_occ   <- out_path(paste0(subject_id, "_occlusion_windows.csv"))
f_ev    <- out_path(paste0(subject_id, "_events.csv"))
f_qc    <- out_path(paste0(subject_id, "_qc_report.csv"))

write_csv(cleaned, f_clean)
if (nrow(occ_windows)) write_csv(occ_windows, f_occ)
write_csv(ev, f_ev)
write_csv(bind_rows(qc_rows), f_qc)

cat("\nOutputs:\n")
cat(sprintf("  %-42s %d rows (1 row = 1 s)\n", basename(f_clean), nrow(cleaned)))
if (nrow(occ_windows)) cat(sprintf("  %-42s %d cycles\n", basename(f_occ), nrow(occ_windows)))
cat(sprintf("  %-42s %d events\n", basename(f_ev), nrow(ev)))
cat(sprintf("  %-42s per-probe signal quality\n", basename(f_qc)))

if (length(warnings_log)) {
  cat(sprintf("\n%d warning(s) - review before using these outputs:\n", length(warnings_log)))
  for (w in warnings_log) cat("  - ", w, "\n", sep = "")
} else {
  cat("\nNo warnings.\n")
}
cat("\nDone.\n")
