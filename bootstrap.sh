#!/usr/bin/env bash
# bootstrap.sh — brancher un projet sur la chaîne CI/CD centrale en ~5 min.
#
# Usage : bash bootstrap.sh <nom-projet> <profil> [repertoire-cible]
#   profils : webapp | service | static | library
#   repertoire-cible : défaut = . (le projet courant)
#
# Génère les callers .github/workflows/ (≈10 lignes chacun), les compose GHCR,
# .env.example et, si absents, des Dockerfile de départ. Ne touche AUCUN projet
# existant sans le vouloir : par défaut, un fichier déjà présent est CONSERVÉ
# (utiliser --force pour écraser).
#
# Variables d'env :
#   DEVOPS_OWNER   propriétaire GitHub du repo devops + des images (défaut danylog-sas)
#   DEVOPS_REF     version épinglée de la chaîne (défaut v1)
#   FORCE=1        écrase les fichiers existants
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES="${SCRIPT_DIR}/templates"
OWNER="${DEVOPS_OWNER:-danylog-sas}"
REF="${DEVOPS_REF:-v1}"
FORCE="${FORCE:-0}"

die() { echo "erreur: $*" >&2; exit 1; }

[ "$#" -ge 2 ] || die "usage: bash bootstrap.sh <nom-projet> <profil> [repertoire-cible]"
NAME="$1"
PROFILE="$2"
TARGET="${3:-.}"

case "$PROFILE" in
  webapp|service|static|library) ;;
  *) die "profil inconnu '$PROFILE' (attendu: webapp | service | static | library)" ;;
esac
[ -d "$TEMPLATES" ] || die "dossier templates/ introuvable (${TEMPLATES})"

DEPLOY_PATH="/opt/${NAME}"
DEPLOY_PATH_STAGING="/opt/${NAME}-staging"
WF="${TARGET}/.github/workflows"
mkdir -p "$WF"

# write_file <chemin> — écrit stdin, en respectant --force / fichiers existants.
write_file() {
  local path="$1"
  if [ -e "$path" ] && [ "$FORCE" != "1" ]; then
    echo "  = conservé (existe déjà)  $path"
    cat > /dev/null   # consomme stdin
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  echo "  + écrit                   $path"
}

# copy_tpl <template> <dest> — copie un template en substituant nom/propriétaire.
copy_tpl() {
  local src="$1" dest="$2"
  if [ -e "$dest" ] && [ "$FORCE" != "1" ]; then
    echo "  = conservé (existe déjà)  $dest"; return 0
  fi
  mkdir -p "$(dirname "$dest")"
  sed -e "s/danschool/${NAME}/g" -e "s/danylog-sas/${OWNER}/g" "${TEMPLATES}/${src}" > "$dest"
  echo "  + écrit                   $dest"
}

app_env_block() {
  cat <<'YAML'
      app-env: |
        JWT_SECRET=ci-not-a-real-secret
        REFRESH_SECRET=ci-not-a-real-secret
YAML
}

echo "== bootstrap ${NAME} (profil ${PROFILE}) -> ${TARGET} =="
echo "   owner=${OWNER} ref=${REF} deploy=${DEPLOY_PATH}"

# ── ci.yml (toujours) ─────────────────────────────────────────────────────────
{
  cat <<YAML
# CI — checks sur Pull Request. Généré par devops/bootstrap.sh (profil ${PROFILE}).
# (sur push main, staging.yml rejoue la CI puis déploie : pas de double exécution)
name: CI
on:
  pull_request:
jobs:
  ci:
    uses: ${OWNER}/devops/.github/workflows/reusable-ci.yml@${REF}
    with:
YAML
  case "$PROFILE" in
    service) echo "      build-frontend: false" ;;
    static)  echo "      run-backend: false"; echo "      run-migrations: false" ;;
    library) echo "      run-backend: false"; echo "      run-migrations: false" ;;
  esac
  app_env_block
} | write_file "${WF}/ci.yml"

# ── library : ci + publish, PAS de déploiement serveur ────────────────────────
if [ "$PROFILE" = "library" ]; then
  cat <<YAML | write_file "${WF}/publish.yml"
# PUBLISH — publie le paquet sur un tag v* (à adapter : npm / pip).
name: Publish
on:
  push:
    tags: ['v*']
jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          registry-url: https://registry.npmjs.org
      - run: npm ci
      - run: npm run build --if-present
      - run: npm test --if-present
      - run: npm publish --provenance --access public
        env:
          NODE_AUTH_TOKEN: \${{ secrets.NPM_TOKEN }}
YAML
  echo "== terminé (library) : ci.yml + publish.yml. Aucun compose/déploiement serveur. =="
  exit 0
fi

