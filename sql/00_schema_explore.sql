-- =====================================================================
-- 00_schema_explore.sql
-- Purpose : Explore the restored AACT tables (schema ctgov): table list,
--           exact row counts, columns, missingness, and key distributions.
-- Inputs  : Local PostgreSQL database `aact`, schema `ctgov`
--           (selective restore of 14 study-level tables)
-- Outputs : Query results only (save the psql log to logs/)
-- Snapshot: AACT 2026-11-15  (postgres.dmp, folder 20261115_clinical_trials_ctgov)
-- Run     : psql -U postgres -h localhost -d aact -f sql/00_schema_explore.sql \
--                 -o logs/00_schema_explore.log
-- =====================================================================

\echo '=== 1. Tables restored in ctgov, with exact row counts ==='
SELECT table_name,
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT count(*) AS c FROM ctgov.%I', table_name),
                           false, true, '')))[1]::text::bigint AS row_count
FROM information_schema.tables
WHERE table_schema = 'ctgov' AND table_type = 'BASE TABLE'
ORDER BY table_name;

\echo ''
\echo '=== 2. Columns of every restored table ==='
SELECT table_name, ordinal_position, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'ctgov'
ORDER BY table_name, ordinal_position;

\echo ''
\echo '=== 3. Missingness: every column of ctgov.studies ==='
SELECT kv.key AS column_name,
       count(*) FILTER (WHERE kv.value = 'null'::jsonb) AS n_null,
       count(*)                                          AS n_rows,
       round(100.0 * count(*) FILTER (WHERE kv.value = 'null'::jsonb) / count(*), 1) AS pct_null
FROM ctgov.studies s
CROSS JOIN LATERAL jsonb_each(to_jsonb(s)) AS kv
GROUP BY kv.key
ORDER BY pct_null DESC, column_name;

\echo ''
\echo '=== 4. Key distributions on ctgov.studies ==='
\echo '--- study_type ---'
SELECT study_type, count(*) AS n FROM ctgov.studies GROUP BY 1 ORDER BY n DESC;

\echo '--- overall_status (interventional only) ---'
SELECT overall_status, count(*) AS n
FROM ctgov.studies WHERE study_type = 'INTERVENTIONAL'
GROUP BY 1 ORDER BY n DESC;

\echo '--- phase (interventional only) ---'
SELECT phase, count(*) AS n
FROM ctgov.studies WHERE study_type = 'INTERVENTIONAL'
GROUP BY 1 ORDER BY n DESC;

\echo '--- start_date range and completeness ---'
SELECT min(start_date) AS min_start, max(start_date) AS max_start,
       count(*) FILTER (WHERE start_date IS NULL) AS n_missing_start
FROM ctgov.studies;

\echo '--- results posting (interventional) ---'
SELECT count(*) FILTER (WHERE results_first_posted_date IS NOT NULL) AS n_results_posted,
       count(*) FILTER (WHERE results_first_submitted_date IS NOT NULL
                          AND results_first_posted_date IS NULL)    AS n_submitted_not_posted,
       count(*)                                                     AS n_interventional
FROM ctgov.studies WHERE study_type = 'INTERVENTIONAL';

\echo '--- why_stopped populated by status ---'
SELECT overall_status,
       count(*) AS n,
       count(*) FILTER (WHERE why_stopped IS NOT NULL) AS n_with_reason
FROM ctgov.studies
WHERE overall_status IN ('TERMINATED', 'WITHDRAWN', 'SUSPENDED')
GROUP BY 1 ORDER BY n DESC;

\echo ''
\echo '=== 5. Primary keys / duplicates sanity ==='
SELECT count(*) AS n_rows, count(DISTINCT nct_id) AS n_distinct_nct_id FROM ctgov.studies;

\echo ''
\echo '=== 6. Intervention types (drug-trial definition) ==='
SELECT intervention_type, count(*) AS n_interventions,
       count(DISTINCT nct_id) AS n_studies
FROM ctgov.interventions GROUP BY 1 ORDER BY n_studies DESC;

\echo ''
\echo '=== 7. Sponsor classes (lead sponsors) ==='
SELECT agency_class, count(DISTINCT nct_id) AS n_studies
FROM ctgov.sponsors WHERE lead_or_collaborator = 'lead'
GROUP BY 1 ORDER BY n_studies DESC;
