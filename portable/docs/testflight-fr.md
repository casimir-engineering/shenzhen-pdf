# TestFlight macOS — guide INTUITION

Guide pas-à-pas pour publier **Shenzhen PDF** en beta macOS via TestFlight.

Équipe détectée sur ce Mac : **INTUITION Robotique & Technologies** (`66LJ4BV7Q3`).

## État actuel (vérifier avec le script)

```sh
./portable/check-testflight-ready.sh
```

| Élément | Statut typique |
|---------|----------------|
| Xcode / clang / productbuild | OK |
| OpenSSL | OK |
| Apple Distribution | OK sur ce Mac |
| 3rd Party Mac Developer Installer | **À créer sur developer.apple.com** |
| Profil Mac App Store Connect | **À télécharger** |
| Transporter | **À installer depuis le Mac App Store** |

## Bundle ID recommandé

Utilisez un Bundle ID explicite sous votre équipe, par exemple :

```text
com.intuition.shenzhenpdf
```

Il doit être **identique** dans :
- Apple Developer → Identifiers
- App Store Connect → fiche app
- variable `MAC_BUNDLE_ID` au build

## Partie A — Actions en temps réel sur developer.apple.com

Ouvrez [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles**.

### A1. Créer le Bundle ID (5 min)

1. **Identifiers** → **+**
2. **App IDs** → Continue
3. Type : **App**
4. Description : `Shenzhen PDF`
5. Bundle ID : **Explicit** → `com.intuition.shenzhenpdf`
6. **Register**

### A2. Créer le certificat Installer (10 min)

Vous avez déjà **Apple Distribution**. Il manque le certificat **3rd Party Mac Developer Installer**.

1. **Certificates** → **+**
2. Choisir **Mac Installer Distribution** (libellé : *3rd Party Mac Developer Installer*)
3. Sur le Mac : **Trousseaux d'accès** → menu **Trousseau d'accès** → **Assistant de certification** → **Demander un certificat à une autorité de certification**
4. Email + nom → **Enregistrer sur le disque** → fichier `.certSigningRequest`
5. Uploader la CSR sur le site Apple → **Continue** → **Download**
6. Double-cliquer le `.cer` pour l'installer dans le trousseau **login**

Vérification locale :

```sh
security find-identity -v | grep "3rd Party Mac Developer Installer"
```

### A3. Créer le profil de provisioning (5 min)

1. **Profiles** → **+**
2. **Mac App Store Connect** (distribution Mac App Store)
3. App ID : `com.intuition.shenzhenpdf`
4. Certificat : **Apple Distribution: INTUITION Robotique & Technologies**
5. Profile Name : `ShenzhenPDF AppStore`
6. **Generate** → **Download**
7. Placer le fichier :

```text
~/Downloads/ShenzhenPDF_AppStore.provisionprofile
```

## Partie B — Actions sur App Store Connect

Ouvrez [appstoreconnect.apple.com](https://appstoreconnect.apple.com).

### B1. Accords (si pas déjà fait)

**Agreements, Tax, and Banking** → accepter le **Paid Applications Agreement** (même app gratuite).

### B2. Créer l'app macOS (5 min)

1. **Apps** → **+** → **New App**
2. Plateformes : **macOS** uniquement
3. Name : `Shenzhen PDF`
4. Primary Language : French ou English
5. Bundle ID : `com.intuition.shenzhenpdf`
6. SKU : `shenzhenpdf-mac-001`
7. User Access : Full Access
8. **Create**

Pour TestFlight, pas besoin de remplir toutes les métadonnées App Store tout de suite.

## Partie C — Build et upload (sur votre Mac)

### C1. Installer Transporter

Mac App Store → chercher **Transporter** → installer.

### C2. Vérifier la préparation

```sh
./portable/check-testflight-ready.sh
```

Le script affiche la commande exacte si tout est prêt.

### C3. Lancer le build TestFlight

```sh
MAC_BUNDLE_ID=com.intuition.shenzhenpdf \
MAC_VERSION=26.6.7 \
MAC_BUILD=1 \
MAC_APPSTORE_IDENTITY="Apple Distribution: INTUITION Robotique & Technologies (66LJ4BV7Q3)" \
MAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: INTUITION Robotique & Technologies (66LJ4BV7Q3)" \
MAC_PROVISIONING_PROFILE="$HOME/Downloads/ShenzhenPDF_AppStore.provisionprofile" \
OPEN_TRANSPORTER=1 \
./portable/build-mac-testflight.sh
```

Résultat :

```text
dist/ShenzhenPDF-testflight-26.6.7-1.pkg
```

**Règle importante :** `MAC_BUILD` doit augmenter à chaque upload (1, 2, 3…).

### C4. Upload via Transporter

1. Transporter s'ouvre avec le `.pkg`
2. Se connecter avec l'Apple ID App Store Connect
3. **Deliver**
4. Attendre **Processing** dans App Store Connect (5–30 min)

## Partie D — Activer TestFlight

1. App Store Connect → **Shenzhen PDF** → **TestFlight**
2. **Internal Testing** → créer un groupe → ajouter le build
3. Les membres de l'équipe reçoivent l'invitation
4. Sur Mac testeur : installer l'app **TestFlight** → accepter l'invitation → installer Shenzhen PDF

Pour des testeurs externes : **External Testing** → review beta Apple (plus long la première fois).

## Dépannage rapide

| Problème | Solution |
|----------|----------|
| `MAC_INSTALLER_IDENTITY` manquant | Créer certificat Mac Installer Distribution (A2) |
| Profil introuvable | Télécharger et placer dans `~/Downloads/` |
| Bundle ID mismatch | Aligner Apple, profil et `MAC_BUNDLE_ID` |
| Build number déjà utilisé | Incrémenter `MAC_BUILD` |
| OCR ne marche pas en beta | Normal en sandbox App Store ; voir notes dans `testflight.md` |

## Références

- Script build : `portable/build-mac-testflight.sh`
- Vérification : `portable/check-testflight-ready.sh`
- Checklist EN : `portable/docs/testflight.md`
