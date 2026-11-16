# AACT: predictors of early termination and results reporting in interventional drug trials

SQL + SAS analysis of ClinicalTrials.gov data from the AACT database (snapshot **2026-11-15**).

**Question:** What predicts early termination, and late or missing results reporting, among interventional drug trials?

> Status: work in progress. Results are descriptive associations, not causal.

## Structure
```
sql/      numbered scripts, run in order against the local `aact` database
sas/      modelling programs on the exported analysis dataset
output/   figures and tables (PNG/PDF)
logs/     saved query and SAS logs
docs/     decisions, cohort flow, data dictionary subset
```

## Reproducing
1. Download the PostgreSQL dump for the snapshot date above from https://aact.ctti-clinicaltrials.org/downloads
2. Create the database and schema, then restore the study-level tables (see `docs/decisions.md`).
3. Run the scripts in `sql/` in numeric order.

Raw data and dumps are not stored in this repository.
