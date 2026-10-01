# plotting_STEP — figures from the cleaned dataset

Step 3 of 3. Reads the cleaned CSVs from `../cleaning_STEP/` and writes the
signal-level figures here.

## Run

```bash
# from the project root, after clean_nirs.R has been run for that subject
Rscript plotting_STEP/plot_nirs.R "Practice12"
```

## Figure set

Follows the source literature for this method — Ryan et al. 2012
(*J Appl Physiol* 113:175–183) Figs. 2 and 3, and Ryan et al. 2014
(*J Physiol* 592.15:3231–3241) Fig. 1.

| file | based on | shows |
|---|---|---|
| `<id>_fig1_protocol_overview.png` | Ryan 2012 Fig 2; Ryan 2014 Fig 1 A/D/G/J | HHb, O2Hb, tHb, TSI% across the whole record, phases shaded, events marked |
| `<id>_fig2_recovery_series.png` | Ryan 2012 Fig 3A; Ryan 2014 Fig 1 B/E/H/K | the same four signals over F1→G1, 8 s occlusion blocks shaded |
| `<id>_fig3_cuff_magnification.png` | Ryan 2012 Fig 3C/D | the final two cycles, with individual 1-s samples as points |
| `<id>_fig4_resting_occlusion.png` | the B1→C1 validity check | O2Hb should fall and HHb rise during the resting cuff |
| `<id>_fig5_probe_comparison.png` | the Rx1/Rx2 averaging decision | Rx1, Rx2, and the average they combine into |
| `<id>_plots.png` | — | figures 1–3 stacked on one sheet |

Conventions follow the papers: μM on the y-axis, NIRS colour convention
(O2Hb red, HHb blue, tHb dark grey, TSI green), clean axes without gridlines.

## The mV̇O2 / recovery-fit figure lives elsewhere

Ryan 2014 Fig. 1 row C/F/I/L — mV̇O2 per occlusion with the monoexponential fit
— is produced by the analysis step, which owns those numbers:
`../analysis_STEP/<id>_fig6_mvo2_recovery_fit.png`.
