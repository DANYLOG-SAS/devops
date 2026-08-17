# Secrets

> Ces secrets sont créés **par toi**, une seule fois, en **secrets
> d'organisation** GitHub (Organization → Settings → Secrets and variables →
> Actions). Le pipeline ne les manipule jamais en clair ; ce document ne fait
> que les lister.

## Où les créer

⚠️ **Plan GitHub Free : les secrets d'ORGANISATION ne sont pas utilisables par
les repos PRIVÉS.** Le picker « Selected repositories » n'affichera pas tes repos
privés, et l'option « Private repositories » est grisée. Deux cas :

| Situation | Où créer les secrets |
|---|---|
| Org **Free** + repos privés (cas actuel) | **Secrets de repo** : `https://github.com/<org>/<projet>/settings/secrets/actions` → *New repository secret*. À refaire pour chaque projet (~2 min). |
| Org **Team/Enterprise** | **Secrets d'organisation**, créés **une fois** et partagés. |

Dans les deux cas, **rien à changer dans les workflows** : `secrets: inherit`
transmet indifféremment les secrets de repo et ceux d'organisation.

## Liste EXACTE à créer

| Secret         | Rôle                                                        | Exemple / format                              |
|----------------|-------------------------------------------------------------|-----------------------------------------------|
| `SSH_HOST`     | IP ou hôte du VPS                                            | `203.0.113.10`                                |
| `SSH_USER`     | utilisateur SSH de déploiement                              | `deploy`                                       |
| `SSH_KEY`      | **clé privée** de déploiement (OpenSSH, multi-lignes)       | `-----BEGIN OPENSSH PRIVATE KEY----- …`       |
| `SSH_PORT`     | port SSH (optionnel, défaut 22)                            | `22`                                           |
| `GHCR_TOKEN`   | PAT GitHub `read:packages` — le VPS l'utilise pour `pull`   | `ghp_…`                                        |
| `ENV_PROD`     | contenu **complet** du `.env` de production                 | tout le fichier (voir `templates/.env.example`)|
| `ENV_STAGING`  | contenu **complet** du `.env` de staging                    | idem, valeurs staging                          |

Pour un profil `library` : pas de secrets VPS, mais un `NPM_TOKEN`
(`Automation` token npm) pour `npm publish`.

Pour un profil `mobile` : pas de secrets VPS non plus, mais un **`EXPO_TOKEN`**
— uniquement nécessaire pour lancer des builds EAS (les vérifications
`expo-doctor` / `expo export` n'en demandent aucun).

| Secret | Rôle | Où l'obtenir |
|---|---|---|
| `EXPO_TOKEN` | authentifier EAS Build / EAS Submit | [expo.dev](https://expo.dev) → *Account settings* → **Access tokens** → *Create token* |

La publication sur les stores (`eas-submit: true`) exige en plus des
identifiants côté Expo : compte Apple Developer et/ou clé de service Google
Play, configurés **dans EAS** (`eas credentials`), jamais dans GitHub.

## Détails

### Clé de déploiement (`SSH_KEY` / `SSH_HOST` / `SSH_USER` / `SSH_PORT`)
Génère une paire dédiée (ne réutilise pas ta clé perso) :

```bash
ssh-keygen -t ed25519 -C "deploy@danschool" -f deploy_key -N ""
```

- La **clé publique** (`deploy_key.pub`) va dans `~/.ssh/authorized_keys` de
  l'utilisateur `SSH_USER` sur le VPS.
- La **clé privée** (`deploy_key`) devient le secret `SSH_KEY` (colle tout le
  fichier, en-têtes `BEGIN/END` compris).

### `GHCR_TOKEN` (pull sur le VPS)
Le **push** des images en CI utilise le `GITHUB_TOKEN` automatique (aucune
action requise). Le **pull** sur le VPS a besoin d'un jeton avec **`read:packages`** :

- GitHub → Settings → Developer settings → **Personal access tokens (classic)**
  → cocher **`read:packages`** uniquement.
- Comme le registre GHCR est **privé**, ce jeton est indispensable côté serveur.

### `ENV_PROD` / `ENV_STAGING`
Le pipeline écrit ce contenu dans le fichier `.env` déposé sur le VPS à chaque
déploiement (voir `reusable-deploy.yml`). Il **pilote à la fois l'API et
Postgres** (un seul `.env`). Base-toi sur `templates/.env.example` et remplace
tous les `CHANGER_…` :

```bash
openssl rand -hex 32   # pour JWT_SECRET et REFRESH_SECRET
```

Spécificités par environnement :
- **`ENV_STAGING`** doit contenir `COMPOSE_PROJECT_NAME=<projet>-staging`,
  `HEALTH_URL=http://localhost:3001/api/v1/health`, un `DB_PASSWORD` distinct,
  et un `DOMAIN=staging.<domaine>`.
- **`ENV_PROD`** laisse `HEALTH_URL` vide (health via Caddy) et utilise le
  `DOMAIN` de production.

> `IMAGE_TAG` dans le `.env` n'est qu'un placeholder : `deploy.sh` exporte le vrai
> tag à la volée. Inutile de le maintenir dans le secret.

## Ce qui n'est PAS un secret
`REGISTRY`, `IMAGE_API`, `IMAGE_WEB`, `DOMAIN`, ports… vivent dans le `.env`
(donc dans `ENV_PROD`/`ENV_STAGING`) — pas de secret séparé. Le `GITHUB_TOKEN`
du push d'images est fourni automatiquement par GitHub Actions.
