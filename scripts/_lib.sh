#!/usr/bin/env bash
# _lib.sh — helpers partagés par deploy.sh / rollback.sh.
# À SOURCER, pas à exécuter :  . "$(dirname "$0")/_lib.sh"
#
# Fournit :
#   env_get <clef>            -> lit une valeur dans $ENV_FILE (vide si absente, ne casse jamais set -e)
#   env_set <clef> <valeur>   -> écrit/replace une valeur dans $ENV_FILE
#   compute_health            -> calcule HEALTH_TARGET (+ CURL_OPTS) à partir de DOMAIN/API_PREFIX

ENV_FILE="${ENV_FILE:-.env}"

# Lit une clef du .env. Prend la DERNIÈRE occurrence, retire d'éventuels guillemets.
# Toujours code retour 0 (le `|| true` neutralise l'échec de grep sous `set -euo pipefail`).
env_get() {
  grep -E "^${1}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2- | sed 's/^"//; s/"$//' || true
}

# Écrit KEY=VALUE dans le .env (remplace la ligne si elle existe, l'ajoute sinon).
# `|` comme séparateur sed pour tolérer les `/` dans les tags d'image.
env_set() {
  local key="$1" val="$2"
  touch "${ENV_FILE}"
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${val}" >> "${ENV_FILE}"
  fi
}

# Construit l'URL de healthcheck. Trois stratégies, par ordre de priorité :
#   1. HEALTH_URL fourni explicitement (n'importe quel profil).
#   2. DOMAIN présent (profil webapp derrière Caddy) : on interroge Caddy EN LOCAL,
#      SNI = vrai domaine, certificat ignoré (-k) -> teste web -> api sans DNS externe.
#   3. Sinon (API exposée directement) : http://localhost:PORT<API_PREFIX>/health.
compute_health() {
  local domain api_prefix health_url
  # HEALTH_URL peut venir du shell OU du .env (cas du staging, qui écoute sur un
  # port non standard) : lire les deux, sinon le réglage du .env est ignoré.
  health_url="${HEALTH_URL:-$(env_get HEALTH_URL)}"
  domain="$(env_get DOMAIN)"
  api_prefix="$(env_get API_PREFIX)"; api_prefix="${api_prefix:-/api/v1}"
  if [ -n "${health_url}" ]; then
    HEALTH_TARGET="${health_url}"
  elif [ -n "${domain}" ]; then
    HEALTH_TARGET="https://${domain}${api_prefix}/health"
    CURL_OPTS="${CURL_OPTS:- -k --resolve ${domain}:443:127.0.0.1}"
  else
    HEALTH_TARGET="http://localhost:${HEALTH_PORT:-3000}${api_prefix}/health"
  fi
  export CURL_OPTS HEALTH_TARGET
}
