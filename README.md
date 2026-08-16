# devops — chaîne CI/CD centrale & réutilisable

Repo **unique** qui héberge toute la logique CI/CD (build, tests, déploiement
sécurisé, rollback). Chaque projet ne garde qu'une **config minimale** : un
`Dockerfile`, des callers de ~10 lignes, un `docker-compose` basé images GHCR et
un `.env`.

## Objectifs

- **Ne plus jamais casser la prod** : le CI valide *les migrations depuis zéro
  sur une base jetable* et le *boot réel de l'API* avant qu'une image n'atteigne
  un serveur (la régression qui a cassé danschool est attrapée en CI).
- **Déploiements délibérés & tracés** : la prod ne se déploie que sur un **tag de
  version** `vX.Y.Z`.
- **Rollback n-1 instantané** : l'image précédente est déjà sur GHCR ; y revenir
  = un `pull`.
- **Sécurité DB** : backup `pg_dump` **avant** migration, healthcheck après, et
  **rollback automatique** si le health échoue.
- **Staging avant prod**, puis promotion.
- **Réutilisable** : reusable workflows + composite actions ; secrets réglés
  **une fois** en secrets d'organisation.

## Le principe en une image

```
projet (ex. danschool)                 devops (ce repo)
──────────────────────                 ────────────────
.github/workflows/*.yml  ──uses:──►    .github/workflows/reusable-*.yml
docker-compose.*.yml                   scripts/  (deploy · rollback · backup · health)
.env  ◄── secret ENV_PROD/ENV_STAGING  actions/  · templates/ · profiles/ · docs/
```

Le VPS ne **build** plus rien : il `pull` une image GHCR déjà construite **et
testée**, taguée par version.

## Structure du repo

```
.github/workflows/
  reusable-ci.yml        lint + migrations-sur-DB-jetable + boot/health + build + push GHCR
  reusable-deploy.yml    SSH → dépose scripts/compose/.env → deploy.sh
  reusable-rollback.yml  SSH → rollback.sh <tag>
actions/setup-app/       composite : setup Node + cache + npm ci
scripts/                 exécutés sur le VPS (deploy, rollback, backup-db, healthcheck, _lib)
templates/               ce qu'un projet copie (callers, compose GHCR, .env.example)
profiles/                webapp · service · static · library
docs/                    branching · cicd-pipeline · deployment · rollback · secrets
bootstrap.sh             onboarder un projet : bash bootstrap.sh <nom> <profil>
```

## Brancher un nouveau projet (≈5 min)

```bash
# depuis le repo devops, en ciblant le dossier du projet
bash bootstrap.sh mon-projet webapp /chemin/vers/mon-projet
```

Génère les callers `.github/workflows/`, les `docker-compose.*.yml` (images
GHCR), `.env.example` et, si absents, des `Dockerfile` de départ. Ensuite :

1. ajuster `.env.example` (`REGISTRY`, `IMAGE_API/IMAGE_WEB`, `DOMAIN`, DB…) ;
2. créer les [secrets d'organisation](docs/secrets.md) (une fois pour tous les
   projets) ;
3. préparer le VPS ([deployment.md](docs/deployment.md)) ;
4. `git push` → **staging** ; `git tag v0.1.0 && git push --tags` → **prod**.

Profils disponibles : voir [profiles/README.md](profiles/README.md).

## Brancher danschool (premier client)

Les `templates/` sont déjà calés sur l'infra danschool (Caddy, `postgres:15`,
`redis:7`, API `/api/v1/health`). Sans toucher à la prod actuelle :

1. déposer les callers + `docker-compose.prod.yml`/`.staging.yml` (images GHCR)
   dans le repo danschool ;
2. compléter `.env` avec `REGISTRY=ghcr.io`, `IMAGE_API=danylog243/danschool-api`,
   `IMAGE_WEB=danylog243/danschool-web` ;
3. vérifier que `backend/Dockerfile` copie `migrations/` (le CI le re-teste) ;
4. valider en **staging**, puis tag `v*` pour la **prod**.

## Versionner la chaîne

Ce repo est tagué (`v1`, `v2`, …) ; les projets épinglent une version stable via
`uses: <owner>/devops/.github/workflows/reusable-*.yml@v1`.

- Correctif/ajout rétrocompatible → on **avance le tag flottant `v1`** sur le
  nouveau commit :
  ```bash
  git tag -f v1 && git push -f origin v1
  ```
- Changement **cassant** → nouveau tag majeur `v2` ; les projets migrent quand
  ils veulent (ils restent sur `@v1` en attendant).

> `bootstrap.sh` accepte `DEVOPS_OWNER` et `DEVOPS_REF` (défaut `danylog243`/`v1`)
> pour cibler un autre propriétaire ou une autre version.

## Documentation

| Doc | Contenu |
|-----|---------|
| [docs/cicd-pipeline.md](docs/cicd-pipeline.md)     | fonctionnement du pipeline, inputs |
| [docs/branching-strategy.md](docs/branching-strategy.md) | branches, releases, hotfix, rollback |
| [docs/deployment.md](docs/deployment.md)           | mise en place VPS, premier déploiement, staging |
| [docs/rollback.md](docs/rollback.md)               | rollback auto & manuel, restauration DB |
| [docs/secrets.md](docs/secrets.md)                 | liste exacte des secrets d'org à créer |
