-- =====================================================================
-- 00b_indexes.sql
-- Purpose : Index the restored AACT tables on nct_id (the join key) and
--           refresh planner statistics. A selective pg_restore may not
--           bring the original indexes back.
-- Inputs  : ctgov.* tables restored by pg_restore
-- Outputs : Indexes; ANALYZE statistics
-- Snapshot: AACT 2026-11-15
-- Run     : psql -U postgres -h localhost -d aact -f sql/00b_indexes.sql > logs/00b.log
-- =====================================================================

\echo '=== Indexes present before ==='
SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'ctgov' ORDER BY 1, 2;

CREATE UNIQUE INDEX IF NOT EXISTS ux_studies_nct_id            ON ctgov.studies (nct_id);
CREATE INDEX IF NOT EXISTS idx_interventions_nct_id            ON ctgov.interventions (nct_id);
CREATE INDEX IF NOT EXISTS idx_interventions_type              ON ctgov.interventions (intervention_type);
CREATE INDEX IF NOT EXISTS idx_sponsors_nct_id                 ON ctgov.sponsors (nct_id);
CREATE INDEX IF NOT EXISTS idx_designs_nct_id                  ON ctgov.designs (nct_id);
CREATE INDEX IF NOT EXISTS idx_conditions_nct_id               ON ctgov.conditions (nct_id);
CREATE INDEX IF NOT EXISTS idx_browse_conditions_nct_id        ON ctgov.browse_conditions (nct_id);
CREATE INDEX IF NOT EXISTS idx_browse_interventions_nct_id     ON ctgov.browse_interventions (nct_id);
CREATE INDEX IF NOT EXISTS idx_design_groups_nct_id            ON ctgov.design_groups (nct_id);
CREATE INDEX IF NOT EXISTS idx_calculated_values_nct_id        ON ctgov.calculated_values (nct_id);
CREATE INDEX IF NOT EXISTS idx_countries_nct_id                ON ctgov.countries (nct_id);
CREATE INDEX IF NOT EXISTS idx_eligibilities_nct_id            ON ctgov.eligibilities (nct_id);
CREATE INDEX IF NOT EXISTS idx_id_information_nct_id           ON ctgov.id_information (nct_id);
CREATE INDEX IF NOT EXISTS idx_responsible_parties_nct_id      ON ctgov.responsible_parties (nct_id);
CREATE INDEX IF NOT EXISTS idx_keywords_nct_id                 ON ctgov.keywords (nct_id);

ANALYZE;

\echo '=== Indexes present after ==='
SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'ctgov' ORDER BY 1, 2;
