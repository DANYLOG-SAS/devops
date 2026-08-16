#!/usr/bin/env bash
# deploy.sh — déploiement sûr d'un tag d'image, avec rollback automatique.
#
# Usage : deploy.sh <image-tag> [compose-file]
# À lancer depuis le répertoire de déploiement (où se trouvent .env + le compose + scripts/).
#
# Séparation nette :
#   - .env            = CONFIG applicative (géré par le secret ENV_PROD/ENV_STAGING,
#                       réécrit à chaque déploiement) — ne contient PAS l'état.
#   - .current_tag    = ÉTAT : tag actuellement en ligne (persiste sur le VPS).
#   - .previous_tag   = ÉTAT : tag n-1 (cible du rollback instantané).
#   IMAGE_TAG est EXPORTÉ dans l'environnement -> docker compose l'interpole
#   (aucun besoin de l'écrire dans .env, donc la réécriture de .env est sans risque).
#
# Déroulé : mémorise n-1 -> backup DB -> pull -> up -d (migrations au boot) ->
#           healthcheck -> rollback automatique si KO.
set -euo pipefail

IMAGE_TAG="${1:?usage: deploy.sh <image-tag> [compose-file]}"
COMPOSE_FILE="${2:-docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-.env}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${STATE_DIR:-.}"
CURRENT_FILE="${STATE_DIR}/.current_tag"
PREVIOUS_FILE="${STATE_DIR}/.previous_tag"
export ENV_FILE COMPOSE_FILE IMAGE_TAG
# shellcheck source=_lib.sh
. "${SCRIPT_DIR}/_lib.sh"

echo "=== deploy: tag=${IMAGE_TAG} compose=${COMPOSE_FILE} ==="

# --- 1. mémoriser le tag courant comme PREVIOUS (rollback n-1) -----------------
if [ -s "${CURRENT_FILE}" ]; then
  PREV="$(cat "${CURRENT_FILE}")"
  if [ -n "${PREV}" ] && [ "${PREV}" != "${IMAGE_TAG}" ]; then
    echo "${PREV}" > "${PREVIOUS_FILE}"
    echo "[deploy] tag précédent mémorisé (rollback n-1) : ${PREV}"
  fi
fi

# --- 2. backup DB AVANT toute migration ---------------------------------------
bash "${SCRIPT_DIR}/backup-db.sh"

# --- 3. pull + up (IMAGE_TAG exporté -> interpolé par compose) -----------------
echo "[deploy] pull ${IMAGE_TAG}"
docker compose -f "${COMPOSE_FILE}" pull
echo "[deploy] up -d"
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans

# --- 4. healthcheck -----------------------------------------------------------
compute_health
if bash "${SCRIPT_DIR}/healthcheck.sh" "${HEALTH_TARGET}" "${HEALTH_RETRIES:-30}" "${HEALTH_DELAY:-5}"; then
  echo "${IMAGE_TAG}" > "${CURRENT_FILE}"
  echo "=== deploy OK — ${IMAGE_TAG} en ligne ==="
  exit 0
fi

# --- 5. rollback automatique --------------------------------------------------
echo "[deploy] HEALTHCHECK KO — rollback automatique" >&2
if [ -s "${PREVIOUS_FILE}" ]; then
  PREV="$(cat "${PREVIOUS_FILE}")"
  echo "[deploy] retour au tag précédent : ${PREV}" >&2
  export IMAGE_TAG="${PREV}"
  docker compose -f "${COMPOSE_FILE}" pull
  docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans
  if bash "${SCRIPT_DIR}/healthcheck.sh" "${HEALTH_TARGET}" "${HEALTH_RETRIES:-30}" "${HEALTH_DELAY:-5}"; then
    echo "${PREV}" > "${CURRENT_FILE}"
    echo "[deploy] rollback vers ${PREV} réussi — le déploiement de ${1} a ÉCHOUÉ" >&2
  else
    echo "[deploy] ALERTE : même le rollback vers ${PREV} n'est pas healthy — intervention manuelle requise" >&2
  fi
else
  echo "[deploy] aucun tag précédent connu — rollback impossible (1ère installation ?)" >&2
fi
exit 1
