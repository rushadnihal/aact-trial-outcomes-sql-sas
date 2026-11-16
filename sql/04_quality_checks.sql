-- =====================================================================
-- 04_quality_checks.sql
-- Purpose : Data quality checks. Counts duplicates and impossible or
--           inconsistent records, and creates analysis.quality_flags
--           (one row per cohort trial) so every cleaning rule is explicit
--           and each rule's affected-record count is documented.
-- Inputs  : analysis.features, analysis.cohort_base, ctgov.studies,
--           ctgov.sponsors
-- Outputs : View analysis.quality_flags; counts table (printed)
-- Snapshot: AACT 2026-11-15
-- Run     : psql -U postgres -h localhost -d aact -f sql/04_quality_checks.sql > logs/04.log
-- =====================================================================

\set snapshot_date '2026-11-15'

\echo '=== 1. Duplicates ==='
SELECT 'studies: rows minus distinct nct_id'  AS check_name,
       count(*) - count(DISTINCT nct_id)      AS n
FROM ctgov.studies
UNION ALL
SELECT 'features: rows minus distinct nct_id', count(*) - count(DISTINCT nct_id)
FROM analysis.features
UNION ALL
SELECT 'cohort trials with more than one lead sponsor', count(*)
FROM (SELECT s.nct_id FROM ctgov.sponsors s
      JOIN analysis.cohort_base c USING (nct_id)
      WHERE s.lead_or_collaborator = 'lead'
      GROUP BY s.nct_id HAVING count(*) > 1) x
UNION ALL
SELECT 'cohort trials with no lead sponsor', count(*)
FROM analysis.cohort_base c
WHERE NOT EXISTS (SELECT 1 FROM ctgov.sponsors s
                  WHERE s.nct_id = c.nct_id AND s.lead_or_collaborator = 'lead');

-- ---------------------------------------------------------------------
-- Per-trial flags. Flags do not delete rows; each analysis states which
-- flags it excludes (see docs/decisions.md).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS analysis.quality_flags CASCADE;
CREATE VIEW analysis.quality_flags AS
SELECT f.nct_id,
       COALESCE(f.primary_completion_date < f.start_date, FALSE)
         AS flag_pcd_before_start,
       COALESCE(f.results_first_submitted_date < f.primary_completion_date, FALSE)
         AS flag_results_before_pcd,
       COALESCE(f.primary_completion_date > :'snapshot_date'::date
                AND f.overall_status = 'COMPLETED', FALSE)
         AS flag_completed_pcd_after_snapshot,
       (f.primary_completion_date IS NULL
        AND f.overall_status IN ('COMPLETED', 'TERMINATED'))
         AS flag_missing_pcd,
       (f.overall_status = 'TERMINATED' AND c.why_stopped IS NULL)
         AS flag_terminated_no_reason,
       (f.overall_status = 'COMPLETED' AND c.why_stopped IS NOT NULL)
         AS flag_completed_with_reason,
       COALESCE(f.overall_status = 'COMPLETED' AND f.enrollment = 0, FALSE)
         AS flag_completed_zero_enrollment,
       (f.sponsor_class IS NULL OR f.sponsor_class = 'UNKNOWN')
         AS flag_unknown_sponsor_class
FROM analysis.features f
JOIN analysis.cohort_base c USING (nct_id);

\echo ''
\echo '=== 2. Records affected by each flag (cohort = all trials in analysis.features) ==='
WITH t AS (SELECT count(*) AS n_total FROM analysis.quality_flags)
SELECT rule, n_affected, round(100.0 * n_affected / n_total, 2) AS pct_of_cohort
FROM t,
LATERAL (VALUES
  ('primary completion before start date',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_pcd_before_start)),
  ('results submitted before primary completion',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_results_before_pcd)),
  ('COMPLETED but primary completion after snapshot',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_completed_pcd_after_snapshot)),
  ('COMPLETED or TERMINATED with missing primary completion',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_missing_pcd)),
  ('TERMINATED without why_stopped',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_terminated_no_reason)),
  ('COMPLETED with a why_stopped value',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_completed_with_reason)),
  ('COMPLETED with enrollment 0',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_completed_zero_enrollment)),
  ('unknown or missing sponsor class',
     (SELECT count(*) FROM analysis.quality_flags WHERE flag_unknown_sponsor_class))
) AS r(rule, n_affected)
ORDER BY n_affected DESC;

\echo ''
\echo '=== 3. Trials hit by at least one date flag (what the date rules would remove from timing analyses) ==='
SELECT count(*) AS n_any_date_flag
FROM analysis.quality_flags
WHERE flag_pcd_before_start OR flag_results_before_pcd
   OR flag_completed_pcd_after_snapshot OR flag_missing_pcd;

\echo ''
\echo '=== 4. Cross-check against AACT months_to_report_results (trials with results) ==='
\echo 'If AACT measures completion to SUBMISSION, the submission-based difference should be near 0 and the posting-based one larger.'
SELECT count(*) AS n_compared,
       round(avg(abs(days_to_submission / 30.4375 - months_to_report_results))::numeric, 2) AS mean_abs_diff_months_submission,
       round(avg(abs(days_to_results    / 30.4375 - months_to_report_results))::numeric, 2) AS mean_abs_diff_months_posting,
       count(*) FILTER (WHERE abs(days_to_submission / 30.4375 - months_to_report_results) > 2) AS n_diff_gt_2_months_submission
FROM analysis.features
WHERE results_submitted_flag
  AND days_to_submission IS NOT NULL
  AND days_to_results IS NOT NULL
  AND months_to_report_results IS NOT NULL;
