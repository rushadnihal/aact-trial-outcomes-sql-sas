-- =====================================================================
-- 02_features.sql
-- Purpose : Build analysis.features (one row per cohort trial) with the
--           candidate predictors and both outcomes. Predictors are fixed
--           here, before looking at outcome associations.
-- Inputs  : analysis.cohort_base, ctgov.sponsors, ctgov.designs,
--           ctgov.design_groups, ctgov.countries, ctgov.calculated_values,
--           ctgov.eligibilities, ctgov.interventions, ctgov.browse_conditions
-- Outputs : Table analysis.features; summary tables (printed)
-- Snapshot: AACT 2026-11-15
-- Run     : psql -U postgres -h localhost -d aact -f sql/02_features.sql > logs/02.log
-- =====================================================================

\set snapshot_date '2026-11-15'

DROP TABLE IF EXISTS analysis.features CASCADE;  -- also drops analysis.quality_flags; rerun 04 afterwards

CREATE TABLE analysis.features AS
WITH lead_sponsor AS (
  SELECT DISTINCT ON (nct_id) nct_id, agency_class, name AS sponsor_name
  FROM ctgov.sponsors
  WHERE lead_or_collaborator = 'lead'
  ORDER BY nct_id, id
),
arms AS (
  SELECT nct_id, count(*) AS n_arms_listed
  FROM ctgov.design_groups GROUP BY nct_id
),
ctry AS (
  SELECT nct_id, count(DISTINCT name) AS n_countries
  FROM ctgov.countries WHERE NOT COALESCE(removed, FALSE) GROUP BY nct_id
),
itypes AS (
  SELECT nct_id,
         count(*)                                   AS n_interventions,
         bool_or(intervention_type = 'BIOLOGICAL')  AS has_biological,
         bool_or(intervention_type NOT IN ('DRUG', 'BIOLOGICAL')) AS has_other_type
  FROM ctgov.interventions GROUP BY nct_id
),
area AS (
  SELECT bc.nct_id,
         bool_or(bc.downcase_mesh_term = 'neoplasms')                        AS area_oncology,
         bool_or(bc.downcase_mesh_term IN ('nervous system diseases',
                                           'mental disorders'))              AS area_cns,
         bool_or(bc.downcase_mesh_term = 'cardiovascular diseases')          AS area_cardiovascular,
         bool_or(bc.downcase_mesh_term IN ('infections', 'virus diseases',
                    'bacterial infections and mycoses'))                     AS area_infectious,
         bool_or(bc.downcase_mesh_term IN ('endocrine system diseases',
                    'nutritional and metabolic diseases'))                   AS area_metabolic,
         bool_or(bc.downcase_mesh_term = 'respiratory tract diseases')       AS area_respiratory,
         bool_or(bc.downcase_mesh_term = 'immune system diseases')           AS area_immune
  FROM ctgov.browse_conditions bc
  JOIN analysis.cohort_base c USING (nct_id)
  WHERE bc.mesh_type = 'mesh-ancestor' OR bc.mesh_type = 'mesh-list'
  GROUP BY bc.nct_id
)
SELECT c.nct_id,
       -- outcomes
       c.overall_status,
       c.terminated_flag,
       c.withdrawn_flag,
       c.results_posted_flag,
       c.primary_completion_date,
       c.results_first_posted_date,
       c.days_to_results,
       c.results_first_submitted_date,
       (c.results_first_submitted_date IS NOT NULL)                          AS results_submitted_flag,
       (c.results_first_submitted_date - c.primary_completion_date)           AS days_to_submission,
       cv.months_to_report_results,
       cv.were_results_reported,
       -- design and registration predictors
       c.phase,
       c.start_date,
       EXTRACT(YEAR FROM c.start_date)::int       AS start_year,
       c.enrollment,
       c.enrollment_type,
       c.is_fda_regulated_drug,
       ls.agency_class                            AS sponsor_class,
       ls.sponsor_name,
       d.allocation,
       d.intervention_model,
       d.primary_purpose,
       d.masking,
       COALESCE(c2.n_arms_listed, 0)              AS n_arms,
       COALESCE(ct.n_countries, 0)                AS n_countries,
       cv.has_us_facility,
       cv.has_single_facility,
       cv.number_of_facilities,
       cv.number_of_primary_outcomes_to_measure   AS n_primary_outcomes,
       it.n_interventions,
       COALESCE(it.has_biological, FALSE)         AS has_biological,
       COALESCE(it.has_other_type, FALSE)         AS has_other_type,
       e.gender,
       e.healthy_volunteers,
       cv.minimum_age_num,
       cv.minimum_age_unit,
       COALESCE(a.area_oncology, FALSE)           AS area_oncology,
       COALESCE(a.area_cns, FALSE)                AS area_cns,
       COALESCE(a.area_cardiovascular, FALSE)     AS area_cardiovascular,
       COALESCE(a.area_infectious, FALSE)         AS area_infectious,
       COALESCE(a.area_metabolic, FALSE)          AS area_metabolic,
       COALESCE(a.area_respiratory, FALSE)        AS area_respiratory,
       COALESCE(a.area_immune, FALSE)             AS area_immune
