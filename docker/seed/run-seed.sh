#!/bin/sh
# Idempotent on purpose: a persistent `pgdata` volume means `docker compose up` after the first
# run hits an already-seeded database, and re-running seed.sql's plain INSERTs would fail on the
# first duplicate primary key. Skip if `properties` already has a row; `docker compose down -v`
# forces a real reseed by dropping the volume.
set -eu

export PGPASSWORD="$POSTGRES_PASSWORD"

ALREADY_SEEDED=$(psql -h db -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT 1 FROM properties LIMIT 1" 2>/dev/null || echo "")

if [ "$ALREADY_SEEDED" = "1" ]; then
  echo "Seed data already present -- skipping (docker compose down -v to force a reseed)."
  exit 0
fi

echo "Seeding database..."
psql -h db -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f /seed/seed.sql
echo "Seed complete."
