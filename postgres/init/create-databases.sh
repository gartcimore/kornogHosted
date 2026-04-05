#!/bin/bash
# Creates databases for services that need Postgres.
# This script runs automatically on first container start (empty data dir).
# Add new databases here as you onboard services.

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE infisical;
EOSQL
