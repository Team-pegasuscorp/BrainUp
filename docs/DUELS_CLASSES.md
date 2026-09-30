# Duels classés (onglet Quiz)

> Branche `test-boutique` (jeu + `brainup-backend`), 2026-09-30.
> Décision avec Sylou7 : **plus de solo dans l'onglet Quiz**. On choisit un mode, **Jouer** lance la recherche d'un adversaire. La catégorie est tirée au **draft** une fois l'adversaire trouvé (idée #8 de `VISION.md`).

## Parcours joueur

1. Onglet Quiz en tuiles (`category_select.gd`, `_build_duel_tiles`) : bandeau de rang (ligue, trophées, prochaine ligue), une tuile par mode (toucher = recherche d'adversaire), puis la tuile Défi du jour.
2. Écran `scenes/game/live_match.tscn` (`scripts/ui/live_match_screen.gd`) :
   - **Recherche** : carte du joueur, fenêtre ±X 🏆 qui s'élargit ; un bot prend la place après 20 s.
   - **Draft** : face-à-face (bannières, avatars, cadres), 3 catégories, 8 s pour voter.
     Même vote → cette catégorie ; votes différents → la roue tire entre les deux ; aucun vote → au hasard.
   - **Match** : bandeau des deux joueurs (score, vies ou horloge, « A répondu ! »), carte question animée, tuiles A–D qui apparaissent l'une après l'autre. À la révélation : bonne réponse en vert, mauvais choix qui tremble, avatar de chaque joueur posé sur sa tuile, scores qui défilent.
   - **LE SAVAIS-TU ?** (Classique ; Survie seulement après une erreur ; jamais en Chrono) : la carte affiche l'explication avec une jauge de lecture ; toucher = « prêt », on passe à la suite quand les deux sont prêts ou à la fin de la jauge.
   - **Résultat** : victoire / défaite / égalité, trophées **du serveur**, XP, Rejouer / Retour.
3. Le Défi du jour reste en haut de l'onglet (solo partagé, inchangé).

## Règles par mode (serveur = arbitre)

| Mode | Déroulé | Gagnant |
|------|---------|---------|
| Classique | 7 questions synchronisées, 10 s chacune | le plus de points |
| Survie | questions synchronisées, 3 vies chacun, une erreur ou un temps écoulé = −1 vie ; arrêt dès qu'un joueur tombe à 0 (40 questions max) | celui qui a encore des vies, sinon les points |
| Chrono | chacun son horloge de 60 s sur la même liste de questions, à son rythme ; erreur = −5 s ; l'horloge s'arrête pendant l'affichage de la réponse | le plus de points |

Survie et Chrono plafonnent le combo à 10 (comme le solo). Les trois modes comptent pour les trophées.

## Protocole (`ws://…/ws/live`)

- Client → `join_queue {player_id, mode, locale, trophies, trophy_range}` (sans `mode` mais avec `category` : ancien classique à catégorie fixe, gardé pour compatibilité).
- Serveur → `match_found {mode, draft: {choices, time_limit} | null, opponent_name, opponent_trophies, opponent_cosmetics, lives, clock, …}`
- Client → `draft_vote {category}` · Serveur → `draft_result {category, your_vote, opponent_vote}` puis `match_start {mode, category}`
- `question` / `answer` / `reveal` comme avant ; `reveal.your_result` porte `lives` (Survie) ou `clock` (Chrono).
- Modes synchronisés : `opponent_answered {index}` dès que l'autre a répondu ; `reveal` porte `explanation` et `read_time` (4 à 10 s selon la longueur, 0 = pas d'explication). Le serveur attend 1,5 s (couleurs) puis jusqu'à `read_time` ; client → `ready {index}`, serveur → `opponent_ready {index}` ; les deux prêts = question suivante.
- Chrono seulement : `opponent_progress {score, correct_count, answered, clock}` et `player_done` quand ton horloge est à 0.
- `match_over {mode, category, your_score, opponent_score, your_correct, your_answered, won, draw, trophy_delta, trophies, win_streak, loss_streak, …}`

## Côté jeu

- Les trophées affichés viennent de `match_over.trophies` (`SaveManager.record_duel_result`) : le client ne recalcule plus rien pour les duels.
- Un duel compte dans les stats de catégorie, l'historique (avec le nom de l'adversaire), les quêtes du jour, la série de jours et l'XP (+30 XP de victoire).
- L'ancien écran live de l'onglet Social (`social_tab.gd`) n'est plus appelé ; il peut être supprimé quand on sera d'accord.

## Tests

- Serveur : `python tools/test_live_modes.py` (un duel par mode contre le bot + un draft à deux), `test_live_trophies.py`, `test_live_cosmetics.py`.
- Téléphone branché : `adb reverse tcp:8000 tcp:8000` pour atteindre le serveur Docker du PC (à refaire après chaque export, qui relance adb).

## À faire / à décider

- Visuel de l'onglet Quiz et de l'écran de match (Sylou7).
- Survie / Chrono : équilibrage (40 questions max, pénalité 5 s, bots).
- Abandon en cours de match : aujourd'hui un joueur déconnecté perd ses questions (et ses vies en Survie).
