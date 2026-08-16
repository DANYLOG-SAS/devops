#!/usr/bin/env bash
# backup-db.sh — dump gzip de la base Postgres, rotation des N plus récents.
# À lancer depuis le répertoire de déploiement (où se trouvent .env + le compose).
#
# Env (ou lu depuis .env) :
#   ENV_FILE       fichier d'env                     (défaut .env)
#   COMPOSE_FILE   fichier compose ciblé             (défaut docker-compose.prod.yml)
#   DB_SERVICE     nom du service Postgres           (défaut postgres)
#   DB_USER        utilisateur Postgres              (requis — lu dans .env sinon)
#   DB_NAME        nom de la base                    (requis — lu dans .env sinon)
#   BACKUP_DIR     dossier des dumps                 (défaut ./backups)
#   BACKUP_KEEP    nombre de dumps conservés         (défaut 10)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-.env}"
# shellcheck source=_lib.sh
. "${SCRIPT_DIR}/_lib.sh"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_SERVICE="${DB_SERVICE:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
BACKUP_KEEP="${BACKUP_KEEP:-10}"

DB_USER="${DB_USER:-$(env_get DB_USER)}"
DB_NAME="${DB_NAME:-$(env_get DB_NAME)}"

if [ -z "${DB_USER}" ] || [ -z "${DB_NAME}" ]; then
  echo "[backup] DB_USER/DB_NAME introuvables (env ou ${ENV_FILE}) — abandon" >&2
  exit 1
fi

# Première installation : pas encore de conteneur Postgres -> rien à sauvegarder.
if [ -z "$(docker compose -f "${COMPOSE_FILE}" ps -q --status running "${DB_SERVICE}" 2>/dev/null)" ]; then
  echo "[backup] service '${DB_SERVICE}' non démarré — backup ignoré (1ère installation)"
  exit 0
fi

mkdir -p "${BACKUP_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${BACKUP_DIR}/db-${DB_NAME}-${STAMP}.sql.gz"

echo "[backup] pg_dump ${DB_NAME} -> ${OUT}"
if ! docker compose -f "${COMPOSE_FILE}" exec -T "${DB_SERVICE}" \
      pg_dump -U "${DB_USER}" "${DB_NAME}" | gzip > "${OUT}"; then
  echo "[backup] pg_dump a échoué — suppression du fichier partiel" >&2
  rm -f "${OUT}"
  exit 1
fi

# Rotation : conserver les BACKUP_KEEP dumps les plus récents.
ls -1t "${BACKUP_DIR}"/db-*.sql.gz 2>/dev/null | tail -n +"$((BACKUP_KEEP + 1))" | while read -r old; do
  echo "[backup] rotation — suppression ${old}"
  rm -f "${old}"
done

echo "[backup] OK — ${OUT} ($(du -h "${OUT}" | cut -f1))"
