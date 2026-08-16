# Pipeline CI/CD

## Vue d'ensemble

Toute la logique vit dans ce repo (`devops`). Chaque projet n'a que des
**callers** de ~10 lignes qui appellent les *reusable workflows* via
`uses: <owner>/devops/.github/workflows/reusable-*.yml@v1`.

```
projet (danschool)                     devops (ce repo)
──────────────────                     ────────────────
.github/workflows/ci.yml       ─────►  reusable-ci.yml
.github/workflows/staging.yml  ─────►  reusable-ci.yml + reusable-deploy.yml
.github/workflows/release.yml  ─────►  reusable-ci.yml + reusable-deploy.yml (staging → prod)
.github/workflows/rollback.yml ─────►  reusable-rollback.yml
docker-compose.prod.yml                scripts/ (deploy, rollback, backup, health)
docker-compose.staging.yml
.env  (via secret ENV_PROD/ENV_STAGING)
```

## Déclencheurs

| Événement                | Workflow projet | Effet                                                        |
|--------------------------|-----------------|-------------------------------------------------------------|
| Pull request / push main | `ci.yml`        | checks (aucune image poussée)                               |
| Push sur `main`          | `staging.yml`   | build+push image `sha` → **déploie staging**                |
| Tag `v*` (ex. `v1.2.3`)  | `release.yml`   | build+push image `v1.2.3` → **staging → prod**              |
| Manuel (Actions)         | `rollback.yml`  | redéploie un tag choisi (ou n-1)                            |

Le **déploiement de production est délibéré** : il n'a lieu que sur un tag de
version. Traçable (le tag = la version en ligne), réversible (redéployer le tag
précédent).

## `reusable-ci.yml` — ce que le CI garantit

1. **lint**
2. **migrations depuis zéro** sur une base **Postgres jetable** (service
   container). *C'est le garde-fou clé* : il attrape les migrations cassées ou
   non embarquées — exactement la régression qui a cassé la prod danschool.
3. **boot + `/health`** : l'API démarre réellement et répond.
4. **build frontend**.
5. si `push-images: true` :
   - build de l'**image API réelle**, puis **re-exécution des migrations dans le
     conteneur** contre un Postgres jetable → attrape spécifiquement « le dossier
     `migrations/` n'est pas dans l'image » ;
   - build de l'image WEB ;
   - push sur **GHCR** tagué `version` + `sha` + `latest`.

Le boot en CI utilise des **secrets factices** (`app-env`) — jamais de vrais
secrets.

### Principaux `inputs` (défauts = danschool)
`node-version=20`, `backend-path=backend`, `frontend-path=frontend`,
`run-backend=true`, `run-lint=true`, `run-migrations=true`,
`migrate-command="npm run migrate"`, `start-command="npm start"`,
`health-path="/api/v1/health"`, `health-port=3000`, `build-frontend=true`,
`push-images=false`, `push-api=true`, `push-web=true`, `image-tag`, `registry=ghcr.io`.

## `reusable-deploy.yml` — déploiement

1. checkout du projet (pour le compose) + checkout de `devops@<ref>` (pour les
   `scripts/`) ;
2. écriture du `.env` depuis le secret `ENV_PROD`/`ENV_STAGING` (choisi selon
   `environment`) ;
3. **scp** du payload (scripts + compose + `.env`) vers le `deploy-path` du VPS ;
4. **ssh** : `docker login ghcr.io` puis `bash deploy.sh <image-tag> <compose>`.

La logique restant centrale, corriger un script ici corrige tous les projets au
prochain déploiement.

## `deploy.sh` (côté VPS)
Mémorise n-1 → **backup DB** → `pull` → `up -d` (migrations Umzug au boot) →
**healthcheck** → **rollback automatique** si le health échoue. Voir
[deployment.md](deployment.md) et [rollback.md](rollback.md).

## Pourquoi le VPS ne build plus
Avant : `git pull` + `docker compose up -d --build` **sur le serveur** (build en
prod, lent, non reproductible, sensible à l'OOM). Maintenant : l'image est
construite **et testée** en CI, poussée sur GHCR, et le VPS ne fait que `pull`
l'image **exacte** validée. Le rollback est instantané (l'image n-1 est déjà là).
