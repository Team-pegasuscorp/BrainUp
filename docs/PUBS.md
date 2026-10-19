# Pubs récompensées

> Branche `test-neurones-pubs` (jeu + `brainup-backend`), 2026-10-19.
> Décisions (page de décisions, 20/20) : **pubs récompensées seulement**, au choix du joueur, aucune pub
> imposée ; régie **AdMob** ; public 13 ans et plus.

## Pour le joueur

- Onglet Boutique, en haut : carte **« Neurones gratuits »** (Android seulement) → une pub vidéo, puis
  **+15 Neurones**, **5 fois par jour** au plus. La carte dit combien il en reste, « Chargement d'une
  pub… » tant qu'aucune n'est prête, « Reviens demain » une fois le plafond atteint.
- Premier lancement en Europe : formulaire de consentement RGPD de Google (UMP), avant toute pub.

## Technique

- Plugin **Poing Studios AdMob v5.1.0** (`addons/admob`, MIT), testé jusqu'à Godot 4.7.2. Seul le module
  `ads` est installé dans `addons/admob/android/bin/` (pas de médiation). Les binaires iOS sont téléchargés
  par le plugin quand ils manquent et ignorés par git.
- L'export Android passe par **Gradle** (`gradle_build/use_gradle_build=true` dans `export_presets.cfg`,
  fichier local) : le modèle `android/` est généré, ignoré par git. Export :
  `godot --headless --path . --install-android-build-template --export-debug "Android" <apk>`.
- `scripts/autoload/ads_manager.gd` (`AdsManager`) : consentement → `MobileAds.initialize()` → précharge
  une pub → `show_rewarded()` → à la fermeture, si la pub a été vue jusqu'au bout,
  `NetworkManager.claim_ad_reward()` → `POST /ads/reward {device_id, day}`.
- Serveur (`app/shop.py`) : `AD_COINS = 15`, `ADS_PER_DAY = 5` (jour du téléphone, comme les quêtes),
  ligne `ad` dans `coin_ledger` ; `ads_left` et `rules.ad` dans l'état de la boutique.

## Avant la mise en ligne

- Créer l'application dans la console AdMob (compte de Yannick) ; remplacer l'**identifiant
  d'application** de test (`admob/general/android/app_id` dans les réglages du projet) et le **bloc
  d'annonces** de test (`AdsManager.REWARDED_UNIT_ANDROID`).
- **Vérification côté serveur** (SSV AdMob) : AdMob appelle le serveur quand une pub est vue ; il faut une
  adresse publique (Hetzner). En attendant, c'est le téléphone qui déclare la pub et seul le plafond
  quotidien limite la triche.
- Déclarer les pubs dans la fiche Play Store et vérifier le formulaire de consentement dans la console AdMob.
