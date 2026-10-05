![FitScope](app/www/fitscope-logo-dark.png)

# Intro (INES)
Muscle biopsies are highly intrusive yet it is the only way that we use to measure 
muscle health. A hypothesized strategy is using infrared light. etc, etc. 

# Explanation of NIRS (ANDREA)
With two lasers, the NIRS is able to measure oxygenated hemoglobin, deoxygenated hemoglobin, total hemoglobin, difference between oxygenated and deoxygenated hemoglobin. EXPAND: explain to how those parameters are indicators of muscle health.

Ideas written by Philip: [What NIRS measures, and why occlusion
"Near-infrared light (roughly 700–900 nm) penetrates skin, fat and a few
centimetres of muscle, and is absorbed differently depending on how much of
the local haemoglobin/myoglobin pool is carrying oxygen. Measuring
attenuation at several wavelengths gives a continuous, non-invasive readout
of oxygenated (**O2Hb**) versus deoxygenated (**HHb**) haemoglobin/myoglobin
in the muscle under the sensor — in real time, with nothing drawn and nothing
inserted.
On its own that signal reflects a balance of two things happening at once:
how fast oxygen is being *delivered* (blood flow) and how fast it's being
*consumed* (mitochondrial respiration). Arterial occlusion separates them.
Inflating a pneumatic cuff above systolic pressure over the limb stops
arterial inflow entirely: no oxygen arrives, and consumption continues. For
the few seconds the cuff is up, the **slope** of HHb rising (or O2Hb falling)
is therefore a direct, blood-flow-independent readout of muscle oxygen
consumption — **mV̇O2**.
A smaller Tc means faster recovery and greater mitochondrial oxidative
capacity. It's a well-validated, repeatable, non-invasive proxy for
mitochondrial function in the specific muscle studied, in place of a biopsy."
"Near-infrared spectroscopy (NIRS) is a noninvasive technique that monitors regional tissue oxygenation reflecting perfusion status. Near-infrared spectroscopy has the ability to continuously and simultaneously monitor tissue perfusion in different organ systems at the bedside without interrupting routine care. Research has demonstrated its benefit in monitoring cerebral, intestinal, and renal perfusion to detect potential ischemic episodes. Near-infrared spectroscopy can augment current physiologic monitoring to increase awareness of abnormal perfusion status in the preterm population and potentially reduce risks associated with many diseases that may lead to ischemic injury."  https://pubmed.ncbi.nlm.nih.gov/22123468/   
Oxygen moves through our bodies in hemoglobin. Oxygenated hemoglobin is what comes from our lungs and travels to our tissues in order to provide our tissues with the oxygen they need. Deoxygenated hemoglobin is what travels away from our tissues back to our lungs and heart for more oxygen. As we use our brain, oxygenated hemoglobin travels to the areas of the brain we are using and deoxygenated hemoglobin flows away from those areas. The cool thing about the hemoglobin is that light travels through oxygenated and deoxygenated hemoglobin differently. We can use this difference to pick up on the amount of oxygenated and deoxygenated hemoglobin in different areas of the brain... The NIRS system is made up of a cap that is kind of like a swim cap and sources (photo-transmitter probe in the diagram) and detectors (photo-receiver probe in the diagram). The sources are essentially light bulbs that give off light of very specific wavelengths. The detectors pick up on the specific wavelengths of light, and how much light the detectors pick up on tells us how much light came back after traveling through the brain tissue" (We can translate this to our purposes using calve muscles) https://cheathamlab.com/index.php/near-infrared-spectroscopy/ ]

# NIRS Procedure (ANDREA)
Explain the whole procedure, KEY TO CONNECT TO THE ONLY TWO ARTICLES WRITTEN ABOUT THE NIRS
 Ideas written by Philip: [- One occlusion at **rest** gives resting mV̇O2.
- A rapid series of these occlusions **after exercise** tracks mV̇O2 as it
  decays back toward the resting value. A muscle with greater mitochondrial
  oxidative capacity resynthesizes ATP — and so returns oxygen consumption to
  baseline — faster, so its recovery curve decays faster.
- Fitting that decay to `mV̇O2(t) = Rest + Delta · e^(−t/Tc)` yields **Tc**,
  the time constant of recovery, and `k = 1/Tc`.]

# NIRS Limitation (CLARA)
Raw data is quite challenging to interpret so we developed FitScope 

## Research objective
Take a raw Oxysoft NIRS export from a repeated-occlusion recovery-kinetics
protocol and produce a **trustworthy** Tc (and k) for each subject — the
operative word being *trustworthy*, because, per above, a converged fit is
not automatically one. The pipeline this repository ships was specified
decision-by-decision by the lab's data owner (recorded in
`data_cleaning_transcript.md` and `NIRS_Pipeline_Questions_and_Challenges.docx`),
not derived or guessed at, and the two front ends below exist to run that
exact pipeline without ever reimplementing it.

