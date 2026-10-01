# Skeletal muscle mitochondrial oxidative capacity from NIRS 

Estimates skeletal muscle mitochondrial oxidative capacity from near-infrared
spectroscopy using the repeated arterial-occlusion method of Ryan et al. 2012
(*J Appl Physiol* 113:175–183) and Ryan et al. 2014 (*J Physiol* 592.15:3231–3241).
Both papers are in this folder.

The headline output is the recovery **time constant Tc** (and `k = 1/Tc`) of
post-exercise muscle V̇O2. A smaller Tc means faster recovery and greater
mitochondrial capacity.

## Pipeline

Three steps, each a folder with its own README. Run in order, per subject:
.
```bash
Rscript cleaning_STEP/clean_nirs.R   "Practice12.xlsx"   # raw export -> 1 s dataset
Rscript analysis_STEP/analyse_nirs.R "Practice12"        # -> mVO2 per occlusion, Tc
Rscript plotting_STEP/plot_nirs.R    "Practice12"        # -> figures 1-6
```

| folder | does | key outputs |
|---|---|---|
| [`cleaning_STEP/`](cleaning_STEP/README.md) | trim to A1, Hz → seconds, average Tx then Rx, label phases and the 8 s/8 s occlusion grid | `<id>_cleaned_1s.csv`, `<id>_occlusion_windows.csv`, `<id>_qc_report.csv` |
| [`analysis_STEP/`](analysis_STEP/README.md) | blood-volume correction, mV̇O2 per occlusion, monoexponential recovery fit | `<id>_mvo2.csv`, `<id>_recovery_fit.csv`, `<id>_fig6_mvo2_recovery_fit.png` |
| [`plotting_STEP/`](plotting_STEP/README.md) | signal-level figures from the source papers | `<id>_fig1…fig5.png`, `<id>_plots.png` |

Raw `.xlsx` exports stay in this root folder. Each script finds its inputs and
writes into its own folder regardless of where you run it from.

Requires R with `readxl dplyr tidyr readr ggplot2 patchwork`.

## Method, in brief

1. A cuff is inflated above arterial pressure over the muscle while NIRS records
   oxygenated (O2Hb) and deoxygenated (HHb) haemoglobin/myoglobin.
2. During occlusion no oxygen is delivered or removed, so the **slope** of HHb
   (or −O2Hb) over the first seconds reflects muscle oxygen consumption (mV̇O2).
3. One occlusion at **rest** gives resting mV̇O2.
4. After exercise, a series of short repeated occlusions tracks mV̇O2 as it
   **decays monoexponentially** back toward rest.
5. Fitting `mV̇O2(t) = Rest + Delta · e^(−t/Tc)` gives **Tc**, the index of
   mitochondrial oxidative capacity.

The blood-volume correction (Ryan 2012, Method 1) and the 3 s slope window are
documented in [`analysis_STEP/README.md`](analysis_STEP/README.md).

## Study protocol

Event codes appear in column 30 of the raw export:

| code | marks | nominal |
|---|---|---|
| A1 | baseline starts | 120 s to B1 |
| B1 | resting occlusion starts | 30 s to C1 |
| C1 | reperfusion (cuff released) | — |
| D1 | exercise starts | 60 s to E1 |
| E1 | exercise ends | — |
| F1 | recovery occlusion series starts | 180 s to G1 |
| G1 | recovery occlusion series ends | — |
| H1 | end of study | — |

Deviations from these nominals are reported by `clean_nirs.R`, never corrected.

## Reference material

`data_cleaning_transcript.md`, `NIRS_Pipeline_Questions_and_Challenges.docx` and
`Docoumentation of the data.docx` record the decisions behind the cleaning
procedure. `Information on the NIRS output file` is the vendor's explanation of
the column naming. These are context; no script reads them.

## archive/

Superseded work, kept for reference — an earlier pipeline that made different
methodological choices, plus one-off diagnostics. See
[`archive/README.md`](archive/README.md). Nothing there is part of the current
pipeline.


Citation
Philip Appiah, Clara de Torres, Ines Machaz, Andrea Osorio & FITGut LAB. (2026). fitgutlab/FitScan: v1.0.0 (Version 1) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.22885722
