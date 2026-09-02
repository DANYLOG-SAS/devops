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
  reusable-mobile.yml    Expo/React Native : expo-doctor + bundle + EAS Build
actions/setup-app/       composite : setup Node + cache + npm ci
scripts/                 exécutés sur le VPS (deploy, rollback, backup-db, healthcheck, _lib)
templates/               ce qu'un projet copie (callers, compose GHCR, .env.example)
profiles/                webapp · service · static · library · mobile
docs/                    branching · cicd-pipeline · deployment · rollback · secrets · mobile
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
2. compléter `.env` avec `REGISTRY=ghcr.io`, `IMAGE_API=danylog-sas/danschool-api`,
   `IMAGE_WEB=danylog-sas/danschool-web` ;
3. vérifier que `backend/Dockerfile` copie `migrations/` (le CI le re-teste) ;
4. valider en **staging**, puis tag `v*` pour la **prod**.

## Versionner la chaîne

Deux sortes de tags, et une règle qui ne se contourne pas.

**`vX.Y.Z` — immuable.** Posé sur un commit, il n'est jamais déplacé ni supprimé.
C'est le point fixe : sans lui, il n'existe aucune version vers laquelle revenir.

**`v1` — flottant.** Ce que les projets épinglent au quotidien. Il ne pointe
**jamais directement sur un commit** : il ne fait que suivre un `vX.Y.Z` déjà
posé.

```bash
# 1. la version immuable, d'abord
git tag -a v1.2.0 -m "ce que la version apporte" && git push origin v1.2.0
# 2. puis le tag flottant, qui la suit
git tag -f v1 v1.2.0 && git push -f origin v1
```

Pourquoi cet ordre, et pas l'inverse : un tag flottant avancé sur un commit non
tagué ne laisse **rien derrière lui**. Le jour où la nouvelle version pose
problème, il n'y a aucune référence stable vers laquelle reculer.

Et surtout : **on ne recule jamais `v1`.** Un dépôt qui a déjà tiré la nouvelle
version repartirait en arrière au milieu d'un run, sans que rien ne le signale —
c'est pire que d'avoir avancé trop tôt. En cas de problème on **avance** vers un
`v1.x.y` correctif ; les projets qui veulent se figer épinglent un `vX.Y.Z` ou un
SHA.

**Changement cassant** → nouveau tag majeur `v2` ; les projets migrent quand ils
veulent (ils restent sur `@v1` en attendant).

### Avant d'avancer `v1`

`v1` sert plusieurs dépôts à la fois. Avancer ce tag est une **mise en
production pour tous ceux qui l'épinglent**, y compris pour les commits déjà sur
`main` mais jamais publiés. Donc, dans l'ordre :

1. recenser qui consomme la chaîne — la branche par défaut de chaque dépôt de
   l'organisation, pas seulement celui qu'on a en tête ;
2. vérifier que le diff depuis le `v1` courant n'enlève ni ne modifie de ligne
   sur les chemins déjà servis (`git diff v1 HEAD -- .github/workflows/`) ;
3. **exécuter**, pas seulement relire : déclencher la CI d'un dépôt consommateur
   et obtenir un vert. Lire une garde `if:` et constater qu'elle est fausse pour
   un projet donné est un raisonnement ; ce n'est pas une preuve.

> `bootstrap.sh` accepte `DEVOPS_OWNER` et `DEVOPS_REF` (défaut `danylog-sas`/`v1`)
> pour cibler un autre propriétaire ou une autre version.

## Documentation

| Doc | Contenu |
|-----|---------|
| [docs/cicd-pipeline.md](docs/cicd-pipeline.md)     | fonctionnement du pipeline, inputs |
| [docs/branching-strategy.md](docs/branching-strategy.md) | branches, releases, hotfix, rollback |
| [docs/deployment.md](docs/deployment.md)           | mise en place VPS, premier déploiement, staging |
| [docs/rollback.md](docs/rollback.md)               | rollback auto & manuel, restauration DB |
| [docs/secrets.md](docs/secrets.md)                 | liste exacte des secrets à créer |
| [docs/mobile.md](docs/mobile.md)                   | livraison Expo/EAS : build, signature, publication stores |
