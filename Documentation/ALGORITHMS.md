# Algorithm specification — version 3

The research sources and repository review behind these choices are tracked in
[RESEARCH-RESOURCES.md](RESEARCH-RESOURCES.md). The formulas below are Veyra
wellness estimates and must not be described as Bevel's private algorithms.

All formulas are independent wellness estimates; they are not Bevel's formulas. Units: bpm, HRV SDNN milliseconds, temperature Celsius, SpO2 percent, duration minutes, mass kg, distance meters, energy kcal.

Baseline: last 42 finite daily observations, median, MAD × 1.4826, z bounded ±3. Minimum 7 observations; low confidence 7–13, medium 14–27, high 28+. Epsilon is metric-specific (HR 1 bpm, temperature .1 °C, oxygen 1 percentage point). Consistent SDNN baseline; RR RMSSD utility is separate.

Recovery: HRV 30%, RHR 20%, sleep 25%, respiratory 10%, temperature 10%, SpO2 5%. HRV contributor = 70+15z; RHR=70−15z; respiratory and temperature=85−15|z|; oxygen=85+15min(0,z). All contributors bounded 0–100. Missing contributors removed from the weighted denominator. Require a calibrated physiological contributor; sleep alone is not Recovery.

Sleep: select one source per sleep import interval, prefer Apple source unless configured. Resolve overlapping intervals into nonoverlapping stages, detailed stages override unspecified/in-bed. Separate sessions after 90-minute unrecorded gap; sessions under 15 asleep minutes excluded. Main session has most asleep minutes; others are naps. Duration score=min(100,actual/need×100), efficiency=asleep/session span×100, continuity=100−.8×max(0,awakeMinutes−10), stage score=85−15|personal stage-fraction z| after 7 observations, consistency=100−.6×circular onset SD in minutes, HR dip=5×dip%. Weights 35/20/15/15/10/5; absent optional contributors renormalized. Need=clamp(base+.35×previousDebt capped120 + .4×previousStrain capped60,360,600). Debt=clamp(.85×previousDebt+need−allSleep,0,240). A missing night does not create debt.

Strain v2: HR reserve zones 50/60/70/80/90%; Edwards load=minutes×zone1…5. Passive load=max(0,daily active kcal−workout kcal)×.06. Raw load=zone load+passive load. Effort=100×(1−exp(−raw/personalScale)), bounded 0–100; personalScale=max(120, 42-day raw-load P75 or150). A personal P75 day therefore scores about63 rather than100; 100 is reserved for unusually large workloads. Target=14-day median effort×(.65+.7×recovery/100), ±10%; break×.7, sick/injured×.5. Cardio load EWMAs use 1−exp(−1/7),1−exp(−1/42); calibration14days.

Stress: 15-minute bins, no workout bins. HR activation=30+22z(HR vs personal RHR; epsilon5bpm); HRV activation=30−22z(epsilon3ms) only if a sample is within30min; weights55/35/10 and renormalize. A personal reference needs three observations for a provisional low-confidence value and seven days for normal calibration; before that, the lower tenth percentile of at least three actual HR samples from the day is used as a provisional reference. Context component subtracts40×movement. Sparse bins remain gaps. This estimate is physiological activation, not psychological diagnosis.

Energy: first morning=.65×recovery+.35×sleep; subsequent=.30×previousEnd+.45×recovery+.25×sleep. Each15min: baseline drain .25, stress drain2.5×(max(0,stress−35)/65)^1.5, load drain .1×new load, restoration .9 when observed stress<25, nap bonus min(12,.15×minutes). Missing stress bins marked predicted and use35 only for prediction. Bound0–100.

Strength: Epley for1–12reps (single rep=weight). Set load=reps×max(.1,weight/e1RM)^1.5×RPE/10. No inference of weight from watch motion. Plate calculator returns plates per side and unmet load.

Journal: ≥5 explicitly recorded yes and ≥5 explicitly recorded no observations. Mean difference and1000 deterministic bootstrap resamples, percentile95%interval. Unlogged days do not count as no. Associations do not establish causation.

Nutrition: protein25,fiber25,water15,sodium15,sugar10,saturatedFat10. Target fulfillment for positive nutrients; excess penalty100−70×max(0,value/limit−1) for limit nutrients. Omitted nutrients are unavailable, not zero.

Cycle: next period uses median observed cycle length15–60days; requires3 recorded starts. Trends: least-squares projection only after14 observations spanning14days, labeled estimate. Wellness age remains explicitly experimental, requires actual inputs and shows its contributing heuristic.

## Body battery v2 — 2026-09-07