# ── release.yml (webapp | service | static) ───────────────────────────────────
{
  cat <<YAML
# RELEASE — deploy prod sur tag v*. Généré par devops/bootstrap.sh (profil ${PROFILE}).
name: Release
on:
  push:
    tags: ['v*']
permissions:
  contents: read
  packages: write
jobs:
  build:
    uses: ${OWNER}/devops/.github/workflows/reusable-ci.yml@${REF}
    with:
      push-images: true
      image-tag: \${{ github.ref_name }}
YAML
  case "$PROFILE" in
    service) echo "      build-frontend: false"; echo "      push-web: false" ;;
    static)  echo "      run-backend: false"; echo "      run-migrations: false"; echo "      push-api: false" ;;
  esac
  app_env_block
  cat <<YAML
  deploy-staging:
    needs: build
    uses: ${OWNER}/devops/.github/workflows/reusable-deploy.yml@${REF}
    with:
      environment: staging
      image-tag: \${{ github.ref_name }}
      compose-file: docker-compose.staging.yml
      deploy-path: ${DEPLOY_PATH_STAGING}
    secrets: inherit
  deploy-production:
    needs: deploy-staging
    uses: ${OWNER}/devops/.github/workflows/reusable-deploy.yml@${REF}
    with:
      environment: production
      image-tag: \${{ github.ref_name }}
      compose-file: docker-compose.prod.yml
      deploy-path: ${DEPLOY_PATH}
    secrets: inherit
YAML
} | write_file "${WF}/release.yml"

# ── staging.yml ───────────────────────────────────────────────────────────────
{
  cat <<YAML
# STAGING — deploy staging sur push main. Généré par devops/bootstrap.sh.
name: Staging
on:
  push:
    branches: [main]
permissions:
  contents: read
  packages: write
jobs:
  build:
    uses: ${OWNER}/devops/.github/workflows/reusable-ci.yml@${REF}
    with:
      push-images: true
      image-tag: \${{ github.sha }}
YAML
  case "$PROFILE" in
    service) echo "      build-frontend: false"; echo "      push-web: false" ;;
    static)  echo "      run-backend: false"; echo "      run-migrations: false"; echo "      push-api: false" ;;
  esac
  app_env_block
  cat <<YAML
  deploy:
    needs: build
    uses: ${OWNER}/devops/.github/workflows/reusable-deploy.yml@${REF}
    with:
      environment: staging
      image-tag: \${{ github.sha }}
      compose-file: docker-compose.staging.yml
      deploy-path: ${DEPLOY_PATH_STAGING}
    secrets: inherit
YAML
} | write_file "${WF}/staging.yml"

# ── rollback.yml ──────────────────────────────────────────────────────────────
cat <<YAML | write_file "${WF}/rollback.yml"
# ROLLBACK — manuel (workflow_dispatch). Généré par devops/bootstrap.sh.
name: Rollback
on:
  workflow_dispatch:
    inputs:
      environment:
        description: Environnement
        type: choice
        options: [production, staging]
        default: production
      image-tag:
        description: Tag à redéployer (vide = tag n-1)
        type: string
        default: ""
jobs:
  rollback:
    uses: ${OWNER}/devops/.github/workflows/reusable-rollback.yml@${REF}
    with:
      environment: \${{ inputs.environment }}
      image-tag: \${{ inputs.image-tag }}
      compose-file: \${{ inputs.environment == 'production' && 'docker-compose.prod.yml' || 'docker-compose.staging.yml' }}
      deploy-path: \${{ inputs.environment == 'production' && '${DEPLOY_PATH}' || '${DEPLOY_PATH_STAGING}' }}
    secrets: inherit
YAML

# ── compose + .env.example ────────────────────────────────────────────────────
copy_tpl ".env.example" "${TARGET}/.env.example"
case "$PROFILE" in
  webapp)
    copy_tpl "docker-compose.prod.yml"    "${TARGET}/docker-compose.prod.yml"
    copy_tpl "docker-compose.staging.yml" "${TARGET}/docker-compose.staging.yml"
    ;;
  service|static)
    copy_tpl "docker-compose.prod.yml"    "${TARGET}/docker-compose.prod.yml"
    copy_tpl "docker-compose.staging.yml" "${TARGET}/docker-compose.staging.yml"
    echo "  ! profil ${PROFILE} : ajustez les compose (retirer le service inutilisé"
    echo "    web/api) — voir profiles/README.md"
    ;;
esac

# ── Dockerfiles de départ (seulement si absents) ─────────────────────────────
if [ "$PROFILE" = "webapp" ] || [ "$PROFILE" = "service" ]; then
  cat <<'DOCKER' | write_file "${TARGET}/backend/Dockerfile"
# API — image de production
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
# INDISPENSABLE en prod (DB_SYNC=false) : embarquer les migrations dans l'image.
COPY migrations ./migrations
RUN mkdir -p uploads
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "src/server.js"]
DOCKER
fi

if [ "$PROFILE" = "webapp" ] || [ "$PROFILE" = "static" ]; then
  cat <<'DOCKER' | write_file "${TARGET}/frontend/Dockerfile"
# Front — build Vite puis service statique via Caddy (HTTPS auto)
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM caddy:2-alpine
COPY --from=build /app/dist /srv
COPY Caddyfile /etc/caddy/Caddyfile
DOCKER
fi

cat <<EOF

== terminé ==
Prochaines étapes :
  1. Vérifier/ajuster : .env.example, deploy-path (${DEPLOY_PATH}), IMAGE_API/IMAGE_WEB.
  2. Créer les secrets d'ORGANISATION (voir devops/docs/secrets.md).
  3. Commit + push, puis créer un tag v0.1.0 pour un premier déploiement.
EOF
