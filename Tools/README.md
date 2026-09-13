# Tools

Scripts that generate committed data. They are not part of the app and are not
compiled into it; they exist so the catalogue can be rebuilt rather than being a
binary blob nobody can reproduce.

| File | What it does |
| --- | --- |
| `build-exercise-catalog.py` | Builds `Resources/exercises.json` and the artwork in `Resources/ExerciseArt/` from a checkout of the [Everkinetic dataset](https://github.com/everkinetic/data) at `/tmp/ekdata`. Converts the black-on-white PNGs to alpha masks, crops them to the figure and scales both frames of a pair by one factor |
| `exercise-name-translation.py` | Rule-based English → Spanish translation of the exercise names, with an explicit table for the 51 titles the rules could not reach cleanly |
| `exercise-steps-es.json` | The instruction translations, keyed by the original English sentence. Kept out of `Resources/` because the app never reads it — only the generator does |

Requires `pillow`. Run from the repository root:

```
git clone --depth 1 https://github.com/everkinetic/data.git /tmp/ekdata
python3 Tools/build-exercise-catalog.py
```
