
## 2026-01-02 Old-code run (Input-tagged)
- Raw input log: `Training/patrice-baumel-halo-goodbye_input_oldcode_20260102.txt`
- Final objc output: `Training/patrice-baumel-halo-goodbye_final_objc_oldcode_20260102.txt`
- Note: produced on old branch (pre-[Shazam] tag); input may be post-processed.

## Observation
- Old-code input capture consistently includes one additional golden (9/19 vs 8/19 in current Shazam logs), missing only `Cosmjn — Cosmo Acids` on the Shazam path.

# Input Regression — Goodbye

## Seeded baseline (old good)

### Files
- Raw input: `Training/patrice-baumel-halo-goodbye_input.txt`
- Golden list: `Training/patrice-baumel-halo-goodbye_golden.txt`
- Refined (py): `Training/patrice-baumel-halo-goodbye_refined_py.txt`
- Eval (py): `Training/patrice-baumel-halo-goodbye_eval_py.txt`

### File timestamps (as archived)
- Raw input mtime: 2025-01-01 20:22
- Golden mtime: 2025-01-01 21:04
- Refined (py) mtime: 2025-01-02 12:47
- Eval (py) mtime: 2025-01-02 12:47

## Notes
- This is the current “old good” baseline for Goodbye.
- When a new run is produced, archive the new Shazam log + final objc output and compare precision/recall + FP/miss deltas against this baseline.

## 2026-01-02 Shazam run (new baseline candidate)
- Raw Shazam log: `Training/patrice-baumel-halo-goodbye_shazam_20260102.txt`
- Final objc output: `Training/patrice-baumel-halo-goodbye_final_objc_shazam_20260102.txt`
- Eval output: `Training/patrice-baumel-halo-goodbye_eval_objc_shazam_20260102.txt`
- Refined 19, Matched 10, Precision 0.526, Recall 0.526

## 2026-01-02 Shazam retry #1
- Raw Shazam log: `Training/patrice-baumel-halo-goodbye_shazam_retry1_20260102.txt`
- Final objc output: `Training/patrice-baumel-halo-goodbye_final_objc_shazam_retry1_20260102.txt`
- Eval output: `Training/patrice-baumel-halo-goodbye_eval_objc_shazam_retry1_20260102.txt`
- Refined 20, Matched 11, Precision 0.550, Recall 0.579

## 2026-01-02 Shazam retry #2
- Raw Shazam log: `Training/patrice-baumel-halo-goodbye_shazam_retry2_20260102.txt`
- Final objc output: `Training/patrice-baumel-halo-goodbye_final_objc_shazam_retry2_20260102.txt`
- Eval output: `Training/patrice-baumel-halo-goodbye_eval_objc_shazam_retry2_20260102.txt`
- Refined 21, Matched 10, Precision 0.476, Recall 0.526

## 2026-01-02 Old-branch raw Shazam capture (with slice hashes)
- Raw Shazam log: `Training/patrice-baumel-halo-goodbye_shazamraw_main_20260102.txt`
- Note: contains `[ShazamRaw] run:<uuid> slice:<hash> frame:<n>` lines for slice-level comparison.

## Baseline eval (old good)
- Eval output: `Training/patrice-baumel-halo-goodbye_eval_py_baseline.txt`
- Refined 19, Matched 14, Precision 0.737, Recall 0.737

## Regression snapshot (baseline vs 2026-01-02)
- Precision/recall dropped (0.737 → 0.526).
- False positives increased: baseline 5 vs new 9.
- Missed goldens increased: baseline 5 vs new 9.

## Recall regression - likely drivers
- Raw input coverage is lower on the Shazam path: old-code input shows 9/19 goldens vs 8/19 on Shazam logs; the missing golden is `Cosmjn — Cosmo Acids`, which caps achievable recall before refinement.
- Refinement still drops some goldens that are present in raw input (baseline vs new has different candidates around that span), so part of the recall loss is post-input.
- Net: recall regression appears to be a mix of input loss (missing Cosmjn) and refiner behavior; not explained by refinement alone.
