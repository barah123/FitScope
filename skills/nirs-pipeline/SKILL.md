---
name: nirs-pipeline
description: >-
  Runs the NIRS skeletal-muscle mitochondrial oxidative capacity pipeline: a
  raw Artinis Oxysoft arterial-occlusion export (.xlsx) goes through cleaning
  (Hz -> 1 s, TSI Fit Factor QC, Tx/Rx probe averaging, phase and occlusion
  labelling), analysis (blood-volume correction, mVO2 per occlusion, the
  monoexponential recovery fit for Tc and k = 1/Tc), and plotting (the six
  standard figures). Use when asked to clean, process, analyse, or run the
  NIRS/oxidative-capacity pipeline on a raw export, to compute Tc / the
  recovery time constant / mVO2, or to check whether a subject's fit is
  trustworthy. Triggers on: NIRS pipeline, mitochondrial oxidative capacity,
  arterial occlusion, recovery time constant, Tc, mVO2, Ryan 2012, Ryan 2014,
  clean_nirs, analyse_nirs, Oxysoft export.
argument-hint: "[raw .xlsx path, or an already-cleaned subject id]"
---

# FitScope NIRS pipeline

Three fixed steps, always in this order, implementing Ryan et al. 2012 (*J
Appl Physiol* 113:175-183) and Ryan et al. 2014 (*J Physiol* 592.15:3231-3241):

1. **Clean** — raw Oxysoft export → `<id>_cleaned_1s.csv` (one row per second),
   `<id>_occlusion_windows.csv`, `<id>_events.csv`, `<id>_qc_report.csv`.
2. **Analyse** — blood-volume correction, mVO2 per occlusion, monoexponential
   recovery fit → `<id>_mvo2.csv`, `<id>_recovery_fit.csv`,
   `<id>_fig6_mvo2_recovery_fit.png`.
3. **Plot** — `<id>_fig1..fig5.png`, `<id>_plots.png`.

**The R scripts compute. You orchestrate, read their output, and interpret
plausibility.** Do not hand-write cleaning or curve-fitting logic — every
decision in `clean_nirs.R` and `analyse_nirs.R` was specified by the data
owner (see `reference/pipeline-hazards.md`), not derived, and re-deriving it
in conversation is how a subtly different answer gets produced.

## 1. Locate the pipeline scripts

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
for cand in "$ROOT" "./fitscope" "."; do
  if [ -f "$cand/cleaning_STEP/clean_nirs.R" ]; then PIPELINE_SRC="$cand"; break; fi
done
[ -n "$PIPELINE_SRC" ] || echo "Could not find the FitScope pipeline scripts. Looked in: $ROOT, ./fitscope, ."
```

If none resolve, stop and tell the user rather than guessing a path or writing
substitute R code.

## 2. Prepare the working project

The scripts are self-locating: each one reads/writes relative to its own
folder, and expects `cleaning_STEP/`, `analysis_STEP/`, `plotting_STEP/` as
siblings with the raw `.xlsx` files at the parent root — exactly the layout in
`PIPELINE_SRC`. Work in the user's current project directory, not inside the
plugin's own install path (outputs must land where the user can find them):

```bash
PROJECT="$(pwd)"   # or wherever the user's raw file / prior outputs live
for step in cleaning_STEP analysis_STEP plotting_STEP; do
  mkdir -p "$PROJECT/$step"
  for f in "$PIPELINE_SRC/$step"/*.R; do
    dst="$PROJECT/$step/$(basename "$f")"
    [ -f "$dst" ] || cp "$f" "$dst"     # never overwrite a script the user edited
  done
done
```

If a raw `.xlsx` was given, make sure it sits at `$PROJECT/` root (copy it
there if it was supplied from elsewhere). If only a subject id was given,
require `<id>_cleaned_1s.csv` to already exist in `$PROJECT/cleaning_STEP/` —
if it doesn't, ask for the raw file instead of fabricating one.

## 3. Run, in order

```bash
Rscript "$PROJECT/cleaning_STEP/clean_nirs.R"   "<raw>.xlsx"      # from $PROJECT
Rscript "$PROJECT/analysis_STEP/analyse_nirs.R" "<subject_id>"
Rscript "$PROJECT/plotting_STEP/plot_nirs.R"    "<subject_id>"
```

Run with cwd = `$PROJECT`. `<subject_id>` is the raw file's basename without
extension. If cleaning reports a hard error (missing A1 marker, unreadable
sheet), stop — do not run analyse/plot on data that didn't clean.

## 4. Read the output, don't just say "done"

Every run prints `[WARNING]` (data/QC/duration problems) and `[NOTE]`
(fit-plausibility problems) lines and continues rather than silently fixing
anything. **Surface every one of them to the user, verbatim or paraphrased —
never drop them because the script "completed successfully."** A zero-exit
status is not the same as a trustworthy result.

Read back `<id>_recovery_fit.csv` and report the **primary result**: signal =
HHb, correction = corrected. Then check it against
`reference/pipeline-hazards.md` before calling it good:

- `converged == FALSE` → report `Tc = NA` as the answer, not a failure. If the
  first recovery occlusion starts more than ~3 time constants after exercise
  ends (check `<id>_events.csv` E1 vs. the first `occ_label` start in
  `<id>_occlusion_windows.csv`), say so explicitly — that is very likely a
  correct result about when measurement started, not a bug in the fit.
- `converged == TRUE` but `r_squared < 0.8`, `Rest < 0`, `abs(End) > 2`, or
  `Tc` outside roughly 20-60 s → flag it as **implausible despite converging**
  and say why (negative oxygen consumption, an end-exercise value far outside
  the physiological 0.3-0.6 range, etc.). Do not present a converged-but-wrong
  fit as the headline number.

**Never** relax a QC threshold, widen the slope window, change the occlusion
grid, or reseed `nls` to make a number appear. If asked to "fix" a `Tc = NA`
or an implausible fit, explain why the guard exists (see
`reference/pipeline-hazards.md`) before considering it — most of the time the
right answer is that the result is genuinely NA or genuinely bad, and that is
what should be reported.

## 5. Report back

For each subject: Tc (s), k (1/s), R², converged, every `[WARNING]`/`[NOTE]`
line, and the output file paths (cleaning_STEP/analysis_STEP/plotting_STEP
under `$PROJECT`). For multiple subjects, or when you want this off the main
conversation's context, delegate to the `pipeline-runner` agent in this
plugin instead of running everything inline.

## Reference

`reference/pipeline-hazards.md` — the plausibility guardrails, the known
per-file protocol deviations, and what NOT to change, condensed from this
repo's `CLAUDE.md` and data-cleaning transcript. Read it before touching
cleaning behaviour or explaining away a bad fit.
