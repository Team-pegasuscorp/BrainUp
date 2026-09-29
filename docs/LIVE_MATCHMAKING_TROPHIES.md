# Matchmaking live par trophées — contrat client ↔ backend

> Spécification pour `quizz-backend` (FastAPI / `ws://…/ws/live`)  
> Client Godot déjà prêt : `NetworkManager`, `LiveMatchmaking`, `social_tab`  
> Voir aussi [`TROPHIES_AND_MATCHMAKING.md`](TROPHIES_AND_MATCHMAKING.md)

---

## 1. Objectif

Rendre le matchmaking **live classé** cohérent avec le ladder Clash-of-Clans du client :

1. Apparier d’abord des joueurs **proches en trophées**.
2. **Élargir** progressivement la fenêtre si personne n’est trouvé.
3. Renvoyer **`opponent_trophies`** pour que le client calcule le **vrai** delta de coupes (upset vs underdog).

Sans le point 3, le client suppose `opponent_trophies == mes trophées` → gain/perte « à égalité » uniquement.

---

## 2. État actuel

| Couche | Statut |
|--------|--------|
| Client — `join_queue` avec `trophies` + `trophy_range` | ✅ |
| Client — `widen_search` toutes les 8 s | ✅ |
| Client — UI « Recherche… ±X 🏆 » | ✅ |
| Client — settle avec `opponent_trophies` | ✅ (branche `match_found` / `match_over`) |
| Backend — honorer `trophy_range` / `widen_search` | ⬜ à faire dans `quizz-backend` |
| Backend — renvoyer `opponent_trophies` | ⬜ à faire dans `quizz-backend` |

Repo backend (hors ce dépôt) : typiquement `~/Documents/quizz-backend` — fichiers `live_match.py` / file en mémoire.

---

## 3. Flux WebSocket

```
Client A                         Serveur                         Client B
   |                                |                                |
   |---- join_queue {trophies,      |                                |
   |      trophy_range: 50} ------->|                                |
   |                                |<---- join_queue {trophies, ----|
   |                                |       trophy_range: 50}        |
   |                                |                                |
   |   (pas de match dans ±50)      |                                |
   |---- widen_search {range:100} ->|  (met à jour A.range)          |
   |                                |---- widen_search {range:100} --|
   |                                |                                |
   |                                |  match si |A.cups−B.cups| ≤    |
   |                                |  min(A.range, B.range)         |
   |<--- match_found {              |---> match_found {              |
   |      opponent_trophies: B} ----|      opponent_trophies: A} ----|
   |                                |                                |
   |         … 7 × question / answer / reveal …                      |
   |<--- match_over {               |---> match_over {               |
   |      opponent_trophies: B,     |      opponent_trophies: A,     |
   |      your_score, …} -----------|      your_score, …} -----------|
```

---

## 4. Messages client → serveur

### 4.1 `join_queue` (déjà envoyé)

```json
{
  "type": "join_queue",
  "player_id": "<uuid>",
  "category": "sport",
  "locale": "fr",
  "trophies": 2845,
  "trophy_range": 50
}
```

| Champ | Type | Sens |
|-------|------|------|
| `trophies` | int ≥ 0 | Rating du joueur (source de vérité client pour le matchmaking) |
| `trophy_range` | int ≥ 0 | Demi-fenêtre acceptée : adversaire dans `[trophies−range, trophies+range]` |

Valeurs initiales client : `trophy_range = 50` (`LiveMatchmaking.RANGE_STEPS[0]`).

### 4.2 `widen_search` (déjà envoyé, toutes les ~8 s)

```json
{
  "type": "widen_search",
  "trophies": 2845,
  "trophy_range": 100
}
```

Paliers client : **50 → 100 → 200 → 400 → 800 → 100000** (≈ illimité).

**Le serveur doit** mettre à jour l’entrée du joueur en file (`trophies` + `trophy_range`) et **ne pas** le retirer de la queue.

---

## 5. Messages serveur → client

### 5.1 `match_found` — **ajouter** `opponent_trophies`

Exemple attendu (champs existants + nouveau) :

```json
{
  "type": "match_found",
  "match_id": "abc123",
  "opponent_name": "Lucas",
  "opponent_id": "<uuid>",
  "opponent_trophies": 2910,
  "category": "sport"
}
```

Variante aussi acceptée par le client :

```json
{
  "type": "match_found",
  "opponent": { "name": "Lucas", "id": "...", "trophies": 2910 }
}
```

### 5.2 `match_over` — **répéter** `opponent_trophies`

```json
{
  "type": "match_over",
  "match_id": "abc123",
  "won": true,
  "your_score": 820,
  "opponent_score": 640,
  "opponent_trophies": 2910
}
```

Le client lit d’abord `match_over.opponent_trophies`, sinon le cache de `match_found`.

---

## 6. Règle de matching (serveur)

Pour deux joueurs A et B dans la **même** file (même `category`, idéalement même `locale`) :

```
compatible(A, B) ⇔
  |A.trophies − B.trophies| ≤ min(A.trophy_range, B.trophy_range)
```

Utiliser le **min** des deux ranges : un joueur encore en ±50 ne doit pas être forcé contre quelqu’un qui a déjà élargi à ±800.

Ordre recommandé :

1. Parmi les candidats compatibles, préférer le **plus petit écart** de trophées.
2. En égalité, FIFO (premier entré en file).
3. Si personne de compatible → rester en file jusqu’au prochain `widen_search` ou arrivée d’un joueur.

