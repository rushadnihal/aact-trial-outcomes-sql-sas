#!/usr/bin/env bash
# Runs the numbered SQL scripts in order against the local `aact` database.
# Usage (from anywhere):  bash run_all.sh
# Asks for the Postgres password once (typing is hidden). Stops at the first error.
set -euo pipefail
cd "$(dirname "$0")"

DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-aact}"

if [ -z "${PGPASSWORD:-}" ]; then
  read -r -s -p "Postgres password for ${DB_USER}: " PGPASSWORD
  echo
  export PGPASSWORD
fi

mkdir -p logs output
for f in 00b_indexes 01_cohort 02_features 03_window_analyses 04_quality_checks 05_analysis_dataset; do
  num="${f%%_*}"
  echo "Running sql/${f}.sql ..."
  if ! psql -v ON_ERROR_STOP=1 -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" -f "sql/${f}.sql" > "logs/${num}.log" 2>&1; then
    echo "FAILED in sql/${f}.sql. Last lines of logs/${num}.log:"
    tail -15 "logs/${num}.log"
    exit 1
  fi
done
echo "Done. Logs are in logs/, exports in output/."
