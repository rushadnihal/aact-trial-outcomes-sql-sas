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

## Log
- 2026-11-16: question confirmed; snapshot restored and row count verified.
