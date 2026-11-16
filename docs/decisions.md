# Decisions log

Snapshot: **AACT 2026-11-15** (postgres.dmp). Every number in the README refers to this snapshot.

## Research question
What predicts early termination, and late or missing results reporting, among interventional drug trials registered on ClinicalTrials.gov?
Results are descriptive associations, not causal. Related published analyses exist; this is an updated, reproducible analysis, not a first-of-its-kind claim.

## Why this question (chosen over enrollment shortfall and oncology termination trends)
- Large eligible cohort, so estimates are precise.
- A binary outcome (terminated) and a time-to-event outcome (completion to results posting) exercise both SQL and SAS modelling.
- Outcomes are cleanly recorded in AACT study-level fields.
- Relevant to clinical development and regulatory work.

## Proposed defaults (to confirm before 01_cohort.sql)
| Topic | Proposed default |
|---|---|
| Study type | INTERVENTIONAL |
| Intervention | At least one DRUG or BIOLOGICAL intervention |
| Phase | PHASE2, PHASE2/PHASE3, PHASE3 |
| Date window | Start date 2008-01-01 to 2022-12-31 (allows follow-up for reporting) |
| Early termination | overall_status TERMINATED; WITHDRAWN handled as a separate category or sensitivity analysis |
| Results reporting | Time from primary completion to results first posted; unposted trials censored at snapshot date |
| Reporting-required subset | Sensitivity analysis restricted to likely-applicable clinical trials |
| Unit of analysis | One row per trial; sponsor clustering as a sensitivity check |

## Environment
- PostgreSQL 18.7 on macOS (arm64), database `aact`, schema `ctgov`.
- Selective restore of 14 study-level tables (results-detail tables skipped). Database size 2.9 GB. `ctgov.studies` = 611,764 rows.
- Tables restored: studies, sponsors, designs, conditions, browse_conditions, interventions, browse_interventions, design_groups, calculated_values, countries, eligibilities, id_information, responsible_parties, keywords.

## Cohort results (snapshot 2026-11-15)
Flow: 611,764 registered, 466,855 interventional, 116,384 Phase 2/2-3/3, 102,981 with a drug or biological intervention, 102,005 with a start date, 60,840 started 2008-2022, 46,801 with final status COMPLETED, TERMINATED or WITHDRAWN.
Cohort: 36,431 completed (77.8%), 7,734 terminated (16.5%), 2,636 withdrawn (5.6%).
Raw results posting: 55.9% of completed, 62.1% of terminated. This mixes trials that must report with trials that do not, so the model needs a US or FDA-regulated flag.
Date checks inside the cohort: 8 with primary completion before start, 99 with results posted before primary completion, 19 with primary completion after the snapshot. Rules for these go in 04_quality_checks.sql.
Indexes did not survive the selective restore; 00b_indexes.sql rebuilds them.

## Outcome definitions (draft, to confirm)
- Early termination: COMPLETED = 0, TERMINATED = 1. WITHDRAWN trials never enrolled, so they are a separate outcome category (sensitivity analysis), not part of the primary model.
- Results reporting due date: 12 months after primary completion date (US requirement, window starts 2008 because the law took effect in late 2007).
- Late reporting: results first posted more than 12 months after primary completion. Trials with primary completion less than 12 months before the snapshot are excluded from the binary late-reporting outcome.
- Time to results (Kaplan-Meier, Cox): event = results first posted; trials without results are censored at the snapshot date 2026-11-15.
- Applicability flag: use is_fda_regulated_drug and has_us_facility; check how complete is_fda_regulated_drug is for trials started before 2017.

## Confirmed by owner (2026-11-16)
- Late reporting = results first posted more than 12 months after primary completion.
- WITHDRAWN trials are excluded from the primary termination model and reported as a sensitivity analysis.

## Findings that shape the modelling
- **Enrollment is not a valid predictor of termination.** AACT keeps one enrollment value, which becomes the actual count at completion; terminated trials have a median of 24 against 100 for completed ones. That is a consequence of the outcome, so it is described but left out of the termination model (reverse causation / leakage). Planned enrollment is not available in this snapshot.
- **Rising termination share by start year (about 15% for 2008-2016 to 21-23% for 2019-2022) is partly a selection effect.** Only resolved trials are kept; for recent starts, short trials and early terminations resolve first. Plan: sensitivity analysis restricted to earlier start years (for example 2008-2018) and a time-to-termination model.
- **is_fda_regulated_drug is 54.6% missing** (field exists for newer registrations only). The reporting-applicability flag uses has_us_facility (5.7% missing); FDA-regulated is a subset sensitivity analysis.
- Descriptive signals (not yet adjusted): oncology 25.5% terminated vs infectious 14.4%; Phase 2 20.1% vs Phase 3 13.7%; industry 15.8%, other 19.9%, other government 9.5%.

## Log
- 2026-11-16: question confirmed; snapshot restored and row count verified.
- 2026-11-16: indexes built; cohort defined (46,801 trials); features table built (46,801 rows); windows and quality scripts added.
