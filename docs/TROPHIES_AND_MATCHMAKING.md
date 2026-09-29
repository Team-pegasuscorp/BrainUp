# Système de trophées & matchmaking live

> Document de session — conception et implémentation côté client Godot  
> Branche de travail : `modif` (poussée sur `main` au fil des itérations UI)

---

## 1. Contexte

Avant ce travail, le compteur 🏆 du profil / accueil n’était **pas** un vrai système de trophées : il affichait surtout le **meilleur score** (`best_score`) pour choisir la ligue.  

Objectif : un vrai ladder **multi 1v1**, inspiré de Clash of Clans, découplé du solo et des défis amis (anti-farm).

---

## 2. Banque de trophées

| Élément | Détail |
|--------|--------|
| Persistance | `SaveManager.trophies` dans `user://save.json` |
| Migration | Si la clé `trophies` est absente → one-shot depuis `best_score` global |
| Ligue | `TrophyLeagues.for_trophies(trophies)` — paliers provisoires (bronze → diamant) |
| Affichage | Accueil / profil / saison via `ProfileSnapshot._build_ranking` |

Fichiers clés :
- `scripts/autoload/save_manager.gd`
- `scripts/profile/trophy_leagues.gd`
- `scripts/profile/profile_snapshot.gd`

---

## 3. Qui gagne (ou perd) des trophées ?

| Mode | Trophées | Remarque |
|------|----------|----------|
| Solo (classique / survie / time attack) | **Non** | XP seulement |
| Défi du jour | **Non** | XP + bonus daily |
| **Défi ami (async)** | **Non** | XP + compteur V–D tête-à-tête (anti-triche) |
| **Match live / classé** | **Oui** | Formule type Clash of Clans |

Implémentation : `scripts/profile/trophy_system.gd` + `SaveManager.settle_versus_trophies(...)`.

Les défis amis ne passent **plus** par `settle_versus_trophies` ; ils utilisent `record_friend_rivalry(...)`.

---

## 4. Formule Clash of Clans (live / versus classé)

Quand **les deux scores** sont connus :

### Delta de base (trophées égaux)

| Issue | Delta |
|-------|--------|
| Victoire | **+30** (borné entre +5 et +60) |
| Défaite | **−20** (borné entre −5 et −50) |
| Égalité | **0** |

### Ajustements

- **Écart de trophées** : battre plus fort → plus de gain ; perdre contre plus faible → plus de perte (`DIFF_DIVISOR = 20`).
- **Marge de score** : petit bonus/malus (±5 max) selon l’écart de points du quiz.
- Si les trophées adverses sont inconnus → on suppose **égal** (baseline +30 / −20).

### Quand ça s’applique

- **Live** : à `match_over` (`social_tab` → `settle_versus_trophies("live:…")`).
- **Défi async** : **plus de trophées** (voir §6).

---

## 5. Bonus / consolation de séries (versus classé)

Compteurs persistés : `versus_win_streak`, `versus_loss_streak`.

### Victoires d’affilée (bonus exact au palier)

| Série | Bonus |
|-------|--------|
| 3 | **+10** 🏆 |
| 5 | **+25** 🏆 |
| 10 | **+50** 🏆 |

Défaite ou égalité → série de victoires remise à **0**.

### Défaites d’affilée (motivation)

| Série | Consolation |
|-------|-------------|
| 5 défaites | **+10** 🏆 |

Victoire ou égalité → série de défaites remise à **0**.

Le total retourné par `settle_versus_trophies` = delta match + bonus série + consolation.

---

## 6. Défis amis — anti-triche

Pour éviter de farmer des trophées entre potes :

1. **Aucun trophée** sur les défis amis.
2. **XP** inchangé (même formule de match).
3. **Compteur face-à-face** `friend_rivalries` :
   - clé = id ami (ou pseudo),
   - `{ wins, losses, draws, settled: [match_ids] }`,
   - idempotent par code de défi.

UI :
- Fiche ami : tuile **Vs toi** (`W-L`).
- Fin de défi : score + `Face-à-face W-L`.
- Écran résultats : `+XP · Pas de trophées (défi ami)`.

