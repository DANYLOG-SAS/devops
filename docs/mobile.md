# Livraison mobile (Expo / EAS)

> Une app mobile ne se « déploie » pas comme un serveur. On **construit** un
> binaire signé, on le **publie** sur un store, la plateforme le **valide**, puis
> chaque utilisateur **met à jour**. La chaîne automatise les deux premières
> étapes ; les deux dernières n'appartiennent à personne d'autre qu'aux stores.

## Le parcours en entier

| # | Étape | Qui s'en charge | Automatisable |
|---|---|---|---|
| 1 | Vérifier (`expo-doctor`, bundle) | la chaîne, à chaque modification | ✅ déjà actif |
| 2 | Construire le binaire signé | EAS Build, sur tag `mobile-v*` | ✅ |
| 3 | Publier sur le store | EAS Submit | ✅ (après configuration) |
| 4 | Validation par Google/Apple | la plateforme (heures à jours) | ❌ |
| 5 | Mise à jour par l'utilisateur | l'utilisateur | ❌ |

## Étape 0 — le seul secret GitHub nécessaire

**`EXPO_TOKEN`** : [expo.dev](https://expo.dev) → *Account settings* → **Access
tokens** → *Create token*. À ajouter dans les secrets du dépôt du projet.

> 🔑 Point important : les identifiants de signature et les clés des stores
> **ne vont pas dans GitHub**. Ils sont stockés chez EAS et référencés par ce
> jeton. GitHub n'a donc jamais à connaître ta clé Google Play ni ton certificat
> Apple.

## Étape 1 — les clés de signature

À faire une fois, en local, dans le dossier de l'app :

```bash
npx eas-cli credentials
```

Laisse EAS générer et conserver le keystore Android (option recommandée : *Let
EAS handle it*). Sans ça, chaque build serait signé différemment et le store
refuserait les mises à jour.

⚠️ **Ne perds jamais ce keystore** : c'est lui qui prouve à Google que les
futures versions viennent bien de toi. EAS le sauvegarde, mais fais-en une copie
(`npx eas-cli credentials` → *Download*).

## Étape 2 — construire

**Sur tag** (livraison tracée) :
```bash
git tag mobile-v1.0.0 -m "première version Android" && git push origin mobile-v1.0.0
```

**À la demande** (binaire de test, sans créer de tag) : onglet **Actions** →
*Mobile Release* → **Run workflow** → choisir `preview` (APK installable
directement sur un téléphone) ou `production` (app-bundle pour le store).

Le binaire est téléchargeable sur [expo.dev](https://expo.dev) une fois le build
terminé.

## Étape 3 — publier automatiquement (Android)

Trois prérequis, tous côté Google et EAS :

1. **Compte Google Play Developer** — 25 $ une fois, sur
   [play.google.com/console](https://play.google.com/console).
2. **Fiche d'application créée** dans la console, et **première version envoyée
   manuellement**. Google exige que le tout premier `.aab` soit déposé à la main ;
   les suivants peuvent être automatisés.
3. **Compte de service Google** (clé JSON) :
   Google Cloud Console → *IAM & Admin* → *Service Accounts* → créer un compte →
   générer une clé JSON → puis, dans Play Console → *Utilisateurs et
   autorisations*, inviter ce compte avec le droit de publier.

   On confie ensuite cette clé à EAS (jamais à GitHub) :
   ```bash
   npx eas-cli credentials
   ```
   → *Android* → *Google Service Account* → fournir le fichier JSON.

Une fois ces trois points réglés, la publication devient automatique :

```yaml
# .github/workflows/mobile-release.yml
      eas-submit: ${{ github.event_name == 'push' }}    # publier sur chaque tag
```

Et pour iOS : compte Apple Developer (99 $/an) + clé d'API App Store Connect,
également confiée à EAS via `eas-cli credentials`.

## Numéros de version

Ton `eas.json` contient déjà ce qu'il faut :

```json
"cli":  { "appVersionSource": "remote" },
"build": { "production": { "autoIncrement": true } }
```

EAS incrémente le `versionCode` Android à chaque build. **Aucune intervention
manuelle**, et pas de conflit de numéro entre deux builds — un store refuse un
`versionCode` déjà utilisé.

Le numéro visible par l'utilisateur (`version` dans `app.json`) reste sous ton
contrôle : fais-le correspondre à ton tag (`mobile-v1.2.0` → `"version": "1.2.0"`).

## Un point de vigilance : compatibilité API

L'app installée sur un téléphone **ne se met pas à jour en même temps que ton
API**. Un utilisateur peut rester des semaines sur une ancienne version.

Conséquence concrète : ne retire jamais une route ou un champ d'API sans avoir
vérifié qu'aucune version en circulation ne l'utilise. La règle sûre est
d'**ajouter** sans retirer, puis de supprimer l'ancien seulement une fois le parc
migré.

C'est précisément le risque que la chaîne serveur ne peut pas détecter seule :
elle valide l'API et le web ensemble, mais pas les apps déjà installées.
