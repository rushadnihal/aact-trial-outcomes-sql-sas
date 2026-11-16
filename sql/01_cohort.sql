-- =====================================================================
-- 01_cohort.sql
-- Purpose : Define the analysis cohort (interventional Phase 2/3 drug or
--           biological trials) with a step-by-step flow table, and create
--           the view analysis.cohort_base (one row per trial).
-- Inputs  : ctgov.studies, ctgov.interventions, ctgov.sponsors
-- Outputs : Flow table (printed); view analysis.cohort_base
-- Snapshot: AACT 2026-11-15
-- Run     : (after 00b_indexes.sql) psql -U postgres -h localhost -d aact -f sql/01_cohort.sql > logs/01.log
-- Config  : edit the \set lines below; nothing else is hard-coded.
-- =====================================================================

\set snapshot_date '2026-11-15'
\set window_start  '2008-01-01'
\set window_end    '2022-12-31'

CREATE SCHEMA IF NOT EXISTS analysis;

-- ---------------------------------------------------------------------
-- Base: one row per study with the fields used to define the cohort
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS analysis.cohort_base CASCADE;   -- also drops dependent views (quality_flags, model_*); rerun 04 and 05
DROP VIEW IF EXISTS analysis.study_base CASCADE;

CREATE VIEW analysis.study_base AS
SELECT s.nct_id,
       s.study_type,
       s.phase,
       s.overall_status,
       s.why_stopped,
       s.start_date,
       s.primary_completion_date,
       s.completion_date,
       s.results_first_submitted_date,
       s.results_first_posted_date,
       s.enrollment,
       s.enrollment_type,
       s.is_fda_regulated_drug,
       COALESCE(d.has_drug_or_bio, FALSE) AS has_drug_or_bio
FROM ctgov.studies s
LEFT JOIN (SELECT DISTINCT nct_id, TRUE AS has_drug_or_bio
           FROM ctgov.interventions
           WHERE intervention_type IN ('DRUG', 'BIOLOGICAL')) d
       ON d.nct_id = s.nct_id;

-- ---------------------------------------------------------------------
-- Cohort flow table (cumulative; each row applies one more rule)
-- ---------------------------------------------------------------------
\echo '=== Cohort flow (snapshot :snapshot_date, window :window_start to :window_end) ==='
WITH flow AS (
  SELECT 0 AS step, 'All registered studies' AS description, count(*) AS n
    FROM analysis.study_base
  UNION ALL
  SELECT 1, 'Interventional', count(*)
    FROM analysis.study_base
   WHERE study_type = 'INTERVENTIONAL'
  UNION ALL
  SELECT 2, 'Phase 2, Phase 2/3 or Phase 3', count(*)
    FROM analysis.study_base
   WHERE study_type = 'INTERVENTIONAL'
     AND phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
  UNION ALL
  SELECT 3, 'At least one DRUG or BIOLOGICAL intervention', count(*)
    FROM analysis.study_base
   WHERE study_type = 'INTERVENTIONAL'
     AND phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
     AND has_drug_or_bio
  UNION ALL
  SELECT 4, 'Start date present', count(*)
    FROM analysis.study_base
   WHERE study_type = 'INTERVENTIONAL'
     AND phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
     AND has_drug_or_bio
     AND start_date IS NOT NULL
  UNION ALL
  SELECT 5, 'Start date within window', count(*)
    FROM analysis.study_base
   WHERE study_type = 'INTERVENTIONAL'
     AND phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
     AND has_drug_or_bio
     AND start_date BETWEEN :'window_start' AND :'window_end'
  UNION ALL
  SELECT 6, 'Final status COMPLETED, TERMINATED or WITHDRAWN (drops UNKNOWN, ongoing, suspended)', count(*)
    FROM analysis.study_base
   WHERE study_type = 'INTERVENTIONAL'
     AND phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
     AND has_drug_or_bio
     AND start_date BETWEEN :'window_start' AND :'window_end'
     AND overall_status IN ('COMPLETED', 'TERMINATED', 'WITHDRAWN')
)
SELECT step, description, n,
       n - lag(n) OVER (ORDER BY step) AS change_from_previous
FROM flow
ORDER BY step;

-- ---------------------------------------------------------------------
-- Cohort view (one row per trial) with outcome definitions
-- ---------------------------------------------------------------------
CREATE VIEW analysis.cohort_base AS
SELECT b.*,
       CASE b.overall_status
            WHEN 'COMPLETED'  THEN 0
            WHEN 'TERMINATED' THEN 1
       END AS terminated_flag,           -- NULL for WITHDRAWN (handled separately)
       (b.overall_status = 'WITHDRAWN')  AS withdrawn_flag,
       (b.results_first_posted_date IS NOT NULL) AS results_posted_flag,
       (b.results_first_posted_date - b.primary_completion_date) AS days_to_results
FROM analysis.study_base b
WHERE b.study_type = 'INTERVENTIONAL'
  AND b.phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
  AND b.has_drug_or_bio
  AND b.start_date BETWEEN :'window_start' AND :'window_end'
  AND b.overall_status IN ('COMPLETED', 'TERMINATED', 'WITHDRAWN');

-- ---------------------------------------------------------------------
-- Quick profile of the cohort (used to finalise decisions in docs/decisions.md)
-- ---------------------------------------------------------------------
\echo ''
\echo '=== Cohort by status ==='
SELECT overall_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM analysis.cohort_base GROUP BY 1 ORDER BY n DESC;

\echo ''
\echo '=== Cohort by phase ==='
SELECT phase, count(*) AS n FROM analysis.cohort_base GROUP BY 1 ORDER BY n DESC;

\echo ''
\echo '=== Results posting (COMPLETED or TERMINATED only) ==='
SELECT overall_status,
       count(*) AS n,
       count(*) FILTER (WHERE results_posted_flag) AS n_results_posted,
       round(100.0 * count(*) FILTER (WHERE results_posted_flag) / count(*), 1) AS pct_posted,
       count(*) FILTER (WHERE primary_completion_date IS NULL) AS n_missing_pcd
FROM analysis.cohort_base
WHERE overall_status IN ('COMPLETED', 'TERMINATED')
GROUP BY 1;

\echo ''
\echo '=== Impossible or odd dates inside the cohort ==='
SELECT count(*) FILTER (WHERE primary_completion_date < start_date)        AS pcd_before_start,
       count(*) FILTER (WHERE results_first_posted_date < primary_completion_date) AS results_before_pcd,
       count(*) FILTER (WHERE primary_completion_date > :'snapshot_date'::date)    AS pcd_after_snapshot
FROM analysis.cohort_base;

\echo ''
\echo '=== why_stopped populated (TERMINATED / WITHDRAWN) ==='
SELECT overall_status, count(*) AS n,
       count(*) FILTER (WHERE why_stopped IS NOT NULL) AS n_with_reason
FROM analysis.cohort_base
WHERE overall_status IN ('TERMINATED', 'WITHDRAWN') GROUP BY 1;

\echo ''
\echo '=== Intervention types across the cohort ==='
SELECT i.intervention_type, count(DISTINCT i.nct_id) AS n_trials
FROM ctgov.interventions i JOIN analysis.cohort_base c USING (nct_id)
GROUP BY 1 ORDER BY n_trials DESC;

\echo ''
\echo '=== Lead sponsor class across the cohort ==='
SELECT sp.agency_class, count(DISTINCT sp.nct_id) AS n_trials
FROM ctgov.sponsors sp JOIN analysis.cohort_base c USING (nct_id)
WHERE sp.lead_or_collaborator = 'lead'
GROUP BY 1 ORDER BY n_trials DESC;
