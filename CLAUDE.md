# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An R data-analysis project (not a package, not a git repo) that estimates **skeletal muscle
mitochondrial oxidative capacity** from NIRS arterial-occlusion data, following Ryan et al.
2012 (*J Appl Physiol*) and Ryan et al. 2014 (*J Physiol*) — both PDFs are in the root. The
headline output is the recovery **time constant Tc** (and `k = 1/Tc`) of post-exercise muscle
V̇O2.

Three-step pipeline, one folder per step, each with its own README:

```bash
Rscript cleaning_STEP/clean_nirs.R   "Practice12.xlsx"
Rscript analysis_STEP/analyse_nirs.R "Practice12"
Rscript plotting_STEP/plot_nirs.R    "Practice12"
```

Raw `.xlsx` exports live in the root. Each script resolves its own location and reads/writes
by folder, so it works from the root or from inside its own folder. Packages: `readxl dplyr
tidyr readr ggplot2 patchwork`. The curve fit uses base `nls`.

```
Practice12.xlsx                                (sheet "Export 1")
  │ cleaning_STEP/clean_nirs.R
  ├─> <id>_cleaned_1s.csv            one row = one second; the analysis input
  ├─> <id>_occlusion_windows.csv     one row per 8 s/8 s cycle
  ├─> <id>_events.csv                event code -> time in seconds
  └─> <id>_qc_report.csv             per-probe Fit Factor, TSI%, resting correlation
        │ analysis_STEP/analyse_nirs.R
        ├─> <id>_mvo2.csv            occlusion x signal x correction
        ├─> <id>_recovery_fit.csv    Rest, Delta, End, Tc, k, R2, converged
        └─> <id>_fig6_mvo2_recovery_fit.png
              │ plotting_STEP/plot_nirs.R
              └─> <id>_fig1..fig5.png, <id>_plots.png
```

## The decisions are the data owner's, not the code's

The cleaning procedure implements what C. Ortega-Santos specified, recorded verbatim in
`data_cleaning_transcript.md` and answered inline in `NIRS_Pipeline_Questions_and_Challenges.docx`.
**Read those before changing cleaning behaviour** — several choices look wrong on the data
and are deliberate:

| behaviour | why |
|---|---|
| average every *sample_rate* rows into 1 s | specified; "easier to visualize things" |
| average Tx1/Tx2/Tx3 within a probe | specified (not best-channel selection) |
| average Rx1 and Rx2 **unconditionally** | specified; a failing probe is reported, never dropped |
| fixed 8 s occlusion / 8 s reperfusion grid from F1 | specified (not detection from the tHb trace) |

An earlier pipeline made the opposite choice on all four. It is in `archive/old_pipeline/`
with a comparison table — do not resurrect it, and do not "fix" the current code toward it.

**TSI Fit Factor is a percentage where higher is better, threshold ≥ 95** (columns 3 and 17).
An earlier version of this file and the archived README said "closer to 0 = better"; that was
wrong. Note it passes at 99+ on every file including probes that are physiologically invalid,
so it discriminates nothing on its own.

## Architecture notes that aren't obvious from one file

**Nothing about the raw export is hardcoded by position.** `clean_nirs.R` reads the sample
rate from the metadata block, builds the column-number → trace-name map from the legend text,
and locates the numeric header row by scanning rows 60–80 for a cell equal to `"1"`. Lookups
go through `find_col(df, rx, tx, signal)`, matching by `"<Rx> - <Tx> <signal> "` prefix —
deliberately, because the legend's parenthetical suffix echoes the file name and is sometimes
misspelled (`"(Pracice12)"` inside `Practice12.xlsx`). Don't simplify to fixed cell
references: the sample files genuinely differ (10 Hz vs 1 Hz, missing `H1`, a stray `E2`).

**Sample rate is per file, never assumed.** `practice_4.xlsx` is natively 1 Hz, so
`rows_per_second` is 1 and the averaging is a pass-through. Anything assuming 10 would
collapse 10 real seconds into one row.

**Second-binning uses integer sample offsets**, `(sample - sample_A1) %/% rows_per_second`,
not floating-point time. Binning on floats produced 9- and 11-row blocks from a perfectly
contiguous sample column.