**Fallback legacy** : si un client ancien n’envoie pas `trophies` / `trophy_range`, traiter comme `trophies = 0`, `trophy_range = 100000` (comportement « premier trouvé », rétrocompatible).

---

## 7. Modèle de file (référence)

Structure d’une entrée en mémoire (mono-process actuel) :

```python
@dataclass
class QueueEntry:
    player_id: str
    websocket: WebSocket
    category: str
    locale: str
    trophies: int = 0
    trophy_range: int = 100_000  # legacy default = unrestricted
    joined_at: float = 0.0
```

Au `join_queue` : créer / remplacer l’entrée, puis tenter un match.

Au `widen_search` : mettre à jour `trophies` + `trophy_range` de **ce** `player_id`, puis retenter un match.

Pseudo-code :

```python
def try_match(queue: list[QueueEntry], newcomer: QueueEntry) -> tuple[QueueEntry, QueueEntry] | None:
    best = None
    best_gap = None
    for other in queue:
        if other.player_id == newcomer.player_id:
            continue
        if other.category != newcomer.category:
            continue
        gap = abs(other.trophies - newcomer.trophies)
        limit = min(other.trophy_range, newcomer.trophy_range)
        if gap > limit:
            continue
        if best is None or gap < best_gap:
            best, best_gap = other, gap
    if best is None:
        return None
    return newcomer, best
```

À l’émission de `match_found` / `match_over` pour A :

```python
await send(A, {
    "type": "match_found",  # ou match_over
    "match_id": match_id,
    "opponent_name": B.display_name,
    "opponent_id": B.player_id,
    "opponent_trophies": B.trophies,  # trophées au moment du match
    ...
})
```

Stocker `B.trophies` **au moment du match_found** dans l’objet `LiveMatch`, pour le renvoyer aussi dans `match_over` (même si B change de rating ailleurs).

---

## 8. Côté client Godot (déjà fait)

| Fichier | Rôle |
|---------|------|
| `scripts/profile/live_matchmaking.gd` | Paliers `RANGE_STEPS` + `STEP_SECONDS = 8` |
| `scripts/autoload/network_manager.gd` | Envoie `join_queue` / `widen_search` |
| `scripts/ui/social_tab.gd` | Cache `_live_opponent_trophies`, settle à la fin |
| `scripts/autoload/save_manager.gd` | `settle_versus_trophies(..., opponent_trophies)` |
| `scripts/profile/trophy_system.gd` | Formule CoC (gap + marge de score) |

### Settle

```gdscript
SaveManager.settle_versus_trophies(match_id, my_score, opponent_score, opponent_trophies)
```

- `opponent_trophies >= 0` → utilisé dans `TrophySystem.calculate_delta`
- `opponent_trophies < 0` (absent) → fallback **égal** (`opp_cups = mes trophées`)

Extraction flexible :

1. `data.opponent_trophies`
2. sinon `data.opponent.trophies`

---

## 9. Formule trophées (rappel — client)

```
gap_term = round((opponent_trophies − my_trophies) / 20)
margin_bonus = clamp(round((my_score − opponent_score) / 250), −5, +5)

Victoire : +clamp(30 + gap_term + margin_bonus, 5, 60)
Défaite  : −clamp(20 − gap_term − margin_bonus, 5, 50)
Égalité  : 0
```

+ bonus de série de victoires versus (exactement 3 / 5 / 10)  
+ consolation +10 à exactement 5 défaites versus d’affilée  

Le **serveur n’a pas besoin** de recalculer les trophées pour le MVP : le client settle localement. Plus tard : authoritative settle serveur + sync `players.trophies`.

---

## 10. Checklist d’implémentation backend

- [ ] Étendre l’entrée de file avec `trophies` + `trophy_range`
- [ ] Parser `join_queue` (defaults legacy si absents)
- [ ] Handler `widen_search` → update + `try_match`
- [ ] Matching avec `min(range_A, range_B)` + plus petit écart
- [ ] `match_found` inclut `opponent_trophies`
- [ ] `match_over` inclut `opponent_trophies` (valeur figée au match)
- [ ] Tests : deux bots avec 100 vs 120 (match en ±50) ; 100 vs 400 (pas de match avant widen)
- [ ] (Optionnel) persister `trophies` sur `players` et préférer la valeur DB à celle du client

---

## 11. Tests manuels

1. Lancer `quizz-backend` (`docker compose up`).
2. Deux clients Godot (profils isolés) → Social → Match en direct, même catégorie.
3. Vérifier logs WS : `join_queue` avec `trophy_range: 50`.
4. Si écart trop grand : après ~8 s, `widen_search` avec 100, etc.
5. À `match_found`, payload contient `opponent_trophies`.
6. Fin de match : delta 🏆 ≠ baseline égal si écart de coupes.

Outils existants :

- `tools/test_live_client.gd` (ce repo)
- `quizz-backend/tools/test_live_opponent.py` / `test_live_match.py`

---

## 12. Suite produit (hors scope immédiat)

1. Settle **authoritatif** serveur + sync trophées joueur.
2. Afficher le détail gap (ex. « +42 vs adversaire 2910 🏆 ») sur l’écran live over.
3. Filtrer aussi par `locale` strictement si le pool le permet.
4. Multi-workers : remplacer la file mémoire par Redis / Postgres LISTEN.

---

*Créé 2026-09-29 — contrat pour brancher le ladder trophées au live matchmaking.*
