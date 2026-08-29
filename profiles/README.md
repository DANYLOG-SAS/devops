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
| `mobile`  | app Expo / React Native    | `expo-doctor` + bundle (`expo export`) | —           | **aucun serveur** — EAS Build sur tag `mobile-v*` |

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

### `mobile` — application Expo / React Native
Une app mobile ne se déploie pas sur un serveur : elle se compile en binaire puis
se publie sur les stores. Le profil suit donc la même philosophie que les autres
(vérifier avant de livrer, livrer sur tag délibéré) avec des outils différents.

- **À chaque modification de `mobile/`** : `expo-doctor` (cohérence des
  dépendances) puis **`expo export`** — le bundle JS est réellement produit, ce
  qui attrape imports cassés, erreurs de syntaxe et modules manquants.
  **Aucun crédit de build EAS consommé.**
- **Sur un tag `mobile-v*`** : EAS Build (Android app-bundle et/ou iOS), avec
  soumission optionnelle aux stores (`eas-submit: true`).

Le préfixe `mobile-v` rend les livraisons mobiles indépendantes des releases
serveur (`v*`) : on publie l'app sans redéployer l'API, et inversement.

> `expo-doctor` est **non bloquant par défaut** : il signale surtout des écarts
> de version de patch, utiles à connaître mais qui ne doivent pas empêcher une
> livraison. Passer `doctor-blocking: true` pour durcir.

Généré : `mobile-ci.yml`, `mobile-release.yml`. Secret requis pour builder :
`EXPO_TOKEN` (voir [secrets.md](../docs/secrets.md)).

## Un serveur en Python

Les profils décrivent la FORME d'un projet ; `backend-runtime` décrit le
LANGAGE de son serveur. Les deux se combinent : un `webapp` peut avoir un
serveur Node (danschool) ou Python (metrex-pro).

```yaml
with:
  backend-runtime: python      # défaut : node
  python-version: "3.13"       # défaut
  backend-path: .              # là où vit requirements.txt
  backend-install-command: ""  # défaut : pip install -r requirements.txt
```

Seules les étapes d'INSTALLATION changent. Tout le reste était déjà
paramétré et le demeure : `migrate-command`, `start-command`, `health-path`,
`test-commands`, `app-env`. Le frontend reste Node dans les deux cas — une
interface l'est toujours.

### Ce qui n'est PAS posé en Python

Le chemin Node écrit `NODE_ENV`, `JWT_SECRET`, `REFRESH_SECRET`,
`CORS_ORIGIN` et `APP_URL` dans l'environnement de CI : ce sont les noms de
danschool. Le chemin Python n'écrit que les COORDONNÉES de la base jetable
(`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `REDIS_URL`,
`PORT`). Tout ce qui est propre au projet passe par `app-env` :

```yaml
  app-env: |
    METREX_BASE=postgresql://ci:ci@localhost:5432/ci_test
    METREX_CLE_JETON=cle-de-controle-jamais-employee-en-production-0001
```

### Plusieurs interfaces

`frontend-paths` (une par ligne) remplace `frontend-path` quand un projet en
porte plusieurs — metrex-pro a une application de terrain et une console
d'exploitation :

```yaml
  frontend-paths: |
    web
    web-admin
```

### Le cloisonnement, et pourquoi il est verbeux

Sans `backend-runtime`, sans `frontend-paths`, **un appelant exécute
exactement les mêmes étapes qu'avant ces inputs** — vérifié en comparant les
deux versions du workflow, étape par étape. Le chemin Python et le chemin
multi-interfaces ne sont que des étapes SUPPLÉMENTAIRES gardées par un `if:`.

C'est pourquoi l'installation Node est restée `npm ci` en dur plutôt que de
devenir une expression avec repli : `${{ x || 'npm ci' }}` rend bien
« npm ci » quand `x` est vide, mais ce serait une expression de plus sur le
chemin d'un projet qui déploie de la production.

De même, le job `frontend` porte deux blocs presque semblables au lieu d'une
boucle qui tournerait une fois. C'est du texte en double, et c'est le prix
pour qu'un projet qui arrive ne puisse pas déranger un projet en ligne.

## Changer de profil plus tard
Les profils ne sont qu'un point de départ : on peut à tout moment éditer les
`with:` des callers `.github/workflows/` pour activer/désactiver un job
(`run-backend`, `build-frontend`, `push-api`, `push-web`, `run-migrations`…).
