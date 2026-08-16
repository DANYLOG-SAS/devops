# Stratégie de branches & de versions

## Principes

- **`main` est protégé** et toujours déployable. On n'y pousse jamais en direct.
- Le travail se fait sur des **branches de feature** → **Pull Request** → merge.
- Chaque push sur `main` **déploie automatiquement en staging** (validation
  continue).
- La **production ne se déploie que sur un tag de version** `vX.Y.Z` : un acte
  délibéré, tracé, réversible.

## Flux nominal

```
feature/x ──PR──► main ──(auto)──► STAGING
                   │
                   └── tag vX.Y.Z ──► release.yml ──► STAGING ──► PROD
```

1. `git switch -c feature/ma-fonctionnalite`
2. commits, push, **Pull Request** vers `main` → le CI (`ci.yml`) tourne.
3. merge de la PR → `staging.yml` déploie sur staging.
4. quand staging est validé, on **taggue une release** :
   ```bash
   git switch main && git pull
   git tag v1.2.3 -m "release 1.2.3"
   git push origin v1.2.3
   ```
   `release.yml` build+push l'image `v1.2.3`, déploie staging **puis** prod.

## Versionnage (SemVer)

`vMAJEUR.MINEUR.CORRECTIF` :
- **CORRECTIF** (`v1.2.3 → v1.2.4`) : correctifs sans changement de comportement.
- **MINEUR** (`v1.2.0 → v1.3.0`) : nouveautés rétrocompatibles.
- **MAJEUR** (`v1.x → v2.0.0`) : changements cassants (ex. migration
  irréversible).

## Rollback = redéployer le tag précédent

Le rollback n'est pas un commit « revert » mais un **redéploiement du tag n-1**,
dont l'image est déjà sur GHCR. Deux voies :
- workflow **Rollback** (manuel) — champ tag vide = n-1 ;
- ou re-tag/relance ciblée. Voir [rollback.md](rollback.md).

## Hotfix (correctif urgent sur la prod)

Partir du **tag en production**, pas de `main` (qui peut être en avance) :

```bash
git switch -c hotfix/1.2.4 v1.2.3     # branche depuis le tag en prod
# correction…
git commit -am "hotfix: …"
git tag v1.2.4 -m "hotfix 1.2.4"
git push origin v1.2.4                # release.yml -> staging -> prod
```

Puis **reporter le correctif sur `main`** (merge/cherry-pick) pour ne pas le
perdre à la prochaine release.

## Protection de `main` (à activer sur GitHub)

- Require a pull request before merging (au moins 1 review).
- Require status checks to pass → le job **CI**.
- Interdire les push directs / le force-push.

## Versionner la chaîne elle-même

Ce repo `devops` est lui aussi tagué (`v1`, `v2`, …). Les projets épinglent
`@v1`. Un changement cassant de la chaîne = un nouveau tag majeur ; les projets
migrent quand ils veulent. Voir le [README](../README.md#versionner-la-chaîne).
