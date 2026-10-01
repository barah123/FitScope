# Pipeline hazards and fixed decisions

Condensed from this repo's `CLAUDE.md` and `data_cleaning_transcript.md` (the
data owner's specification). Read this before explaining away a result or
suggesting a change to `cleaning_STEP/`, `analysis_STEP/`, or `plotting_STEP/`.

## The cleaning decisions are the data owner's, not the code's

These look like they could be "improved" and are not — they are specified:

| behaviour | why |
|---|---|
| average every *sample_rate* rows into 1 s | specified; "easier to visualize things" |
| average Tx1/Tx2/Tx3 within a probe | specified (not best-channel selection) |
| average Rx1 and Rx2 **unconditionally** | specified; a failing probe is reported, never dropped |
| fixed 8 s occlusion / 8 s reperfusion grid from the F1 marker | specified (not detected from the tHb trace) |

Do not "fix" any of these toward best-channel selection, conditional probe
dropping, or trace-detected occlusion windows. An earlier pipeline made the
opposite choice on all four and was superseded.

**TSI Fit Factor is a percentage where higher is better, threshold ≥ 95**
(not "closer to 0 = better" — that was a documented error in an earlier
version of this project). It passes at 99+ on effectively every file,
including physiologically invalid probes, so it discriminates nothing on its
own — don't treat a passing Fit Factor as proof a probe's signal is good.

## A converged fit is not a trustworthy one — the main hazard

`nls` will fit a drifting or near-flat series and return a `Tc` that looks
entirely normal. Check the primary result (HHb, blood-volume corrected)
against all four:

- `r_squared < 0.8`
- `Rest < 0` (negative oxygen consumption is impossible)
- `abs(End) > 2` (physiological end-exercise mVO2 is roughly 0.3-0.6)
- `Tc` outside roughly 20-60 s

Any one of these means: report the number, but flag it as implausible. Do not
suppress the flag because the fit "worked."

## `Tc = NA` can be the correct answer

If the recovery occlusion series starts several time constants after exercise
ends, most of the recovery is over before measurement begins and the fit
correctly fails to converge. That is **a correct result about the study
protocol, not a bug in the fit** — check `time_since_exercise_s` for the
first recovery occlusion against a plausible Tc (20-60 s); starting at
3+ time constants (i.e. ≥ 60-180 s post-exercise) explains a non-convergent
fit without anything being wrong.

**Never** relax a QC gate, widen the 3 s slope window, change the occlusion
grid, or reseed `nls` with different starting values to force a number out of
data that doesn't support one.

## Two identities that must hold (checked at runtime by `analyse_nirs.R`)

- Corrected tHb is **identically zero** by construction (sum of the two
  corrected signals) — its recovery fit is skipped on purpose. A non-zero
  corrected tHb slope means the correction itself is broken, not a signal
  finding.
- Corrected O2Hb and HHb give the **same Tc** — after correction they carry
  the same information with opposite sign. The script prints their agreement
  (should be machine precision, ~1e-9 or smaller) every run; a real
  discrepancy means something upstream changed.

## Known, unresolved data anomalies (report them, don't "fix" them)

- A probe showing a **positive** O2Hb/HHb correlation during the resting
  occlusion is not behaving like oxygen consumption, but per the averaging
  rule above it is still averaged in — flag it, don't drop it.
- Phase durations (baseline, occlusion, exercise, recovery) that differ from
  the protocol's nominal timing by more than ~10 s are reported as warnings,
  not corrected. A markedly short or long phase can mean the event labelling
  itself is shifted by one position in that particular export — note the
  possibility, do not silently relabel events to compensate.

## Conventions to preserve

- Subject id = the raw file's basename; every output file is prefixed with it.
- `[WARNING]` = event/QC/duration problem. `[NOTE]` = fit-plausibility problem.
  Both mean "reported and continued," never "silently corrected." Relay them.
- Figures map to specific published figures (fig 1 ≈ Ryan 2012 Fig 2, fig 2 ≈
  Ryan 2012 Fig 3A, fig 3 ≈ Ryan 2012 Fig 3C/D, fig 6 ≈ Ryan 2014 Fig 1 row 3
  with Ryan 2012 Fig 3E/F's corrected/uncorrected pairing). Keep the
  correspondence if the plotting script ever changes.
