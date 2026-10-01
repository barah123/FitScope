# FitScope Shiny app

A thin front end over the repo root's `cleaning_STEP/` / `analysis_STEP/` /
`plotting_STEP/`. Does not reimplement any cleaning, correction, or
curve-fitting logic — it copies the pipeline's three scripts into a project
folder and shells out to `Rscript`, then reads back the CSVs and PNGs those
scripts already produce.

## Run

```bash
cd app
R -e 'shiny::runApp(".")'
```

Requires R with `shiny DT base64enc readxl dplyr tidyr readr ggplot2
patchwork`. The sidebar's "R package check" table shows what's missing.

## Using it

1. **Project directory** — where your raw `.xlsx` and pipeline outputs live.
   Defaults to `../workspace` (git-ignored scratch space next to this app).
   Point it at an existing project to work with data that's already there.
2. **Prepare project folder** — copies `clean_nirs.R` / `analyse_nirs.R` /
   `plot_nirs.R` into `cleaning_STEP/` / `analysis_STEP/` / `plotting_STEP/`
   under the project directory, if not already present. Never overwrites a
   script you've customized.
3. **Upload** a raw Oxysoft `.xlsx`, or pick one already in the project root.
4. **Run** — step by step, or all three at once. Long runs show a progress
   bar; R itself is single-threaded per session, so one run blocks the UI
   until it finishes (expected for a local analysis tool, not a bug).
5. Tabs: **Console** (full log, `[WARNING]`/`[NOTE]` lines highlighted),
   **QC report**, **Recovery fit (Tc)** (with the same plausibility flags the
   reference project's guardrails require — a converged fit is checked, not
   trusted by default), **Signal figures (1-5)**, **Output files**.
6. **View existing subject** — switch between previously cleaned subjects in
   the same project without rerunning anything.

## Files

- `app.R` — UI and server.
- `R/pipeline_runner.R` — `run_step()` shells out to Rscript; `ensure_project()`
  copies the bundled scripts; `read_recovery_fit()` / `read_qc_report()` read
  results back; `plausibility_flags()` mirrors the guardrails in
  `../skills/nirs-pipeline/reference/pipeline-hazards.md`.
