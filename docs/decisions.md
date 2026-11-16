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

## Correction to the reporting definition (2026-11-16)
The legal deadline is for **submitting** results, not for posting them; posting follows after review. A first run using the posting date gave an implausibly low on-time rate (7% overall, 13% for US FDA-regulated trials), and the posting-based timing differed from AACT's own months_to_report_results by 4.5 months on average, consistent with the review lag. All reporting outcomes now use `results_first_submitted_date`:
- On time = results first submitted within 12 months of primary completion.
- Time to event = submission minus primary completion; trials with no submission are censored at the snapshot date.
- The posting date is kept only for descriptive tables.

## Results-reporting checks (after the submission-date fix)
- Submission-based timing agrees with AACT months_to_report_results (mean absolute difference 0.34 months; posting-based 4.46).
- On time (submitted within 12 months): industry 29.9%, other 16.7%, NIH 45.1%; US-facility and FDA-regulated 45.7% vs 7.5-10% where neither applies; trend among US-facility trials 18.7% (2008 starts) to about 47-50% (2020-2021 starts).
- Applicability proxy `likely_applicable` = US facility and not marked non-FDA-regulated (is_fda_regulated_drug missing is treated as possibly applicable because the field only exists for newer registrations). Main reporting analyses use this subset; the all-trials model is a comparison.

## Model specification (SAS)
- Termination: logistic regression, COMPLETED vs TERMINATED, sponsor-clustered robust SEs (PROC SURVEYLOGISTIC), AUC and Hosmer-Lemeshow from PROC LOGISTIC. Predictors: sponsor class, phase, start period, allocation, intervention model, primary purpose, masking, US site, sex eligibility, arms, primary outcomes, interventions, countries, biological, other intervention type, six therapeutic-area flags. Enrollment excluded. Reference level = most frequent level.
- Sensitivity: start year <= 2018; withdrawn counted as early stops.
- Reporting: Kaplan-Meier (cumulative submission) by sponsor class and start period; Cox with robust sponsor-clustered variance; logistic model for late (> 12 months or never) among trials with >= 12 months of follow-up; proportional hazards check (resampling first, then a two-window comparison, see results below).

## SAS data handling (2026-11-16)
- 12 trials with missing sex eligibility, none terminated, caused quasi-complete separation (odds ratio not estimable); they are treated as `ALL` (no restriction recorded).
- Other missing categories are kept as their own level, shown in the tables and left off the forest plot.

## Findings that shape the modelling
- **Enrollment is not a valid predictor of termination.** AACT keeps one enrollment value, which becomes the actual count at completion; terminated trials have a median of 24 against 100 for completed ones. That is a consequence of the outcome, so it is described but left out of the termination model (reverse causation / leakage). Planned enrollment is not available in this snapshot.
- **Rising termination share by start year (about 15% for 2008-2016 to 21-23% for 2019-2022) is partly a selection effect.** Only resolved trials are kept; for recent starts, short trials and early terminations resolve first. Plan: sensitivity analysis restricted to earlier start years (for example 2008-2018) and a time-to-termination model.
- **is_fda_regulated_drug is 54.6% missing** (field exists for newer registrations only). The reporting-applicability flag uses has_us_facility (5.7% missing); FDA-regulated is a subset sensitivity analysis.
- **Sponsor-level variation is large** (for example 0.7% to 34% terminated among sponsors with at least 50 trials), so models use sponsor-clustered standard errors (or a sponsor random effect).
- **Recent-year reporting rates are right-censored** (ever-posted falls from 93% for 2017 starts to 75% for 2022 starts); the time-to-event model handles this.
- Descriptive signals (not yet adjusted): oncology 25.5% terminated vs infectious 14.4%; Phase 2 20.1% vs Phase 3 13.7%; industry 15.8%, other 19.9%, other government 9.5%.

## Cleaning rules (counts from 04_quality_checks.sql, cohort of 46,801)
| Rule | Affected | Action |
|---|---|---|
| Primary completion before start date | 8 | Excluded from the reporting dataset |
| Results submitted before primary completion | 149 | Excluded from the reporting dataset |
| Completed or terminated with missing primary completion | 33 | Excluded from the reporting dataset |
| Completed with completion after snapshot | 0 | None needed |
| Terminated without why_stopped | 639 | Kept; reason is not a model input |
| Unknown sponsor class | 8 | Excluded from both datasets |
| Completed with enrollment 0 | 2 | Kept; enrollment is not a termination predictor |
| Duplicated nct_id, or trials with several lead sponsors | 0 | None needed |

Analysis populations (05_analysis_dataset.sql): termination dataset 44,157 trials (7,734 terminated); reporting dataset 43,975 trials (25,024 submissions); 190 trials hit at least one date flag.

## Log
- 2026-11-16: question confirmed; snapshot restored and row count verified.
- 2026-11-16: indexes built; cohort defined (46,801 trials); features table built (46,801 rows); windows and quality scripts added.
- 2026-11-16: SAS models run (termination, reporting). us_site dropped from applicable-subset models (constant). Resampling PH check exhausted SAS OnDemand work space and time, so it was replaced by a two-window Cox comparison (03b).

## Results (2026-11-16)
- Termination model: n = 44,157, 7,734 terminated; AUC 0.658; Hosmer-Lemeshow p = 0.92. Largest odds ratios: oncology 1.63, start 2020-2022 1.66, sequential design 1.51; lowest: crossover 0.66, no US site 0.53, Phase 3 0.76. Not stable across sensitivity analyses: number of countries (1.09, 1.03, 1.00) and infectious area (0.99, 0.78, 0.97); reported as non-robust.
- Withdrawn-counted sensitivity: unknown US-site OR rises to 3.16 (withdrawn trials rarely list facilities). One rare level (DEVICE_FEASIBILITY) is not estimable (OR > 999); it is not interpreted.
- Time to submission (likely applicable, n = 22,668; 19,094 submitted): within 12 months 20% (2008-2011), 33%, 44%, 48% (2020-2022); medians 896, 543, 402, 371 days. By sponsor class at 12 months: NIH 44%, other 36%, industry 34%, FED 28%.
- Late reporting (n = 22,346 with >= 12 months follow-up; 14,482 late = 64.8%): AUC 0.712; OR 0.24 for 2020-2022, 0.51 per log(1+countries), NIH 0.37, other 0.52, terminated 0.96 (CI 0.87-1.07, null).
- Proportional hazards violated (resampling p < 0.0001 for sponsor class OTHER; effects differ before and after 365 days: start 2020-2022 HR 2.79 vs 1.99; countries 1.60 vs 1.23; terminated 1.07 vs 0.81). Overall Cox HRs are reported as averages over follow-up; the deadline-aligned logistic model is the primary reporting result.
- Crude vs adjusted: among all trials with >= 12 months follow-up, other sponsors are late in 84% (industry 70%) but have lower adjusted odds of lateness (0.52); explained by start period and country count.
