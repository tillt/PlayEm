# Training Sets

This folder holds training inputs, golden lists, and the mapping file that ties them together.

## Checklist

- Capture raw Shazam hits log -> `Training/<artist>-<set>_input.txt`
- Create golden tracklist -> `Training/<artist>-<set>_golden.txt`
- Add a mapping line to `Training/training_sets.txt`
- Run eval on the set

## File Naming

- Input: `Training/<artist>-<set>_input.txt`
- Golden: `Training/<artist>-<set>_golden.txt`

## Golden List Format

One per line:

```
HH:MM:SS Artist - Title
```

## Mapping Entry (Training/training_sets.txt)

```
sample=<absolute path to audio>
input=Training/<artist>-<set>_input.txt
golden=Training/<artist>-<set>_golden.txt
```

## Quick Eval

```
python3 Scripts/refine_experiments.py Training/<artist>-<set>_input.txt \
  --mode interval --cluster-gap-seconds 240 --min-support 2 --merge-window-seconds 60 \
  --short-seconds 90 --interval-min-seconds 120 > /tmp/<set>.log

python3 Scripts/eval_refine.py --relaxed Training/<artist>-<set>_golden.txt /tmp/<set>.log
```

## Blend-Noise Report (Tag Only)

```
python3 Scripts/report_refine.py /tmp/<set>.log --strong-support 8 --short-seconds 120
```
