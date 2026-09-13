#!/usr/bin/env sh
set -eu

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma -Atc \
  "SELECT string_agg(schema_name, ',' ORDER BY schema_name) FROM information_schema.schemata WHERE schema_name IN ('auth','academic_pi','extension','assets','institutional');" \
  | grep -qx 'academic_pi,assets,auth,extension,institutional'