# FitScope
A Shiny app and a Claude Code plugin for estimating **skeletal muscle
mitochondrial oxidative capacity** from near-infrared spectroscopy (NIRS)
arterial-occlusion recordings, following the repeated-occlusion method of
Ryan et al. 2012 (*J Appl Physiol* 113:175–183) and Ryan et al. 2014
(*J Physiol* 592.15:3231–3241).

NIRS recovery-kinetics analysis has the same failure mode every quantitative
pipeline eventually has: the curve fit converges, the number looks
physiological, and it's wrong. Fit one real recording in this repository and
`nls` returns `Tc = 13.6 s` — a perfectly textbook-plausible number — from the
same fit that implies a resting oxygen consumption of **−0.09** (negative
oxygen consumption does not exist) and an end-exercise value of **89** against
a physiological range of roughly 0.3–0.6, with R² = 0.17. None of that throws
an error. The script runs to completion, writes a CSV, and draws a figure. The
one thing wrong with an otherwise fully reproducible pipeline is the number
you'd be tempted to put in a table.

The opposite failure looks like success and isn't: the fit can also correctly
refuse to converge at all. Three real recordings in this repository return
`Tc = NA`, because their post-exercise occlusion series starts 95–109 seconds
after exercise ends — three to three-and-a-half time constants for a normal
20–40 s Tc, so most of the recovery is already over before measurement begins.
A tool that quietly widened the fit window or reseeded `nls` until a number
appeared would call this a success. FitScope calls it correctly: `NA`, with
the reason stated.

