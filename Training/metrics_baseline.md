Baseline metrics for `PlayEmTests` detection runs.

```json
{
  "fixture": "test_set_patrice.m4a",
  "hop_size_frames": 1310720,
  "hop_size_note": "Quality-first default: 4096*320 (~2.5s); smaller (4096*128) and larger (4096*512) hurt coverage/order.",
  "pacing_note": "Locked pacing: in-flight gate = 1, adaptive cadence from average response latency, no EMA/backoff.",
  "jitter_note": "Set PLAYEM_JITTER_RUNS to N to run the detection test N times and print summary stats (currently capped at 5).",
  "golden_min_matches": 2,
  "golden_hits_min": {
    "yotto - seat 11": 1,
    "tigerskin & alfa state - slippery roads (pablo bolivar remix)": 1,
    "saktu - muted glow (extended mix)": 0
  },
  "total_hits_min": 2,
  "total_hits_max": 6,
  "unexpected_max": 3
}
```