FROM analysis.cohort_base c
LEFT JOIN lead_sponsor ls            ON ls.nct_id = c.nct_id
LEFT JOIN ctgov.designs d            ON d.nct_id  = c.nct_id
LEFT JOIN arms c2                    ON c2.nct_id = c.nct_id
LEFT JOIN ctry ct                    ON ct.nct_id = c.nct_id
LEFT JOIN ctgov.calculated_values cv ON cv.nct_id = c.nct_id
LEFT JOIN itypes it                  ON it.nct_id = c.nct_id
LEFT JOIN ctgov.eligibilities e      ON e.nct_id  = c.nct_id
LEFT JOIN area a                     ON a.nct_id  = c.nct_id;

CREATE UNIQUE INDEX ux_features_nct_id ON analysis.features (nct_id);
ANALYZE analysis.features;

\echo '=== Row check: features should equal cohort rows, one per trial ==='
SELECT (SELECT count(*) FROM analysis.cohort_base) AS cohort_rows,
       count(*) AS feature_rows,
       count(DISTINCT nct_id) AS distinct_trials
FROM analysis.features;

\echo ''
\echo '=== Missingness of every feature column (percent null) ==='
SELECT kv.key AS column_name,
       round(100.0 * count(*) FILTER (WHERE kv.value = 'null'::jsonb) / count(*), 1) AS pct_null
FROM analysis.features f
CROSS JOIN LATERAL jsonb_each(to_jsonb(f)) AS kv
GROUP BY kv.key ORDER BY pct_null DESC, column_name;

\echo ''
\echo '=== Termination rate by sponsor class (COMPLETED vs TERMINATED only) ==='
SELECT sponsor_class, count(*) AS n, sum(terminated_flag) AS n_terminated,
       round(100.0 * avg(terminated_flag), 1) AS pct_terminated
FROM analysis.features WHERE terminated_flag IS NOT NULL
GROUP BY 1 ORDER BY n DESC;

\echo ''
\echo '=== Termination rate by phase ==='
SELECT phase, count(*) AS n, round(100.0 * avg(terminated_flag), 1) AS pct_terminated
FROM analysis.features WHERE terminated_flag IS NOT NULL GROUP BY 1 ORDER BY 1;

\echo ''
\echo '=== Termination rate by start year ==='
SELECT start_year, count(*) AS n, round(100.0 * avg(terminated_flag), 1) AS pct_terminated
FROM analysis.features WHERE terminated_flag IS NOT NULL GROUP BY 1 ORDER BY 1;

\echo ''
\echo '=== Termination rate by therapeutic area flags ==='
SELECT 'oncology' AS area, count(*) AS n, round(100.0 * avg(terminated_flag), 1) AS pct_terminated
  FROM analysis.features WHERE terminated_flag IS NOT NULL AND area_oncology
UNION ALL SELECT 'cns', count(*), round(100.0 * avg(terminated_flag), 1)
  FROM analysis.features WHERE terminated_flag IS NOT NULL AND area_cns
UNION ALL SELECT 'cardiovascular', count(*), round(100.0 * avg(terminated_flag), 1)
  FROM analysis.features WHERE terminated_flag IS NOT NULL AND area_cardiovascular
UNION ALL SELECT 'infectious', count(*), round(100.0 * avg(terminated_flag), 1)
  FROM analysis.features WHERE terminated_flag IS NOT NULL AND area_infectious
UNION ALL SELECT 'metabolic', count(*), round(100.0 * avg(terminated_flag), 1)
  FROM analysis.features WHERE terminated_flag IS NOT NULL AND area_metabolic;

\echo ''
\echo '=== Enrollment summary by outcome ==='
SELECT overall_status, count(*) AS n,
       percentile_cont(ARRAY[0.25, 0.5, 0.75]) WITHIN GROUP (ORDER BY enrollment) AS enrollment_q1_med_q3
FROM analysis.features WHERE enrollment IS NOT NULL GROUP BY 1;
