# Rollback

Le rollback est **instantané** : l'image précédente est déjà construite, testée
et présente sur GHCR. Revenir en arrière = un simple `pull` + `up -d` du tag
précédent. Aucune reconstruction, aucune surprise.

## Deux mécanismes

### 1. Rollback **automatique** (pendant un déploiement)
Si le **healthcheck** échoue après un déploiement, `deploy.sh` :
1. relit le tag n-1 (`.previous_tag`),
2. réécrit le tag, `pull` + `up -d`,
3. re-vérifie le health.

Autrement dit : **un déploiement qui casse le health se répare tout seul** et
laisse la prod sur la dernière version saine. Le job GitHub sort en échec (pour
alerter), mais le service reste en ligne.

### 2. Rollback **manuel** (workflow_dispatch)
Depuis l'onglet **Actions → Rollback → Run workflow** du projet :
- **environment** : `production` ou `staging` ;
- **image-tag** : vide = revient au **tag n-1**, ou un tag précis (ex. `v1.2.2`).

Le workflow relaie vers `reusable-rollback.yml`, qui exécute `rollback.sh` sur le
VPS.

## Sur le serveur (secours)

En SSH direct, si besoin :

```bash
cd /opt/danschool
# revenir au tag n-1
bash scripts/rollback.sh
# ou cibler un tag précis déjà sur GHCR
bash scripts/rollback.sh v1.2.2 docker-compose.prod.yml
```

## État suivi sur le VPS

| Fichier         | Contenu                                    |
|-----------------|--------------------------------------------|
| `.current_tag`  | tag actuellement en ligne                  |
| `.previous_tag` | tag n-1 (cible du rollback par défaut)     |

`rollback.sh` mémorise aussi le tag courant avant de basculer : on peut donc
**annuler un rollback** en le relançant sans argument (il repasse à ce qui
tournait juste avant).

## Base de données — précautions

- Un **backup `pg_dump`** est pris **avant** chaque déploiement **et** chaque
  rollback (rotation des 10 derniers, dans `backups/`).
- Le rollback rebascule le **code/schéma applicatif** vers une image antérieure.
  Si la version fautive a appliqué une **migration destructrice** (drop de
  colonne/table), redescendre l'image ne restaure pas les données perdues :
  restaurer alors depuis le dump. D'où la règle des migrations **idempotentes et
  non destructives** autant que possible (cf. `reconcile.js` côté danschool).

### Restaurer un dump manuellement
```bash
cd /opt/danschool
gunzip -c backups/db-danschool-AAAAMMJJ-HHMMSS.sql.gz \
  | docker compose -f docker-compose.prod.yml exec -T postgres psql -U danschool danschool
```

## Choisir une version à redéployer
```bash
git tag --sort=-creatordate | head        # dernières releases
# puis Actions → Rollback → image-tag = vX.Y.Z
```
