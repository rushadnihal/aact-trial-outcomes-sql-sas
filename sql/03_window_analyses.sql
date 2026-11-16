-- =====================================================================
-- 03_window_analyses.sql
-- Purpose : Window-function analyses: sponsor rankings, rolling and
--           year-over-year termination rates, and time from primary
--           completion to results posting (percentiles, on-time rates).
-- Inputs  : analysis.features
-- Outputs : Result tables (printed; save the log to logs/)
-- Snapshot: AACT 2026-11-15
-- Run     : psql -U postgres -h localhost -d aact -f sql/03_window_analyses.sql > logs/03.log
-- =====================================================================

\set snapshot_date '2026-11-15'

\echo '=== 1. Sponsors with >= 50 completed or terminated trials: volume and termination rankings ==='
WITH s AS (
  SELECT sponsor_name, sponsor_class,
         count(*)                                   AS n,
         sum(terminated_flag)                       AS n_terminated,
         round(100.0 * avg(terminated_flag), 1)     AS pct_terminated
  FROM analysis.features
  WHERE terminated_flag IS NOT NULL
  GROUP BY sponsor_name, sponsor_class
  HAVING count(*) >= 50
)
SELECT sponsor_name, sponsor_class, n, n_terminated, pct_terminated,
       rank() OVER (ORDER BY n DESC)              AS rank_by_volume,
       rank() OVER (ORDER BY pct_terminated DESC) AS rank_by_termination_rate,
       ntile(4) OVER (ORDER BY pct_terminated)    AS termination_rate_quartile
FROM s
ORDER BY rank_by_volume
LIMIT 30;

\echo ''
\echo '=== 2. Termination rate by start year: 3-year rolling pooled rate and change vs previous year ==='
WITH y AS (
  SELECT start_year, count(*) AS n, sum(terminated_flag) AS n_terminated
  FROM analysis.features
  WHERE terminated_flag IS NOT NULL
  GROUP BY start_year
)
SELECT start_year, n, n_terminated,
       round(100.0 * n_terminated / n, 1) AS pct_terminated,
       round(100.0 * sum(n_terminated) OVER w / sum(n) OVER w, 1) AS pct_terminated_rolling3,
       round(100.0 * n_terminated / n
             - 100.0 * lag(n_terminated) OVER (ORDER BY start_year)
                     / lag(n) OVER (ORDER BY start_year), 1)      AS change_vs_prev_year_pts
FROM y
WINDOW w AS (ORDER BY start_year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
ORDER BY start_year;

\echo ''
\echo '=== 3. Results reporting by sponsor class (trials with >= 12 months of follow-up) ==='
\echo 'Eligible: COMPLETED or TERMINATED, primary completion date present and at least 12 months before the snapshot.'
WITH e AS (
  SELECT f.*,
         (primary_completion_date + INTERVAL '12 months')::date AS due_date
  FROM analysis.features f
  WHERE overall_status IN ('COMPLETED', 'TERMINATED')
    AND primary_completion_date IS NOT NULL
    AND primary_completion_date <= (:'snapshot_date'::date - INTERVAL '12 months')::date
)
SELECT sponsor_class,
       count(*) AS n_eligible,
       round(100.0 * count(*) FILTER (WHERE results_posted_flag) / count(*), 1) AS pct_ever_posted,
       round(100.0 * count(*) FILTER (WHERE results_first_posted_date <= due_date) / count(*), 1) AS pct_posted_within_12m,
       percentile_cont(ARRAY[0.25, 0.5, 0.75, 0.9])
         WITHIN GROUP (ORDER BY days_to_results) FILTER (WHERE results_posted_flag) AS days_to_results_q25_50_75_90
FROM e
GROUP BY sponsor_class
ORDER BY n_eligible DESC;

\echo ''
\echo '=== 4. On-time reporting by start year, trials with a US facility ==='
WITH e AS (
  SELECT f.*,
         (primary_completion_date + INTERVAL '12 months')::date AS due_date
  FROM analysis.features f
  WHERE overall_status IN ('COMPLETED', 'TERMINATED')
    AND primary_completion_date IS NOT NULL
    AND primary_completion_date <= (:'snapshot_date'::date - INTERVAL '12 months')::date
    AND has_us_facility
)
SELECT start_year,
       count(*) AS n_eligible,
       round(100.0 * count(*) FILTER (WHERE results_first_posted_date <= due_date) / count(*), 1) AS pct_posted_within_12m,
       round(100.0 * count(*) FILTER (WHERE results_posted_flag) / count(*), 1)                   AS pct_ever_posted
FROM e
GROUP BY start_year
ORDER BY start_year;

\echo ''
\echo '=== 5. On-time reporting by US facility and FDA-regulated flag (same eligibility) ==='
WITH e AS (
  SELECT f.*,
         (primary_completion_date + INTERVAL '12 months')::date AS due_date
  FROM analysis.features f
  WHERE overall_status IN ('COMPLETED', 'TERMINATED')
    AND primary_completion_date IS NOT NULL
    AND primary_completion_date <= (:'snapshot_date'::date - INTERVAL '12 months')::date
)
SELECT COALESCE(has_us_facility::text, 'missing')       AS has_us_facility,
       COALESCE(is_fda_regulated_drug::text, 'missing') AS is_fda_regulated_drug,
       count(*) AS n_eligible,
       round(100.0 * count(*) FILTER (WHERE results_first_posted_date <= due_date) / count(*), 1) AS pct_posted_within_12m
FROM e
GROUP BY 1, 2
ORDER BY 1, 2;