Experimental, unvalidated 0–100 estimate; not a direct measurement of physiological reserves.
Requires a scored sleep session. With recovery available, starting value is
0.65 × recovery + 0.35 × sleep, or 0.30 × prior evening energy + 0.45 × recovery
+ 0.25 × sleep when the prior value is finite. Without recovery, sleep alone
provides a provisional low-confidence starting estimate.

Each 15-minute interval drains 0.25 points for waking time, plus
2.5 × (max(0, stress − 35) / 65)^1.5 and 0.1 × workout zone load allocated by
actual overlap. Observed low stress (<25) restores 0.9 points; sleep within a
nap restores 0.15 points/minute. Results are clamped to 0–100. Missing stress
removes stress-dependent drain/restoration and marks the interval predicted.
Nonfinite inputs are rejected or ignored. No data produces no score.

The UI displays net positive/negative changes between consecutive timeline
points, not independent gross charge and drain. Light dots mark predicted
intervals. All results retain low confidence; this has not been clinically
validated. Historic stored v1 results retain their own version until recalculated.


## Version 3 — 2026-09-13

Bumped because stored numbers change meaning. Diagnostics offers a forced
recalculation; snapshots keep their own `algorithmVersion` until recomputed.

**Confidence as a percentage.** `ConfidenceEngine` returns
`100 × coverage × maturity × recency`. Coverage is the share of a score's weight
that had real data; maturity is `1 − exp(−3n/target)` over the days of personal
baseline (target 28 by default, 14 for sleep and stress); recency decays from
one day old and floors at 0.25. The four-step `Confidence` enum is derived from
the percentage (<20 insufficient, <45 low, <70 medium, else high) so stored
snapshots and existing screens keep working. Each report also names what is
holding it down, and those reasons are shown to the user.

**Recovery** now needs three baseline observations instead of seven. The result
is reported with a correspondingly low percentage rather than withheld, which
previously left the app silent for a full week after install.

**Heart-rate zones** use the configured maximum heart rate instead of a
hardcoded 185 bpm, and the resting reference is the workout's own day rather
than the median of the entire imported window.

**Stress** receives real movement: step counts bucketed to the same 15-minute
grid, normalised against 250 steps per bucket. Its 10%-weighted movement
component previously received a constant zero, which reduced it to a duplicate
of the heart-rate component.

**Sleep** computes the overnight heart-rate dip that its 5% contributor always
expected and never received: the tenth percentile of in-night samples against
the median of the waking samples framing it, as a percentage, capped at 40.

**Strain** includes strength work. Set load (`StrengthEngine.load`) is summed
per day and added to `rawLoad`, because muscular work is invisible to heart-rate
zones and a heavy lifting session previously produced no strain at all. Weights
are now zone 55 / strength 20 / non-workout activity 25.

**Energy v3** simulates from the onset of the night rather than from waking, so
the overnight recharge is visible. The ramp rate is derived from the scored
night (`(morning − nightStart) / asleepMinutes`) instead of a fixed speed.
Sleeping suspends the waking baseline cost and the stress drain. A day with no
scored night carries the previous evening's level forward instead of producing
nothing. Every 15-minute step now records its own restoration, stress drain,
load drain and baseline drain, which is what the battery breakdown displays.
Confidence is additionally scaled by the share of intervals that had an observed
stress sample.

**Wellness age** answers from the first day. The fourteen-day gate is gone;
instead the correction is multiplied by the confidence fraction, so with one day
of data the estimate stays close to the chronological age, and a margin of
`1 + 7 × (1 − confidence)` years is shown alongside it. Absent signals are
listed as absent rather than dropped. Chronological age comes from the user's
stored birth date.

Removed in this version: the nutrition score, the remote coaching provider and
the conversational assistant. Metric narration is now a deterministic local
function (`MetricNarrator`) returning localisation keys and arguments.

## Wellness age — version 2 (2026-09-13)

### Why this is not a biological age

The published methods for biological age — Klemera–Doubal and PhenoAge — are
built on blood chemistry: albumin, creatinine, glucose, C-reactive protein,
lymphocyte percentage, mean cell volume, red cell distribution width, alkaline
phosphatase and white cell count, alongside chronological age. A wrist wearable
measures none of these. Any app deriving a "biological age" from a watch alone
is doing something else, and Veyra says so on screen.

