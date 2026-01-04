# Patrice HALO 2024 Input Regression Archive

## Inputs
- Old input: `Training/patrice-baumel-halo-2024_input.txt`
  - File date: 2026-01-01 21:03:51
  - Captured from `[Input]` logging during detection runs.
- New baseline: `Training/patrice-baumel-halo-2024_input_newbaseline.txt`
  - File date: 2026-01-02 12:52:41
  - Captured from `[Input]` logging during detection runs.

Note: These files do not include `[InputMeta]`, so exact runtime parameters were not embedded. Use repo history and test logs for run context.

## Reproducibility (Verbose)
Use this as the canonical run log template. Fill in every field when producing a new input or eval.

### Environment
- Machine: 
- OS: 
- Audio device: 
- Build configuration: 
- Git branch: 
- Git commit: 
- Dirty working tree? (Y/N, list files): 

### Test Harness Settings
- Fixture path: 
- `PLAYEM_SIGNATURE_WINDOWS`: 
- `PLAYEM_SIGNATURE_RUNS`: 
- `PLAYEM_HOP_SIZE_FRAMES`: 
- `PLAYEM_USE_STREAMING_MATCH`: 
- `PLAYEM_DOWNMIX_TO_MONO`: 
- `UseSignatureTimes` (defaults): 
- `UseStreamingMatch` (defaults): 
- `DownmixToMono` (defaults): 

### Runtime Parameters (from logs)
- `[InputMeta] sampleRate`: 
- `[InputMeta] hopSize`: 
- `[InputMeta] signatureWindow`: 
- `[InputMeta] maxSignatureWindow`: 
- `[InputMeta] skipRefinement`: 
- `[InputMeta] frames`: 

### Input Capture
- Input file path: 
- Input capture method: `[Input]` log via `debugScoring` (YES/NO)  
- Capture time (local): 
- Number of `[Input]` lines: 

### Refinement / Eval Artifacts
- Refined output path: 
- Eval output path: 
- Summary log path (`Training/test_summaries/*.log`): 

### Observed Metrics (copy/paste)
- `[PlayEmTests] Summary over ...`: 
- Per‑window summaries (if any): 
- Golden comparison: 
- Missing / unexpected lists: 

## Input Quality Comparison (String-Level)
- Old: inputs=371, unknown=8 (2.2%), unique keys=118
- New: inputs=757, unknown=388 (51.3%), unique keys=44
- Lost unique keys: 96
- Added unique keys: 22
- Canonicalization shift: none detected (shared normalized keys had identical raw strings)

## Refiner Evaluation (Current Python)

### Old input (`Training/patrice-baumel-halo-2024_refined_py.txt`)
- Refined: 22, Golden: 24
- Matched: 19 (precision 0.864, recall 0.792)
- SoftMatched: 20 (soft recall 0.833)
- False positives:
  - Munir Amastha — Can You Feel the Night (One Opinion Remix) [feat. Sauli Harper]
  - Marc Marzenit — Perron (Wehbba Remix)
  - Blackbelt Andersen — Åpenbaring (Original Mix)
- Missed golden:
  - Luigi Tozzi — Epica del Ritorno
  - Thomas Ragsdale — An Evil Within
  - Galcher Lustwerk — Liberty, Oh!
  - Henry Saiz & Tentacle — The Prophetess (Brian Cid Remix)
  - Blackbelt Andersen — Åpenbaring

### New input (`Training/patrice-baumel-halo-2024_refined_py_newbaseline.txt`)
- Refined: 10, Golden: 24
- Matched: 8 (precision 0.800, recall 0.333)
- SoftMatched: 8 (soft recall 0.333)
- False positives:
  - unknown
  - Rick Marshall — Don’t Stop
- Missed golden:
  - Priori — Winged (Priori Rezone)
  - Luigi Tozzi — Epica del Ritorno
  - Downliner Sekt — Balt Shakt I
  - Peter van Hoesen — Swerve Damiao
  - DJ Akira Prophets Tribe — Why Listen Music (Paul Hamilton Remix)
  - Thomas Ragsdale — An Evil Within
  - Minilogue — Blessed
  - Dactilar — Ojancanos
  - Subconscious Tales — Why
  - Galcher Lustwerk — Liberty, Oh!
  - Jens Zimmermann — X11
  - Joachim Spieth — Trails
  - Bohdan — Tungsten (Deepbass Remix)
  - Ness — In The Meanderings Of Shibuya
  - Henry Saiz & Tentacle — The Prophetess (Brian Cid Remix)
  - Blackbelt Andersen — Åpenbaring

### 2026-01-02 Shazam capture (new baseline)
- Raw Shazam log: `Training/patrice-baumel-halo-2024_shazam_20260102.txt`
- Final objc output: `Training/patrice-baumel-halo-2024_final_objc_shazam_20260102.txt`
- Defaults used in core:
  - UseStreamingMatch=YES
  - UseSignatureTimes=YES
  - HopSizeFrames=1048576
  - DownmixToMono=YES
  - ExcludeUnknownInputs=YES
  - SignatureWindowSeconds=8.0
  - SignatureWindowMaxSeconds=8.0
- Raw input stats (old vs new):
  - Old input: 371 lines, 118 unique keys, 8 unknowns (2.16%), last frame 255,852,544
  - New Shazam: 509 lines, 139 unique keys, 7 unknowns (1.38%), last frame 268,833,600
- Golden coverage in raw input (strict artist/title match):
  - Old input: 14/24 matched
  - New Shazam: 14/24 matched

### Objc refined eval (strict match)
- Old input + old final:
  - Eval output: `Training/patrice-baumel-halo-2024_eval_objc_newbaseline.txt`
  - Refined 10, Matched 8, Precision 0.800, Recall 0.333
- New Shazam + new final:
  - Eval output: `Training/patrice-baumel-halo-2024_eval_objc_shazam_20260102.txt`
  - Refined 19, Matched 13, Precision 0.684, Recall 0.542

### 2026-01-02 Shazam capture (non-streaming baseline)
- Raw Shazam log: `Training/patrice-baumel-halo-2024_shazam_nonstreaming_20260102.txt`
- Final objc output: `Training/patrice-baumel-halo-2024_final_objc_shazam_nonstreaming_20260102.txt`
- Eval output: `Training/patrice-baumel-halo-2024_eval_objc_shazam_nonstreaming_20260102.txt`
- Config: UseStreamingMatch=NO, UseSignatureTimes=YES, SignatureWindowSeconds=6.0, SignatureWindowMaxSeconds=8.0, HopSizeFrames=4096, DownmixToMono=NO
- Refined 20, Matched 14, Precision 0.700, Recall 0.583

### Streaming vs non-streaming A/B (Shazam)
- Delta is within noise: 1 FP swap (Wigbert Balance vs Sam Paganini Rave) and 1 golden miss difference (Burial New Love missing only in streaming). All other FPs and misses are shared.

### Reasoning
- Precision drop indicates more false positives, which usually points to refiner/normalization/overlap logic rather than input signal quality.
- Recall did not regress (it improved), which further suggests the signal is not worse; the post-processing is more permissive.
