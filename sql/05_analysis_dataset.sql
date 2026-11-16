-- =====================================================================
-- 05_analysis_dataset.sql
-- Purpose : Final modelling views and CSV exports for SAS.
--           model_termination : COMPLETED vs TERMINATED (logistic model)
--           term_base / model_termination_sens : adds WITHDRAWN (sensitivity)
--           model_reporting   : time from primary completion to results
--                               submission, censored at the snapshot date
--                               (Kaplan-Meier, Cox) plus a binary late flag
-- Inputs  : analysis.features, analysis.quality_flags
-- Outputs : Views analysis.model_termination, analysis.model_reporting;
--           output/model_termination.csv, output/model_reporting.csv
-- Snapshot: AACT 2026-11-15
-- Run     : from the repo root (so the relative output/ path resolves):
--           psql -U postgres -h localhost -d aact -f sql/05_analysis_dataset.sql > logs/05.log
-- Notes   : Enrollment is deliberately excluded from the termination model
--           (it is the actual count after the outcome). n_countries and
--           has_us_facility reflect the final registry record; interpret
--           with that caveat.
-- =====================================================================

\set snapshot_date '2026-11-15'

DROP VIEW IF EXISTS analysis.term_base CASCADE;   -- also drops model_termination
DROP VIEW IF EXISTS analysis.model_reporting;

-- ---------------------------------------------------------------------
-- Termination model dataset
-- Rule: COMPLETED or TERMINATED only (WITHDRAWN is a sensitivity analysis);
--       drops 8 trials with unknown sponsor class.
-- ---------------------------------------------------------------------
CREATE VIEW analysis.term_base AS
SELECT f.nct_id,
       f.overall_status,
       f.terminated_flag,
       (f.overall_status <> 'COMPLETED')::int AS any_stop_flag,   -- sensitivity outcome: terminated or withdrawn
       f.sponsor_name,
       f.sponsor_class,
       f.phase,
       f.start_year,
       f.allocation,
       f.intervention_model,
       f.primary_purpose,
       f.masking,
       f.n_arms,
       f.n_primary_outcomes,
       f.n_interventions,
       f.has_biological::int AS has_biological,
       f.has_other_type::int AS has_other_type,
       f.n_countries,
       f.has_us_facility::int AS has_us_facility,
       f.gender,
       f.healthy_volunteers,
       CASE WHEN lower(f.minimum_age_unit) LIKE 'year%'   THEN f.minimum_age_num::numeric
            WHEN lower(f.minimum_age_unit) LIKE 'month%'  THEN f.minimum_age_num / 12.0
            WHEN lower(f.minimum_age_unit) LIKE 'week%'   THEN f.minimum_age_num / 52.18
            WHEN lower(f.minimum_age_unit) LIKE 'day%'    THEN f.minimum_age_num / 365.25
            WHEN lower(f.minimum_age_unit) LIKE 'hour%'   THEN f.minimum_age_num / 8766.0
            WHEN lower(f.minimum_age_unit) LIKE 'minute%' THEN f.minimum_age_num / 525960.0
       END AS min_age_years,
       f.area_oncology::int AS area_oncology, f.area_cns::int AS area_cns,
       f.area_cardiovascular::int AS area_cardiovascular, f.area_infectious::int AS area_infectious,
       f.area_metabolic::int AS area_metabolic, f.area_respiratory::int AS area_respiratory,
       f.area_immune::int AS area_immune
FROM analysis.features f
JOIN analysis.quality_flags q USING (nct_id)
WHERE f.overall_status IN ('COMPLETED', 'TERMINATED', 'WITHDRAWN')
  AND NOT q.flag_unknown_sponsor_class;

-- Primary termination model: COMPLETED vs TERMINATED
CREATE VIEW analysis.model_termination AS
SELECT * FROM analysis.term_base WHERE terminated_flag IS NOT NULL;

