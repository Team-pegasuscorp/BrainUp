# BrainUp — prompts génération assets (ComfyUI / RunPod)

Style global : premium mobile quiz, fond navy `#1C1830`, accents cyan `#12C4B8`, violet `#6B5CFF`, magenta `#E85D9A`, glow doux, fond transparent ou `#010010`.

Modèle recommandé : **Juggernaut XL v9** (512×512 ou 768×768, PNG transparent si possible).

---

## Icônes catégories (8 × 128 px)

Nommage : `assets/categories/{id}.png` — ids : `sport`, `cinema`, `history`, `science`, `geography`, `music`, `general`, `television`.

Prompt base :
```
game UI icon, single subject centered, flat premium mobile app style,
navy and cyan glow, soft gradient, no text, transparent background,
BrainUp quiz app, clean silhouette, 128px icon
```

| id | sujet |
|----|-------|
| sport | soccer ball |
| cinema | film clapperboard |
| history | ancient scroll |
| science | laboratory flask |
| geography | globe |
| music | musical note |
| general | light bulb |
| television | retro TV set |

Negative : `text, watermark, blurry, photorealistic face, cluttered`

---

## Badges succès (14 × 128 px)

Nommage : `assets/badges/{achievement_id}.png` — voir `scripts/profile/achievements_catalog.gd`.

Prompt base :
```
achievement badge icon, circular medal, premium mobile game UI,
glow accent color, navy rim, no text, transparent background, 128px
```

Ajouter l’accent par badge (teal, gold, violet, magenta, etc.) selon le champ `accent` du catalogue.

---

## Badges ligue (5 × 128 px)

Nommage : `assets/leagues/{league_id}.png` — voir `scripts/profile/trophy_leagues.gd`.

Prompt base :
```
trophy league badge, stylized cup shield emblem, premium quiz app,
metallic glow, no text, transparent background, 128px
```

---

## Avatars demo social (14–20 × 256 px)

Nommage : `assets/avatars/demo/{friend_id}.png` — ids dans `social_tab.gd` → `_demo_friends()`.

Prompt base :
```
stylized portrait avatar, shoulders up, friendly quiz gamer,
semi-flat illustration, soft navy violet cyan palette,
no text, no watermark, centered face, 256px square
```

Varier genre, cheveux, accessoires entre profils. Éviter le photoréalisme pur.

---

## Workflow RunPod

1. Créer pod 4090 sur volume `e9354hq21w` (voir `Documents/Onboarding-Collab/04-RunPod.md`).
2. Générer par batch, récupérer via fileserver `:3000`.
3. Copier dans `assets/` ci-dessus.
4. **Supprimer le pod** après usage.
