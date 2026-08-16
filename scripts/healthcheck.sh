#!/usr/bin/env bash
# healthcheck.sh — interroge un endpoint HTTP jusqu'à ce qu'il réponde "up".
#
# Usage : healthcheck.sh <url> [retries] [delay_seconds]
# Env   : CURL_OPTS  options curl supplémentaires (ex: "-k --resolve dom:443:127.0.0.1")
#
# "up" = code HTTP 200, 400 ou 401 : le process répond (les codes d'auth 4xx
# prouvent que l'API est vivante même sans jeton). Tout autre code (000/5xx/404)
# = pas encore prêt -> on retente.
set -euo pipefail

URL="${1:?usage: healthcheck.sh <url> [retries] [delay]}"
RETRIES="${2:-30}"
DELAY="${3:-5}"

echo "[healthcheck] cible=${URL} (retries=${RETRIES}, delay=${DELAY}s, opts='${CURL_OPTS:-}')"
for i in $(seq 1 "${RETRIES}"); do
  # CURL_OPTS volontairement non quoté pour permettre plusieurs options.
  # shellcheck disable=SC2086
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 ${CURL_OPTS:-} "${URL}" 2>/dev/null || echo 000)"
  case "${code}" in
    200|400|401)
      echo "[healthcheck] OK — HTTP ${code} (tentative ${i}/${RETRIES})"
      exit 0
      ;;
    *)
      echo "[healthcheck] pas prêt — HTTP ${code} (tentative ${i}/${RETRIES})"
      sleep "${DELAY}"
      ;;
  esac
done

echo "[healthcheck] ÉCHEC — ${URL} n'est jamais devenu healthy (${RETRIES} tentatives)" >&2
exit 1
