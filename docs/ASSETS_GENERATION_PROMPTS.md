# BrainUp — prompts génération assets (ComfyUI / RunPod)

Style global : premium mobile quiz, fond navy `#1C1830`, accents cyan `#12C4B8`, violet `#6B5CFF`, magenta `#E85D9A`, glow doux.

**Format cible (v4)** :
- catégories, badges et ligues : sujet détouré sur fond entièrement transparent ;
- avatars : portrait circulaire avec son fond.

Les cercles, couleurs et anneaux des icônes sont dessinés par l’interface Godot.

Modèle : **Juggernaut XL v9** (1024×1024 → finalize 128 ou 256 px).

---

## Icônes catégories (8 × 128 px)

Nommage : `assets/categories/{id}.png` — ids : `sport`, `cinema`, `history`, `science`, `geography`, `music`, `general`, `television`.

Prompt base :
```
single centered game UI object, isolated subject,
premium mobile quiz app style, clean silhouette, no text
```

Negative : `frame, background, scenery, text, watermark`

---

## Badges succès (14 × 128 px)

Nommage : `assets/badges/{achievement_id}.png` — voir `scripts/profile/achievements_catalog.gd`.

Prompt base :
```
achievement medal object, isolated subject, premium mobile game UI,
glow accent, no text, no background
```

---

## Badges ligue (5 × 128 px)

Nommage : `assets/leagues/{league_id}.png` — voir `scripts/profile/trophy_leagues.gd`.

Prompt base :
```
epic league trophy emblem, isolated centered object,
metallic glow, no text, no background
```

---

## Avatars demo social (14 × 256 px)

Nommage : `assets/avatars/demo/{slug}.png` — slugs dans `social_tab.gd` → `_demo_friends()`.

Prompt base :
```
cute animal mascot avatar, head and shoulders, centered in perfect circle,
round circular composition, soft navy violet cyan gradient disc background,
semi-flat illustration, no square frame, no text
```

---

## Workflow RunPod

```bash
/mnt/stockage/comfyui/run_brainup_pod.sh
# ou manuellement :
export COMFY_URL="https://<pod>-8188.proxy.runpod.net"
python3 /mnt/stockage/comfyui/gen_brainup.py --kind all --out ./raw
python3 /mnt/stockage/comfyui/finalize_brainup.py --src ./raw --out ./final
```

1. Pod 4090 sur volume `e9354hq21w` (voir `Documents/Onboarding-Collab/04-RunPod.md`).
2. Générer les images puis détourer catégories, badges et ligues avec IS-Net.
3. Centrer les sujets sur un canevas RGBA transparent de 128 px.
4. **Supprimer le pod** après usage.
5. Godot : Project → Reload (réimport PNG).
