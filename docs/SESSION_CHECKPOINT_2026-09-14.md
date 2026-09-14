# Checkpoint session — 14 septembre 2026 (~16h44 UTC+2)

> **Reprendre ici après redémarrage PC.**  
> Projet : BrainUp — phase **visuels / assets**.

---

## Où on en est (résumé)

1. **Repo local synchronisé** avec GitHub (`Team-pegasuscorp/BrainUp`).
2. **Audit visuel complet** fait — inventaire de tout ce qu'il faut produire.
3. **RunPod** : clé API trouvée, **aucun pod actif** au moment du checkpoint.
4. **Prochaine action prévue** : intégration Godot (brancher PNG dans le code) — **assets générés le 14/09 ~17h20**.

---

## État Git BrainUp

| | |
|---|---|
| **Chemin** | `/home/Pegase/BrainUp` |
| **Branche** | `main` |
| **Remote** | `https://github.com/Team-pegasuscorp/BrainUp.git` |
| **Commit** | `998952f` — *Polish Social friend detail and create-challenge category chips.* |
| **Statut** | Propre, à jour avec `origin/main` |
| **Modifs locales** | Aucune (sauf ce fichier checkpoint) |

---

## Ce qu'on a fait dans cette session

### 1. Import / sync du repo GitHub
- Le dossier local existait déjà mais était **7 commits en retard**.
- `git pull --ff-only` effectué → aligné sur GitHub.

### 2. Audit complet des visuels
Analyse du code, scènes, `assets/`, catalogues mock.

**Constat clé :** le projet mélange ~10 fichiers image réels + emoji procédural + shaders.

---

## Inventaire assets — à produire (plan validé)

### Priorité immédiate (bloquant)
| Asset | Chemin attendu | Statut |
|-------|----------------|--------|
| Avatar par défaut | `assets/ui/default_avatar.svg` | **MANQUANT** — référencé dans `save_manager.gd` |

### Déjà présents et branchés (OK)
- `assets/ui/logo_app.png` (header 80×80)
- `assets/ui/brainup_wordmark.png` (280×64)
- `assets/ui/icon_settings.png` (56 px)
- `assets/ui/icon_tab_home.svg`, `icon_tab_multiplayer.svg`, `icon_tab_leaderboard.svg`, `icon_tab_profile.svg` (44×44)
- `assets/ui/icon_tab_quiz.png` (FAB 52 px)
- `icon.svg` (icône projet Godot)
- `assets/fonts/NotoColorEmoji.ttf`

### Présents mais orphelins (non branchés)
- `assets/branding/brainup-app-icon.png` (1024×1024 — export stores)
- `assets/branding/brainup_brand_sheet.jpg`, logos officiels, variantes concept
- `assets/ui/icon_quiz_brain.png` / `.svg` — candidat FAB Quiz
- `assets/ui/logo_wordmark.png` — doublon wordmark

### Procédural aujourd'hui → à remplacer si identité unifiée
| Type | Quantité | Source code | Specs recommandées |
|------|----------|-------------|-------------------|
| Icônes catégories | 8 | `profile_snapshot.gd` → `_category_icon()` | PNG/SVG 128 px, fond transparent |
| Badges succès | 14 | `achievements_catalog.gd` | 128×128, glow par accent |
| Badges ligue | 5 | `trophy_leagues.gd` | 96–128 px |
| Avatars demo social | 14 profils | `social_tab.gd` → `_demo_friends()` | 256×256 portraits stylisés |
| Stats / médailles / drapeaux | emoji | divers | optionnel MVP |

**Catégories (emoji actuels) :** sport ⚽, cinema 🎬, history 📜, science 🧪, geography 🌍, music 🎵, general 💡, television 📺

### Bannières
- **Pas implémentées** dans le code — header = couleur unie `#010010`, fonds = shaders.
- Bannière profil/couverture = feature future (nécessite code + assets ~1200×300).

### Photos profil utilisateur
- Runtime : `user://profile_avatar.png` (import 256×256) — **déjà fonctionnel**.

---

## RunPod — état au checkpoint

| | |
|---|---|
| **Doc référence** | `/home/Pegase/Documents/Onboarding-Collab/04-RunPod.md` |
| **Clé API** | `/mnt/stockage/comfyui/.runpod_key` |
| **Token Orion** | `/mnt/stockage/comfyui/.pod/orion_token` |
| **Volume réseau** | `e9354hq21w` (EU-RO-1, ComfyUI + Juggernaut XL) |
| **Scripts gen** | `/mnt/stockage/comfyui/` (`gen_creatures.py`, `gen_pitchtactics_cards.py`, etc.) |
| **Pod actif** | **Aucun** (`GET /v1/pods` → `[]`) |
| **Coût pod 4090** | ~0,74 $/h — **supprimer le pod après usage** |

**Accès pod (quand créé) :**
- ComfyUI : `https://<podId>-8188.proxy.runpod.net`
- Fileserver : `https://<podId>-3000.proxy.runpod.net`
- Pas de SSH fiable — tout via proxy/fileserver.

---

## Plan de reprise (dans l'ordre)

### Étape A — Sans GPU (local, gratuit)
1. Créer `assets/ui/default_avatar.svg`
2. Créer structure dossiers : `assets/categories/`, `assets/badges/`, `assets/leagues/`, `assets/avatars/demo/`
3. Rédiger prompts/workflow ComfyUI BrainUp (style glow navy/violet/cyan)

### Étape B — RunPod ComfyUI (GPU)
1. Créer pod RTX 4090 sur volume `e9354hq21w`
2. Générer : 8 icônes catégories, 14 badges, 5 ligues, 14–20 avatars demo
3. Récupérer via fileserver `:3000`
4. **Supprimer le pod**

### Étape C — Intégration Godot
1. Brancher assets dans le code (remplacer emoji par textures où pertinent)
2. Brancher `icon_quiz_brain.png` sur FAB si validé
3. Tester profil / social / badges en jeu

---

## Fichiers clés à relire au redémarrage

```
/home/Pegase/BrainUp/docs/SESSION_CHECKPOINT_2026-09-14.md   ← CE FICHIER
/home/Pegase/BrainUp/scripts/autoload/save_manager.gd           ← DEFAULT_AVATAR_PATH
/home/Pegase/BrainUp/scripts/config/ui_tokens.gd               ← chemins header/nav
/home/Pegase/BrainUp/scripts/profile/achievements_catalog.gd   ← 14 badges
/home/Pegase/BrainUp/scripts/profile/trophy_leagues.gd         ← 5 ligues
/home/Pegase/BrainUp/scripts/profile/profile_snapshot.gd       ← icônes catégories
/home/Pegase/BrainUp/scripts/ui/social_tab.gd                   ← 14 amis demo
/home/Pegase/Documents/Onboarding-Collab/04-RunPod.md           ← procédure RunPod
/mnt/stockage/comfyui/                                          ← scripts génération GPU
```

---

## Message utilisateur au redémarrage

> « On reprend BrainUp visuels — lis `docs/SESSION_CHECKPOINT_2026-09-14.md` »

Ou simplement : **« on reprend où on en était »** — l'agent retrouvera ce fichier.
