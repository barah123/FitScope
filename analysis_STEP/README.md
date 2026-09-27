# analysis_STEP — mV̇O2 per occlusion and the recovery time constant

Step 2 of 3. Reads the cleaned data from `../cleaning_STEP/` and produces the
mitochondrial-capacity result. Figures come from `../plotting_STEP/`.

## Run

```bash
Rscript analysis_STEP/analyse_nirs.R "Practice12"
```

## Method (Ryan defaults)

**1. Blood-volume correction** — Ryan et al. 2012, Method 1, per occlusion:

```
ΔtHb  = ΔO2Hb + ΔHHb
β     = mean over t of |ΔO2Hb| / (|ΔO2Hb| + |ΔHHb|)

ΔO2Hb_corrected = ΔO2Hb − ΔtHb × (1 − β)
ΔHHb_corrected  = ΔHHb  − ΔtHb × β
```

**2. mV̇O2 = the slope** of the (corrected) signal over the **first 3 s** of each
occlusion. Ryan 2012 used 3 s because β is stable there and drifts during the
final 1–2 s of the cuff (their Fig. 5).

**3. Monoexponential recovery fit** against time since exercise end (`E1`):

```
mV̇O2(t) = Rest + Delta × e^(−t / Tc)
```

`Tc` is the index of mitochondrial oxidative capacity; `k = 1/Tc`. Smaller Tc
(larger k) means faster recovery and greater capacity.

Computed for **HHb, O2Hb, tHb and TSI**, each uncorrected and — where the
correction applies — corrected. TSI has no blood-volume correction (it is
already a ratio). The primary result is **HHb, corrected**, Ryan's recommended
signal.

Sign convention: `mVO2` is reported so positive always means oxygen
consumption. `slope` is the raw per-second slope, kept alongside it.

## Two built-in checks

- **Corrected tHb must be identically zero.** It is the sum of the two
  corrected signals, so the correction zeroes it by construction — Ryan 2012
  Fig. 3B/D shows exactly this flat line. Its fit is skipped rather than fitted
  to rounding noise.
- **Corrected O2Hb and HHb must give the same Tc.** After correction they carry
  the same information with opposite sign. Ryan 2012 Fig. 3F shows both at
  Tc = 125.5 s. The script prints the agreement to machine precision.

## Outputs

| file | contents |
|---|---|
| `<id>_mvo2.csv` | one row per occlusion × signal × correction: `slope`, `mVO2`, `beta`, `slope_r2`, `n_points`, `time_since_exercise_s` |
| `<id>_recovery_fit.csv` | one row per signal × correction: `Rest`, `Delta`, `End`, `Tc`, `k`, `r_squared`, `converged`, `resting_mVO2` |
| `<id>_fig6_mvo2_recovery_fit.png` | the figure — mV̇O2 per occlusion with the fitted curve, all four signals, corrected and uncorrected |

The figure is Ryan 2014 Fig. 1 row C/F/I/L, with the corrected/uncorrected
pairing of Ryan 2012 Fig. 3E/F overlaid in each panel. It is drawn from the
results in memory, so it always matches the CSVs written beside it. The other
five figures are in `../plotting_STEP/`.

## A converged fit is not a trustworthy one

`nls` will happily fit a drifting series and return a time constant that looks
entirely normal. The script flags, and you should not report a result where:

- R² is below 0.8–0.9
- fitted `Rest` is negative (negative resting oxygen consumption is impossible)
- fitted `End` is far outside roughly 0.3–0.6
- `Tc` falls outside about 20–40 s for a healthy adult

It also reports the delay between exercise end and the first recovery cuff. If
that delay is long relative to a 20–40 s time constant, most of the recovery is
over before measurement starts and no time constant can be recovered from the
data — `Tc` is reported as `NA` rather than invented.
