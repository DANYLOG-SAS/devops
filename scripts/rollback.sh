#!/usr/bin/env bash
# rollback.sh — repasse à un tag d'image précédent (n-1 par défaut).
#
# Usage : rollback.sh [image-tag] [compose-file]
#   sans argument  -> repasse au tag enregistré dans .previous_tag (rollback n-1)
#   avec image-tag -> repasse à ce tag précis (déjà présent sur GHCR)
#
# L'image visée est DÉJÀ construite/testée/poussée sur GHCR : le rollback se
# limite à un pull + up -d. Instantané, aucune reconstruction.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${2:-docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-.env}"
STATE_DIR="${STATE_DIR:-.}"
CURRENT_FILE="${STATE_DIR}/.current_tag"
PREVIOUS_FILE="${STATE_DIR}/.previous_tag"
export ENV_FILE COMPOSE_FILE
# shellcheck source=_lib.sh
. "${SCRIPT_DIR}/_lib.sh"

TARGET="${1:-}"
if [ -z "${TARGET}" ] && [ -s "${PREVIOUS_FILE}" ]; then
  TARGET="$(cat "${PREVIOUS_FILE}")"
fi
if [ -z "${TARGET}" ]; then
  echo "[rollback] aucun tag fourni et pas de .previous_tag — abandon" >&2
  exit 1
fi
export IMAGE_TAG="${TARGET}"

echo "=== rollback vers ${TARGET} (compose=${COMPOSE_FILE}) ==="

# Mémoriser le tag courant pour pouvoir « annuler le rollback » ensuite.
if [ -s "${CURRENT_FILE}" ]; then
  CUR="$(cat "${CURRENT_FILE}")"
  if [ -n "${CUR}" ] && [ "${CUR}" != "${TARGET}" ]; then
    echo "${CUR}" > "${PREVIOUS_FILE}"
  fi
fi

# Backup de sécurité avant de rebasculer le schéma.
bash "${SCRIPT_DIR}/backup-db.sh"

echo "[rollback] pull ${TARGET}"
docker compose -f "${COMPOSE_FILE}" pull
echo "[rollback] up -d"
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans

compute_health
if bash "${SCRIPT_DIR}/healthcheck.sh" "${HEALTH_TARGET}" "${HEALTH_RETRIES:-30}" "${HEALTH_DELAY:-5}"; then
  echo "${TARGET}" > "${CURRENT_FILE}"
  echo "=== rollback OK — ${TARGET} en ligne ==="
  exit 0
fi

echo "[rollback] ÉCHEC — ${TARGET} n'est pas healthy, intervention manuelle requise" >&2
exit 1
