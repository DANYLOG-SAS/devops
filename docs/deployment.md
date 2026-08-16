# Déploiement — mise en place du VPS & premier déploiement

> Objectif : le VPS ne fait plus que **`pull`** des images GHCR déjà testées.
> Plus aucun build en production.

## 1. Prérequis VPS (une fois)

- VPS Ubuntu (≈2 vCPU / 4 Go), Docker + plugin `compose` installés :
  ```bash
  curl -fsSL https://get.docker.com | sh
  ```
- Pare-feu : autoriser `OpenSSH`, `80`, `443` (et `8080/8443` si staging sur le
  même hôte).
- **Utilisateur de déploiement** dédié, membre du groupe `docker` :
  ```bash
  sudo adduser --disabled-password deploy
  sudo usermod -aG docker deploy
  sudo -u deploy mkdir -p /home/deploy/.ssh
  # coller la clé PUBLIQUE de déploiement :
  sudo -u deploy tee -a /home/deploy/.ssh/authorized_keys < deploy_key.pub
  ```
  (génération de la paire : voir [secrets.md](secrets.md).)
- **Répertoires de déploiement** (correspondant aux `deploy-path` des callers) :
  ```bash
  sudo install -d -o deploy -g deploy /opt/danschool /opt/danschool-staging
  ```

## 2. DNS

Deux enregistrements A vers l'IP du VPS :
- `app` (console) — ex. `app.danschool.app`
- `*` (sous-domaines par école) — wildcard

Pour le staging sur le même hôte : `staging.danschool.app` → même IP (voir §5).

## 3. Secrets d'organisation

Créer les secrets listés dans [secrets.md](secrets.md) : `SSH_HOST`, `SSH_USER`,
`SSH_KEY`, `SSH_PORT`, `GHCR_TOKEN`, `ENV_PROD`, `ENV_STAGING`.

## 4. Premier déploiement

Rien à préparer manuellement dans le `deploy-path` : le pipeline y dépose les
`scripts/`, le compose et le `.env`. Il suffit de :

1. brancher le projet (voir [README](../README.md)) — callers + compose GHCR ;
2. `git push` sur `main` → **staging** se déploie tout seul ;
3. quand c'est bon : `git tag v0.1.0 && git push origin v0.1.0` → **staging →
   prod**.

`deploy.sh` s'occupe de : login GHCR, backup DB (ignoré à la 1ʳᵉ install),
`pull`, `up -d` (les migrations Umzug s'appliquent au boot de l'API),
healthcheck, et rollback automatique si le health échoue.

### Seed initial (le cas échéant)
Après le premier `up`, exécuter le seed applicatif sur le serveur :
```bash
cd /opt/danschool
docker compose -f docker-compose.prod.yml exec api npm run seed
```

## 5. Staging sur le même VPS

Le staging tourne dans un **projet compose isolé** (`COMPOSE_PROJECT_NAME` +
répertoire distinct) → conteneurs, réseau et **volumes séparés**, donc **base de
données séparée** de la prod.

La prod occupe déjà `80/443`. Le staging (`docker-compose.staging.yml`) :
- publie le web sur **`8080/8443`** ;
- expose l'API en local sur **`127.0.0.1:3001`** pour un healthcheck fiable
  (`HEALTH_URL=http://localhost:3001/api/v1/health` dans `ENV_STAGING`).

⚠️ Sur `8443`, l'ACME on-demand de Caddy n'obtient pas de certificat public
(ports non standard). Pour un staging **HTTPS propre**, deux options :
- un **hôte dédié** pour le staging (le plus simple, recommandé si le budget le
  permet) ;
- un **proxy frontal partagé** (Caddy/Traefik unique) routant `app.…` vers la
  prod et `staging.…` vers le staging.

Le pipeline reste identique quelle que soit l'option (seuls `deploy-path` et le
compose changent).

## 6. Bascule d'un projet existant vers GHCR (ex. danschool)

Aujourd'hui danschool build sur le serveur. Pour basculer, **sans risque pour la
prod** :
1. déposer les callers + les `docker-compose.*.yml` basés images GHCR + adapter
   `.env` (ajouter `REGISTRY`/`IMAGE_API`/`IMAGE_WEB`) ;
2. vérifier que le backend `Dockerfile` **copie bien `migrations/`** (le CI le
   re-teste de toute façon) ;
3. valider d'abord en **staging**, puis tagguer une release pour la prod.

## Opérations courantes

```bash
cd /opt/danschool
docker compose -f docker-compose.prod.yml ps                 # état
docker compose -f docker-compose.prod.yml logs -f api        # logs API
bash scripts/backup-db.sh                                     # backup manuel
cat .current_tag .previous_tag                                # tags en ligne / n-1
```