---

## 7. Calcul d’XP (rappel, inchangé dans l’esprit)

### XP de partie

```
XP = correct_count × 10 + score ÷ 10   (division entière)
```

- Survie / time attack : plafonné à **300** (`MODE_XP_CAP`).
- Classique / défi ami / daily (hors bonus) : pas de plafond sur cette formule.

### Bonus éventuels

| Source | Montant |
|--------|---------|
| Défi du jour (1ʳᵉ fois / jour) | +50 XP |
| Série de jours joués | `(streak−1)×3` (max 25) + petits paliers (3→25 … 100→200) |
| Quêtes daily (home) | XP au claim |

### Niveau

```
XP pour le prochain niveau = round(100 × 2,15^(level − 1))
```

| Passage | XP barre |
|---------|----------|
| 1 → 2 | 100 |
| 2 → 3 | ~215 |
| 3 → 4 | ~462 |
| 4 → 5 | ~993 |
| 5 → 6 | ~2 135 |

Croissance exponentielle adoucie (`XP_LEVEL_GROWTH` dans `save_manager.gd`).

La save stocke l’**XP totale cumulée** (`xp_is_total`) : rien n’est soustrait au level-up ; le niveau est recalculé à partir du total, la barre = XP dans le palier en cours.

---

## 8. Matchmaking live basé sur les trophées

Fichiers :
- `scripts/profile/live_matchmaking.gd`
- `scripts/autoload/network_manager.gd`

### Protocole client

1. `join_queue` envoie :
   - `trophies` (rating),
   - `trophy_range` (fenêtre ± initiale = **50**).
2. Toutes les **8 s** sans adversaire → `widen_search` avec une fenêtre plus large :
   - ±50 → ±100 → ±200 → ±400 → ±800 → illimité (~100000).
3. UI : `Recherche… ±X 🏆`.

### Attendu côté serveur (`quizz-backend`)

- Matcher d’abord dans `±trophy_range` autour des trophées du joueur.
- À chaque `widen_search`, élargir la bande acceptée.
- Sans ce support serveur, le client élargit mais le matchmaking reste “premier trouvé”.

---

## 9. Fichiers touchés (cœur trophées / social)

| Fichier | Rôle |
|---------|------|
| `scripts/profile/trophy_system.gd` | Formule CoC + bonus / consolation |
| `scripts/profile/live_matchmaking.gd` | Paliers d’élargissement |
| `scripts/autoload/save_manager.gd` | `trophies`, séries, rivalités amis, settle |
| `scripts/autoload/game_manager.gd` | Fin de round : pas de trophées en défi ami |
| `scripts/autoload/network_manager.gd` | Queue live + widen |
| `scripts/ui/social_tab.gd` | Live settle, H2H amis, UI recherche |
| `scripts/ui/results_screen.gd` | Affichage XP / message défi ami |
| `scripts/profile/profile_snapshot.gd` | Ranking = vrais trophées |
| `locale/ui.csv` | Chaînes FR/EN associées |

---

## 10. Suite suggérée

1. **Backend** (`quizz-backend`) : implémenter le contrat décrit dans [`LIVE_MATCHMAKING_TROPHIES.md`](LIVE_MATCHMAKING_TROPHIES.md) — honorer `trophies` + `trophy_range` + `widen_search` ; renvoyer `opponent_trophies` dans `match_found` / `match_over`.
2. ~~Brancher `opponent_trophies` dans `settle_versus_trophies`~~ ✅ (client : `social_tab` lit `match_found` / `match_over`).
3. Afficher le détail gap trophées sur l’écran live over une fois le backend en place.
4. Verrouiller les paliers de ligue (`TrophyLeagues`) quand le design est figé.
5. Synchro serveur des `friend_rivalries` (aujourd’hui local save).
6. Settle authoritatif côté serveur (anti-triche ladder).

---

## 11. Résumé en une phrase

**Les trophées sont un ladder multi type Clash (gain/perte + séries), le solo et les défis amis ne les touchent pas (XP + V–D amis), et la recherche live part des trophées puis élargit la fenêtre.**