-- ---------------------------------------------------------------------
-- Results-reporting dataset
-- Rule: COMPLETED or TERMINATED with a usable primary completion date.
--       Excludes date-flagged trials (completion before start, results
--       submitted before completion, completed with completion after the
--       snapshot, missing completion date) and unknown sponsor class.
-- time_days  : submission minus completion, or snapshot minus completion if none
-- event      : 1 = results submitted by the snapshot, 0 = censored
-- late_12m   : defined only with >= 12 months of follow-up;
--              1 = never submitted or submitted more than 12 months after completion
-- ---------------------------------------------------------------------
CREATE VIEW analysis.model_reporting AS
SELECT f.nct_id,
       f.overall_status,
       f.terminated_flag,
       f.sponsor_name,
       f.sponsor_class,
       f.phase,
       f.start_year,
       f.has_us_facility::int AS has_us_facility,
       f.is_fda_regulated_drug::int AS is_fda_regulated_drug,
       -- proxy for the US reporting requirement: US facility and not marked non-FDA-regulated
       (COALESCE(f.has_us_facility, FALSE) AND COALESCE(f.is_fda_regulated_drug, TRUE))::int AS likely_applicable,
       f.allocation,
       f.masking,
       f.primary_purpose,
       f.n_arms,
       f.n_primary_outcomes,
       f.n_countries,
       f.has_biological::int AS has_biological,
       f.area_oncology::int AS area_oncology, f.area_cns::int AS area_cns,
       f.area_cardiovascular::int AS area_cardiovascular, f.area_infectious::int AS area_infectious,
       f.area_metabolic::int AS area_metabolic, f.area_respiratory::int AS area_respiratory,
       f.area_immune::int AS area_immune,
       f.primary_completion_date,
       f.results_first_submitted_date,
       EXTRACT(YEAR FROM f.primary_completion_date)::int AS completion_year,
       CASE WHEN f.results_submitted_flag
            THEN f.days_to_submission
            ELSE (:'snapshot_date'::date - f.primary_completion_date)
       END AS time_days,
       f.results_submitted_flag::int AS event,
       (f.primary_completion_date <= (:'snapshot_date'::date - INTERVAL '12 months')::date)::int AS eligible_12m,
       CASE WHEN f.primary_completion_date <= (:'snapshot_date'::date - INTERVAL '12 months')::date
            THEN (NOT f.results_submitted_flag
                  OR f.results_first_submitted_date > (f.primary_completion_date + INTERVAL '12 months')::date)::int
       END AS late_12m
FROM analysis.features f
JOIN analysis.quality_flags q USING (nct_id)
WHERE f.overall_status IN ('COMPLETED', 'TERMINATED')
  AND f.primary_completion_date IS NOT NULL
  AND NOT (q.flag_pcd_before_start OR q.flag_results_before_pcd
           OR q.flag_missing_pcd OR q.flag_completed_pcd_after_snapshot
           OR q.flag_unknown_sponsor_class);

-- ---------------------------------------------------------------------
-- Analysis population flow
-- ---------------------------------------------------------------------
\echo '=== Analysis population flow ==='
SELECT 1 AS step, 'Cohort (completed, terminated, withdrawn)' AS description, count(*) AS n
  FROM analysis.features
UNION ALL
SELECT 2, 'less WITHDRAWN (sensitivity analysis only)', count(*) FILTER (WHERE withdrawn_flag)
  FROM analysis.features
UNION ALL
SELECT 3, 'Termination model dataset (after unknown-sponsor-class rule)', count(*)
  FROM analysis.model_termination
UNION ALL
SELECT 4, '   of which terminated', count(*) FILTER (WHERE terminated_flag = 1)
  FROM analysis.model_termination
UNION ALL
SELECT 5, 'Reporting dataset (after date and sponsor rules)', count(*)
  FROM analysis.model_reporting
UNION ALL
SELECT 6, '   with results submitted by the snapshot (events)', count(*) FILTER (WHERE event = 1)
  FROM analysis.model_reporting
UNION ALL
SELECT 7, '   with >= 12 months follow-up (late_12m defined)', count(*) FILTER (WHERE eligible_12m = 1)
  FROM analysis.model_reporting
UNION ALL
SELECT 8, '   late_12m = 1', count(*) FILTER (WHERE late_12m = 1)
  FROM analysis.model_reporting
ORDER BY step;

\echo ''
\echo '=== Missing values in model_termination (count of NULLs per column) ==='
SELECT kv.key AS column_name, count(*) FILTER (WHERE kv.value = 'null'::jsonb) AS n_null
FROM analysis.model_termination m
CROSS JOIN LATERAL jsonb_each(to_jsonb(m)) AS kv
GROUP BY kv.key HAVING count(*) FILTER (WHERE kv.value = 'null'::jsonb) > 0
ORDER BY n_null DESC;

\echo ''
\echo '=== Minimum age units seen (check that min_age_years is now populated) ==='
SELECT minimum_age_unit, count(*) AS n,
       count(*) FILTER (WHERE min_age_years IS NOT NULL) AS n_min_age_years
FROM (SELECT f.minimum_age_unit, m.min_age_years
      FROM analysis.features f
      JOIN analysis.model_termination m USING (nct_id)) x
GROUP BY 1 ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- Exports for SAS (written to output/ on this computer; not committed)
-- ---------------------------------------------------------------------
\copy (SELECT * FROM analysis.model_termination ORDER BY nct_id) TO 'output/model_termination.csv' CSV HEADER
\copy (SELECT * FROM analysis.term_base ORDER BY nct_id) TO 'output/model_termination_sens.csv' CSV HEADER
\copy (SELECT * FROM analysis.model_reporting ORDER BY nct_id) TO 'output/model_reporting.csv' CSV HEADER
