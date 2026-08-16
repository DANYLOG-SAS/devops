# Profils de projet

Un **profil** = une combinaison d'options passées aux reusable workflows. On le
choisit au moment du bootstrap :

```bash
bash bootstrap.sh <nom-projet> <profil> [repertoire-cible]
```

Tous les profils partagent la même logique centrale (`reusable-ci`,
`reusable-deploy`, `reusable-rollback`) ; seuls les `inputs` changent.

| Profil    | Contenu                    | CI                                   | Images GHCR   | Déploiement serveur |
|-----------|----------------------------|--------------------------------------|---------------|---------------------|
| `webapp`  | front + API + DB (danschool)| lint + migrations + boot/health + build front | `api` + `web` | staging → prod (VPS) |
| `service` | API seule (+ DB)           | lint + migrations + boot/health      | `api`         | staging → prod (VPS) |
| `static`  | SPA / vitrine (front seul) | build front                          | `web`         | staging → prod (VPS) |
| `library` | paquet npm/pip             | lint + build + test                  | —             | **aucun** — `npm publish` sur tag |

## Détail

### `webapp` — l'application complète (cas danschool)
Le profil de référence. Le CI valide **les migrations sur une base Postgres
jetable** (attrape la régression « migrations non embarquées »), démarre l'API
et vérifie `/health`, puis build le front. Sur tag `v*`, les images `api` et
`web` sont poussées sur GHCR et déployées staging → prod.

Généré : `ci.yml`, `release.yml`, `staging.yml`, `rollback.yml`,
`docker-compose.prod.yml`, `docker-compose.staging.yml`, `.env.example`,
`backend/Dockerfile`, `frontend/Dockerfile` (ces deux derniers seulement s'ils
sont absents).

### `service` — une API sans front
Comme `webapp` mais `build-frontend: false` et `push-web: false`.
**À ajuster** : retirer le service `web` du compose ; exposer l'API derrière
votre proxy TLS (ou publier son port). Le healthcheck peut viser directement
l'API (`HEALTH_URL` dans `.env`).

### `static` — SPA ou site vitrine
`run-backend: false`, `run-migrations: false`, `push-api: false`. Seule l'image
`web` (Caddy + build statique) est construite et déployée.
**À ajuster** : retirer `postgres`/`redis`/`api` du compose.

### `library` — paquet réutilisable, pas de serveur
Pas de compose, pas de scripts VPS, pas de déploiement. Le CI lint/build/teste ;
`publish.yml` publie le paquet sur un tag `v*` (exemple npm fourni — adapter
pour pip/PyPI). Nécessite le secret `NPM_TOKEN` (et non les secrets VPS).

## Changer de profil plus tard
Les profils ne sont qu'un point de départ : on peut à tout moment éditer les
`with:` des callers `.github/workflows/` pour activer/désactiver un job
(`run-backend`, `build-frontend`, `push-api`, `push-web`, `run-migrations`…).