**`Rscript` encodes spaces in the script path as `~+~`**, and this project's path contains
spaces. All three scripts decode it in `script_dir()` before use. Removing that breaks every
absolute-path invocation.

**Two identities hold by construction in the blood-volume correction**, and both are checked
at runtime:
- Corrected tHb is **identically zero** — it is the sum of the two corrected signals. Ryan
  2012 Fig. 3B/D shows exactly this. Its recovery fit is skipped; without that guard `nls`
  returns a time constant fitted to rounding noise.
- Corrected O2Hb and HHb give the **same Tc** — after correction they carry the same
  information with opposite sign. Ryan 2012 Fig. 3F shows both at Tc = 125.5 s. The script
  prints the agreement (machine precision) every run.

**Ryan's constants**: slope over the **first 3 s** of each occlusion (`SLOPE_WINDOW_S`),
because β is stable there and drifts in the final 1–2 s (Ryan 2012 Fig. 5). At 1 Hz that is
4 points per slope, which the script flags as a real precision limit.

**Figures map to specific published figures** — fig 1 ≈ Ryan 2012 Fig 2 / Ryan 2014 Fig 1 row
1, fig 2 ≈ Ryan 2012 Fig 3A / row 2, fig 3 ≈ Ryan 2012 Fig 3C/D, fig 6 ≈ Ryan 2014 Fig 1 row 3
with Ryan 2012 Fig 3E/F's corrected/uncorrected pairing. Keep the correspondence if you change
them. **Each step owns its own figures**: figs 1–5 are signal-level and belong to
`plotting_STEP/`; fig 6 is drawn by `analyse_nirs.R` from its in-memory results, so it cannot
drift out of step with `<id>_recovery_fit.csv`.

In fig 6, every panel is given both `correction` levels — as an unplotted `NA` row for TSI,
which has no corrected series — so patchwork merges the four guides into one legend instead of
emitting a separate legend per panel shape. Range calculations there need `na.rm = TRUE`.

## Handling results that look wrong

**A converged fit is not a trustworthy one, and this is the main hazard in the project.**
`nls` will fit a drifting series and return a Tc that looks entirely normal. `practice_4`
returns `Tc = 13.6 s` — plausible — with a fitted resting mV̇O2 of −0.087 (negative oxygen
consumption is impossible), a fitted end-exercise value of 89 against a physiological 0.3–0.6,
and R² = 0.17. `analyse_nirs.R` flags all four conditions (R² < 0.8, negative `Rest`, `|End| >
2`, Tc outside 20–60 s). Keep those guards.

**All three sample files start the recovery cuff series 95–109 s after exercise ends** — 3–3.5
time constants for a normal 20–40 s Tc, so most of the recovery is over before measurement
begins. `Practice12` and `practice3` therefore return `Tc = NA`. **That is a correct result
about the protocol, not a bug.** Never relax a QC gate, widen a fit window, or reseed `nls` to
make a number appear.

Both `clean_nirs.R` and `analyse_nirs.R` report and continue rather than altering data:
`[WARNING]` for event/QC/duration problems, `[NOTE]` for fit plausibility. Don't suppress them.

## Known data issues awaiting the data owner

- `Practice12` Rx2 shows a **positive** O2Hb/HHb correlation during the resting occlusion
  (r = +0.92) — not oxygen-consumption behaviour. It is still averaged in, as specified. Rx2
  is clean in `practice3` (r = −0.99), so this is session-specific, not a faulty probe.
- `practice3` has an extra `E2` and no `H1`, and its tHb cadence analysis puts the 8 s/8 s
  occlusion series in `E2`→`F1`, not the marked `F1`→`G1`. Reading its labels as shifted one
  position makes all three files agree on protocol timing. Unresolved — the script reads the
  markers literally and flags the anomaly.
- Baseline `A1`→`B1` is 83 / 192 / 99 s against a nominal 120 s across the three files.

## Conventions

- Subject ID comes from the raw file's basename; every output is prefixed with it.
- `.docx` / `.txt` / `caht history` / `untitled` / `Overview of the Data Cleaning Workflow`
  are lab correspondence and the Q&A trail behind the decisions — context, not script inputs.
- `archive/` holds the superseded pipeline and one-off diagnostics. No live script reads it.
