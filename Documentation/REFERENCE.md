# Reference freeze — 2026-09-05

Reference: https://help.bevel.health/en/articles/11194113 (3.1.4 and above listing), https://www.bevel.health/ and https://help.bevel.health/en/articles/11586817.

Original brief is the user supplied 111-section master prompt. The implementation instruction supersedes only the original-design requirement. This is an independent implementation named PulseLab. Bevel's private formulas and assets are not included.

## Screen inventory
- Home: date navigation, three primary score rings, coaching summary, health monitor, stress and energy timelines, activity, nutrition, journal. Card visibility/order editable.
- Score details: score, date, category, contributor values/baselines, time-range selector and history chart; sleep adds stages and sessions; stress/energy show time bins.
- Fitness: load/trends, activities, strength templates, workout detail, exercise search, active strength session, history and plate calculator.
- Nutrition: energy/macros/water, diary, manual editor, product lookup, scan review, custom foods and recipes.
- Biology: vitals, cycle, health records and experimental wellness age.
- Intelligence: conversation, suggested queries, preferences, editable memory and planning.
- Settings: Health connection, sync window/source, goals, units, appearance, alarm, notifications, privacy, diagnostics, export/delete.
- Watch: summary, metric details, workout types, live workout, strength, water, alarm; accessory and Smart Stack widgets.

## Reference limitations
Public descriptions establish behavior and information hierarchy. Direct CDN image inspection was blocked by browser site-safety policy. Pixel equality and unseen screens cannot be verified against those images in this session. No screenshots are embedded as application UI. Keep this limitation in the final QA report.

## Shared states
Each metric supports loading, no records, insufficient baseline, partial quality, current and stale. Every service supports actionable failure/retry. Never convert missing HealthKit read results to a claim that read permission was denied.