- Klemera & Doubal, *Mech Ageing Dev* (2006) — the KDM estimator.
- Levine et al., *Aging* (2018) — PhenoAge.
- [BioAge toolkit](https://pmc.ncbi.nlm.nih.gov/articles/PMC8602613/) —
  reference implementations of both.
- [Methods for the assessment of biological age, systematic review (2025)](https://www.sciencedirect.com/science/article/pii/S0378512225000234)

### What a watch can anchor

Cardiorespiratory fitness. VO2max has published normative curves by age and sex
and Apple Watch writes an estimate to HealthKit, so the curve can be inverted:
"your VO2max equals the median for an N-year-old". This is the only part of the
estimate with a defensible external reference, and it carries the largest weight.

Reference curves are linear fits to the ACSM "average" bands, whose decade
midpoints run 39 → 24.5 mL/kg/min for men and 33 → 21.5 for women between ages
25 and 75:

    expected(age, male)   = 39.0 − 0.29 × (age − 25)
    expected(age, female) = 33.0 − 0.23 × (age − 25)
    fitnessAge            = 25 + (intercept − VO2) / slope,  clamped to 20…100

The floor at 20 is a limit of the reference, not of the user; when a measurement
falls below it the screen shows "≤ 20" and says why. Without a declared
biological sex there is no curve to invert and no fitness age is produced.

- [ACSM Guidelines for Exercise Testing and Prescription, 11th ed. (2021), normative tables](https://openspiro.com/knowledge/vo2max-reference-values/)
- [Mayo Clinic Proceedings — FRIEND registry reference standards](https://www.mayoclinicproceedings.org/article/S0025-6196(15)00642-4/pdf)
- [Nes et al., HUNT Study — non-exercise VO2peak estimation](https://www.semanticscholar.org/paper/Estimating-V%C2%B7O-2peak-from-a-nonexercise-prediction-Nes-Janszky/cff3dbccaa041b33f2b0a34a9554c17a9d2340e1)

### Signals and weights

Each signal maps to a bounded number of years. Weights are applied over the
signals that are actually present, so a missing signal is not silently treated
as neutral.

| Signal | Weight | Years | Reference |
| --- | --- | --- | --- |
| VO2max | 35 | fitnessAge − age, ±15 | ACSM curve above |
| Resting heart rate | 15 | (rhr − 60) / 10 × 2.5, ±5 | 60 bpm |
| HRV (SDNN) | 10 | (expected − hrv) / expected × 10, ±5 | 60 − 0.45 × (age − 20) ms |
| Sleep score | 10 | (75 − score) / 12, ±3 | 75 |
| Sleep regularity | 5 | (deviation − 45) / 40, −1.5…+2.5 | 45 min circular SD |
| Steps | 8 | (7 500 − steps) / 2 500, ±3 | 7 500/day |
| Training minutes | 12 | (150 − weekly) / 75, ±3 | WHO 150 min/week |
| Stress | 5 | (stress − 35) / 15, −2…+3 | 35 activation |
| Body fat, else BMI | 5 | penalty only, 0…3 | ACE fitness band / BMI 22 |

Training minutes take the larger of Apple exercise minutes and recorded workout
minutes per day rather than their sum, because the two overlap and summing them
would double-count one session. Body composition is a penalty only: being near
the reference is not evidence of being younger.

The weighted mean is clamped to ±15 years, then multiplied by the confidence
fraction, so a first-week estimate stays close to the chronological age instead
of asserting a swing it cannot support. The plausible range is
`1.5 + 8 × (1 − confidence)` years. Without VO2max the confidence is additionally
scaled by 0.6 and the missing anchor is named on screen.

The estimate is stored and recalibrated weekly, not recomputed on every redraw,
so the displayed number is stable between recalibrations. A button forces one.


## Stress — version 3 (2026-09-13)

The previous version compared the day's heart rate against a baseline built
from *resting* heart-rate samples. Awake, you are always above your resting
rate, so the z-score saturated at its ±3 bound and the result sat at
`30 + 3 × 22 = 96` for essentially the whole day.

That also emptied the body battery: the energy simulation drains
`((stress − 35) / 65)^1.5 × 2.5` points every fifteen minutes, which at a pinned
96 is roughly nine points an hour, or over a hundred across a waking day.

Activation is now heart-rate reserve, the standard framing:

    reserve    = clamp((hr − resting) / (maximum − resting), 0, 1)
    activation = clamp(reserve / 0.45 × 100)

Reserve is bounded by construction, so it cannot pin, and it means the same
thing for a trained and an untrained heart. Forty-five percent of reserve is
treated as full activation; beyond that the interval is effort rather than
stress, and workout intervals are excluded outright.

Weights: heart rate 60, HRV 30 (only once the personal baseline has at least
three observations), movement 10. Movement is context rather than a signal —
a raised rate that movement explains is discounted, not counted.

The resting reference is the day's own resting sample where one exists, then the
personal median, then the fifth percentile of the day's actual samples.

Regression test: `testStressReadsHeartRateReserveAndCannotPin` asserts that
ordinary waking rates from 70 to 100 bpm never read as extreme activation.
