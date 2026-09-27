# cleaning_STEP — raw Oxysoft export → cleaned dataset

Step 1 of 2. Turns a raw Artinis Oxysoft `.xlsx` export into a cleaned,
one-row-per-second dataset. Step 2 is `../plotting_STEP/`.

## Run

```bash
# from the project root
Rscript cleaning_STEP/clean_nirs.R "Practice12.xlsx"
```

The raw `.xlsx` files stay in the project root; every output is written into
this folder. The script finds both regardless of where you run it from.

## What it does

Implements the procedure specified by C. Ortega-Santos (see
`../data_cleaning_transcript.md` and
`../NIRS_Pipeline_Questions_and_Challenges.docx`):

1. Delete every row above the **A1** baseline marker. A1 becomes `t = 0 s`.
2. **Hz → seconds**: average every *sample_rate* rows into one row, so one row
   = one second. The rate is read from each file's own metadata — not assumed
   to be 10 Hz (`practice_4.xlsx` is natively 1 Hz).
3. Check **TSI Fit Factor ≥ 95** for Rx1 (col 3) and Rx2 (col 17).
4. Average **Tx1/Tx2/Tx3** within each probe, then average **Rx1 and Rx2**
   unconditionally into the analysis signal.
5. Label protocol phases from the event codes, and split the recovery series
   into alternating **8 s occlusion / 8 s reperfusion** blocks from the F1
   marker.

## Outputs, per subject

| file | contents |
|---|---|
| `<id>_cleaned_1s.csv` | the cleaned dataset — one row per second |
| `<id>_occlusion_windows.csv` | one row per cycle: occlusion and reperfusion start/end |
| `<id>_events.csv` | each event code, its raw sample number, its time in seconds |
| `<id>_qc_report.csv` | per-probe Fit Factor, TSI%, resting-occlusion correlation |

### `<id>_cleaned_1s.csv` columns

- `time_s` — seconds since A1, contiguous
- `phase` — `baseline`, `rest_occlusion`, `reperfusion`, `exercise`,
  `post_exercise_gap`, `recovery_series`, `end`, `post_study`
- `occ_label` — `occlusion_01`, `reperfusion_01`, `occlusion_02`, … inside the
  recovery series; `NA` elsewhere
- `O2Hb`, `HHb`, `tHb`, `HbDiff` — **the analysis signals** (Tx-averaged, then
  Rx1/Rx2-averaged)
- `O2Hb_rx1`, `O2Hb_rx2`, `HHb_rx1`, `HHb_rx2`, `tHb_rx1`, `tHb_rx2` — the
  per-probe inputs, kept so the probe QC can be checked rather than trusted
- `TSI_rx1`, `TSI_rx2`, `FitFactor_rx1`, `FitFactor_rx2` — signal quality
- `n_raw` — raw rows averaged into this second (should equal the sample rate;
  a short final block is normal)

## Warnings

The script reports and continues — it never alters data to silence a warning.
Warnings cover missing or unexpected event codes, a probe whose O2Hb/HHb move
together during the resting occlusion, Fit Factor below 95, and phase
durations that differ from the protocol nominal by more than 10 s.
