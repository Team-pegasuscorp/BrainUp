# Quizz backend

Backend multijoueur pour [Quizz](https://github.com) (Godot). Plan complet dans
`docs/MULTIPLAYER_PLAN.md` du dépôt du jeu.

## Lancer en local

```bash
cp .env.example .env
# éditer .env, changer POSTGRES_PASSWORD
docker compose up --build
```

Vérifier : `curl http://localhost:8000/health` doit renvoyer `{"status":"ok"}`.

## Structure

```
docker-compose.yml   # Postgres + API
db/init/             # schéma SQL exécuté au premier démarrage de Postgres
app/                  # service FastAPI
```

## Défi du jour partagé

- `GET /daily-challenge` : catégorie et seed du jour (jour UTC).
- `POST /daily-challenge/result` : envoie le résultat du joueur. Seul le premier résultat
  de la journée est conservé (`already_played: true` ensuite). Refusé (422) si
  impossible : `total_count != 7`, `correct_count > total_count`, `max_combo > correct_count`,
  score au-dessus du maximum théorique (910) ou score sans bonne réponse.
- `GET /daily-challenge/leaderboard?player_id=&limit=` : top du jour (rang = score, puis
  bonnes réponses, puis premier arrivé) + rang du joueur demandé.

La table `daily_results` (`db/init/003_daily_results.sql`) n'est créée automatiquement qu'au
premier démarrage de Postgres : sur une base existante, l'appliquer à la main :
`docker exec -i quizz-backend-postgres-1 psql -U quizz -d quizz < db/init/003_daily_results.sql`

## Live classé : trophées et anti-triche minimal

Contrat client ↔ serveur : `LIVE_MATCHMAKING_TROPHIES.md` (côté jeu).

- **Appariement** : `join_queue` porte `trophies` + `trophy_range`, `widen_search` élargit la fenêtre
  (paliers 50 → 100 → 200 → 400 → 800 → illimité, jamais rétrécie). Deux joueurs se rencontrent si
  l'écart ≤ la plus petite des deux fenêtres ; le plus proche gagne, puis le premier arrivé.
- **`match_found` / `match_over`** renvoient `opponent_trophies` (figé au moment du match) ;
  `match_over` ajoute `trophy_delta` (variation totale), son détail `trophy_match_delta` /
  `trophy_streak_bonus` / `trophy_loss_consolation`, et `trophies` (nouveau total serveur).
- **Le serveur fait foi** (`players.trophies`, migration `004_trophies.sql`) : le premier match classé
  importe la valeur du client une seule fois, plafonnée à 1 500 ; ensuite la valeur annoncée par le
  client est ignorée pour l'appariement. Le règlement est calculé côté serveur avec les mêmes règles que
  `TrophySystem` du jeu, bonus de série compris (+10 / +25 / +50 à exactement 3 / 5 / 10 victoires
  d'affilée, +10 à exactement 5 défaites, égalité = 0 et remise à zéro des séries) ; séries stockées
  dans `players.versus_win_streak` / `versus_loss_streak` (migration `005_versus_streaks.sql`).
- **Garde-fous** : un seul match live par compte (code 4009), `player_id` invalide refusé (4004),
  seule la première réponse valide à la question en cours compte (les réponses envoyées d'avance
  sont ignorées), messages invalides ignorés sans faire tomber le match.
- **`players.cheat_flags`** compte les signaux suspects (trophées annoncés > serveur + 250, choix
  invalide, réponse en moins de 0,25 s) pour une revue manuelle ; rien n'est bloqué automatiquement.

- **Bots** (`app/bots.py`) : un joueur seul en file depuis 20 s affronte un bot de son niveau
  (±30 trophées), avec un pseudo normal et sans aucun indicateur côté client. Le bot répond seul
  (précision et vitesse selon ses trophées et la difficulté de la question), n'est jamais stocké en
  base, et le match ne règle que la moitié de la variation de trophées (bonus de série entiers).
- **Classement** (`GET /leaderboard?category=all`) : trié par trophées serveur (`score` = trophées,
  affichés 🏆 côté jeu) ; seuls les joueurs ayant joué en classé y figurent. Complété par 80 bots
  cachés (`leaderboard_bots`, `app/leaderboard_bots.py`, migration `006_leaderboard_bots.sql`) :
  créés à la première requête, mêmes champs qu'un vrai joueur, ils bougent un peu chaque jour
  (−40 à +60 trophées). Avec une catégorie précise, l'ancien classement par meilleur score reste.
- **Questions** : `app/data` est synchronisé avec le jeu (1 202 questions) ; en live, « general »
  (Culture générale) pioche dans toutes les catégories, comme `QuestionLoader` côté jeu.

Sur une base existante, appliquer les migrations à la main :
`docker exec -i quizz-backend-postgres-1 psql -U quizz -d quizz < db/init/004_trophies.sql` (puis `005_versus_streaks.sql`)

Test : `python tools/test_live_trophies.py` (stack lancée, `pip install websockets`).
