-- =====================================================================
-- 06_explain_analyze.sql
-- Purpose : Show what the indexes from 00b_indexes.sql buy. Runs the same
--           cohort query with EXPLAIN (ANALYZE, BUFFERS) twice: first with the
--           two indexes on ctgov.interventions dropped, then with them in place.
-- Inputs  : ctgov.studies, ctgov.interventions, analysis.study_base
-- Outputs : Query plans and timings (printed; save the log to logs/06.log)
-- Snapshot: AACT 2026-11-15
-- Run     : psql -U postgres -h localhost -d aact -f sql/06_explain_analyze.sql > logs/06.log
-- Notes   : Optional; not part of run_all.sh. The DROP INDEX statements run inside
--           a transaction that is rolled back, so the indexes are not lost.
--           DROP INDEX takes an exclusive lock on ctgov.interventions, so run it
--           on a local copy, not on a shared database. Timings depend on the
--           machine and on caching: run the script twice and report the second run.
-- =====================================================================

\echo '=== A. Without the indexes on ctgov.interventions ==='
BEGIN;
DROP INDEX ctgov.idx_interventions_nct_id;
DROP INDEX ctgov.idx_interventions_type;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM analysis.study_base
WHERE study_type = 'INTERVENTIONAL'
  AND phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
  AND has_drug_or_bio;
ROLLBACK;

\echo ''
\echo '=== B. With the indexes (as created by 00b_indexes.sql) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM analysis.study_base
WHERE study_type = 'INTERVENTIONAL'
  AND phase IN ('PHASE2', 'PHASE2/PHASE3', 'PHASE3')
  AND has_drug_or_bio;
