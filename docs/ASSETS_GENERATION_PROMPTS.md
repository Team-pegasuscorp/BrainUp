# BrainUp — prompts génération assets (ComfyUI / RunPod)

Style global : premium mobile quiz, fond navy `#1C1830`, accents cyan `#12C4B8`, violet `#6B5CFF`, magenta `#E85D9A`, glow doux.

**Format cible (v3)** : PNG **circulaire** — disque navy uniforme + sujet centré + alpha transparent hors cercle. Finalisation via `finalize_brainup.py` (masque rond + gradient radial).

Modèle : **Juggernaut XL v9** (1024×1024 → finalize 128 ou 256 px).

---

## Icônes catégories (8 × 128 px)

Nommage : `assets/categories/{id}.png` — ids : `sport`, `cinema`, `history`, `science`, `geography`, `music`, `general`, `television`.

Prompt base :
```
perfect circular game UI icon, single centered object inside round badge,
symmetrical round composition, soft navy circular disc background,
cyan violet glow rim, no square frame, no corners, no text
```

Negative : `square frame, rectangular background, corner vignette, text, watermark`

---

## Badges succès (14 × 128 px)

Nommage : `assets/badges/{achievement_id}.png` — voir `scripts/profile/achievements_catalog.gd`.

Prompt base :
```
achievement badge icon, circular medal, centered in round disc,
premium mobile game UI, glow accent, navy rim, no text, no square frame
```

---

## Badges ligue (5 × 128 px)

Nommage : `assets/leagues/{league_id}.png` — voir `scripts/profile/trophy_leagues.gd`.

Prompt base :
```
epic circular league rank badge, trophy emblem centered in round medal,
soft navy round disc background, metallic glow, no text, no square frame
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
2. Générer 41 jobs, finaliser (fond rond), copier dans `BrainUp/assets/`.
3. **Supprimer le pod** après usage.
4. Godot : Project → Reload (réimport PNG).