FitScope encodes the checks that catch both failures and refuses to let a
result through without them. See [Guardrails](#guardrails) below.

## What FitScope is
Three fixed R scripts are the single source of truth for every number this
project produces:

```
cleaning_STEP/clean_nirs.R     raw .xlsx export -> cleaned, one-row-per-second dataset
analysis_STEP/analyse_nirs.R   blood-volume correction, mVO2 per occlusion, the Tc fit
plotting_STEP/plot_nirs.R      the six standard figures from the source papers
```

Everything else in this repository is a way to run those three scripts
without touching their logic:

| | |
|---|---|
| **`app/`** | A Shiny app: upload a raw export, run clean → analyse → plot, view QC, the recovery-fit table with plausibility flags, and the figures. |
| **`.claude-plugin/`, `skills/`, `agents/`** | A Claude Code plugin: a `nirs-pipeline` skill that runs the pipeline conversationally, and a `pipeline-runner` subagent for batch runs. |

Both shell out to `Rscript` against the three scripts above, unmodified. If
you've read `clean_nirs.R` and trust it, you can trust what either front end
reports — there's no second implementation to drift out of sync with it.

## Install — Shiny app

Requires R with `shiny DT base64enc readxl dplyr tidyr readr ggplot2
patchwork`.

```bash
cd app
R -e 'shiny::runApp(".")'
```

The sidebar's "R package check" table shows anything missing before you try
to run a step. Point **Project directory** at wherever your raw `.xlsx`
exports live (or let it use a scratch `workspace/` next to the app), upload or
pick a file, and run the pipeline step by step or all at once.

## Install — Claude Code plugin

### 1. What you need first

| | |
|---|---|
| **Claude Code** | The CLI, desktop app, or VS Code/JetBrains extension. See [code.claude.com/docs](https://code.claude.com/docs). |
| **R 4.4+** | Needs `readxl dplyr tidyr readr ggplot2 patchwork`. Check with `R --version`. |

### 2. Open a Claude Code session

```bash
cd ~/path/to/your/study        # wherever your raw .xlsx exports live
claude
```

### 3. Install the plugin

At Claude Code's `>` prompt:

```
/plugin marketplace add fitgutlab/FitScope
/plugin install fitscope@fitgutlab
```

Restart Claude Code (`/exit`, then `claude` again) — plugins load at startup.

### 4. Check it worked

```
/fitscope:nirs-pipeline Practice12.xlsx
```

or just describe the task in plain language — the skill triggers on its own:

```
clean and analyse Practice12.xlsx, is the Tc trustworthy?
```

For several subjects at once, or to keep a long run's console output out of
the main conversation, ask it to delegate to the `pipeline-runner` subagent
instead.

## Using it

A raw Oxysoft `.xlsx` export in, subject id out. Each script finds its own
inputs and writes into its own folder (`cleaning_STEP/`, `analysis_STEP/`,
`plotting_STEP/`) regardless of where it's run from.

```bash
Rscript cleaning_STEP/clean_nirs.R   "Practice12.xlsx"   # -> cleaned 1 s dataset
Rscript analysis_STEP/analyse_nirs.R "Practice12"        # -> mVO2, Tc, k
Rscript plotting_STEP/plot_nirs.R    "Practice12"        # -> figures 1-5
```

| output | contents |
|---|---|
| `<id>_cleaned_1s.csv` | one row per second: O2Hb, HHb, tHb, phase, occlusion label |
| `<id>_qc_report.csv` | per-probe Fit Factor, TSI%, resting-occlusion correlation |
| `<id>_mvo2.csv` | mVO2 per occlusion × signal × correction |
| `<id>_recovery_fit.csv` | Rest, Delta, End, **Tc**, **k**, R², `converged` |
| `<id>_fig1..fig5.png`, `<id>_fig6_mvo2_recovery_fit.png` | the six figures |

## Guardrails

Both scripts report and continue rather than silently altering data:
`[WARNING]` for event/QC/duration problems, `[NOTE]` for fit-plausibility
problems. Across the two scripts there are **17 points** where a condition is
checked and flagged rather than assumed:

| guard | catches |
|---|---|
| TSI Fit Factor ≥ 95 | a probe whose signal quality doesn't support the analysis — flagged, never silently dropped (both probes are still averaged in, as specified) |
| Resting-occlusion O2Hb/HHb correlation sign | a probe moving the *wrong* direction for oxygen consumption during the one window where the physiology is unambiguous |
| Event-code presence/duplication | a marker missing, duplicated, or outside the expected set, before anything downstream trusts it |
| Phase duration vs. protocol nominal | a baseline, occlusion, or recovery phase that ran markedly shorter or longer than specified, which can mean the markers themselves are shifted |
| Corrected tHb ≈ 0 | the blood-volume correction identity (Ryan 2012): corrected tHb is zero *by construction*; a non-zero value means the correction broke, not a new finding |
| Corrected O2Hb/HHb agreement | after correction, O2Hb and HHb carry the same information with opposite sign and so must yield the same Tc — checked to machine precision every run |
| R² < 0.8, `Rest` < 0, `\|End\|` > 2, Tc outside ≈ 20–60 s | **the main hazard**: a converged fit that is not a trustworthy one (the `Tc = 13.6 s` example above trips three of these four at once) |
| Minimum occlusions / points per slope | a 3-parameter exponential or a 3 s slope window being asked to fit more than the data can support |

A guard that fires is doing its job. The response is to report what it found,
not to relax it until the warning goes away — see
`skills/nirs-pipeline/reference/pipeline-hazards.md` for the full reasoning
behind each one, including the two converged-but-wrong and
correctly-non-convergent cases above.

## Known data issues (reported, not corrected)

- One sample file's second probe shows a **positive** O2Hb/HHb correlation
  during the resting occlusion (r = +0.92) — not oxygen-consumption behaviour.
  It is still averaged in, as specified; the same probe is clean (r = −0.99)
  in a different session, so this looks session-specific, not a faulty probe.
- A different sample file has an extra event marker and is missing another;
  its occlusion-cadence pattern is consistent with every event label being
  shifted by one position. Flagged, not corrected.
- Baseline duration across the three bundled sample files is 83 s, 192 s and
  99 s against a nominal 120 s.

None of these are fixed in code. The decisions belong to whoever owns the
data, not to the pipeline — see `CLAUDE.md`.

## Scope

Downstream of acquisition only. FitScope starts from a raw Oxysoft `.xlsx`
export; it does not control the NIRS device, and it does not do anything with
a recording before that export exists.

## Citation

Appiah, P., de Torres, C., Machaz, I., Osorio, A. & FITGut LAB. (2026).
fitgutlab/FitScan: v1.0.0 (Version 1) [Computer software]. Zenodo.
https://doi.org/10.5281/zenodo.22885722

## References 

Method: Ryan, T.E. et al. (2012), *J Appl Physiol* 113:175–183; Ryan, T.E. &
Neufer, P.D. (2014), *J Physiol* 592.15:3231–3241. Cleaning and QC procedure
specified by C. Ortega-Santos. Built by FITGut LAB, The George Washington
University.

## License

MIT — see [`LICENSE.md`](LICENSE.md).
