# Amis, défis entre amis et jokers

> Branche `test-defis-jokers` (jeu + `brainup-backend`), 2026-10-06.
> Le côté jeu des défis entre amis (onglet Social) était fait par Sylou7 sur des données de démo ;
> cette branche ajoute le serveur et branche l'onglet dessus, ainsi que les jokers du passe en duel.

## Pour le joueur

- **Onglet Social** : liste d'amis (présence en ligne / absent / hors ligne), demandes d'amis reçues,
  défis reçus, recherche de joueur.
- **Ajouter un ami** : taper au moins 2 lettres du pseudo → liste des joueurs trouvés, bouton « Ajouter »
  (« Accepter » si ce joueur nous avait déjà demandé : on devient amis tout de suite).
- **Défier un ami** : fiche de l'ami → Défier → choix du mode. Le défi reste valable **4 h**.
- **Accepter un défi** : seulement si l'ami qui a défié est **en ligne** (application ouverte). Les deux
  téléphones rejoignent alors une salle privée (catégorie tirée au sort comme en classé).
  Si l'autre ne vient pas dans les 90 s : « X n'a pas rejoint le duel ».
- **Duel amical** : pas de trophées, pas d'XP de passe, pas de victoire/défaite au profil (anti-triche
  entre amis). Compte : le bilan face à cet ami, l'XP de profil, les stats de catégorie, l'historique,
  et la quête du jour « Jouer un défi ».
- **Jokers en duel** (classé ou amical) : boutons sous les réponses si on en possède.
  - **50/50** : retire deux mauvaises réponses.
  - **+5 s** : 5 secondes de plus sur la question (en Chrono : 5 s de plus sur l'horloge).
  - Chaque sorte au plus **une fois par match**, avant d'avoir répondu. L'adversaire voit « 50/50 » / « +5 s ».

## Serveur (`brainup-backend`)

- Migration `db/init/009_friends_jokers.sql` : `friendships` (les deux sens), `friend_requests`,
  `friend_challenges` (pending → accepted → played, ou declined / cancelled / expired),
  `players.last_seen_at`, `players.level`, `players.jokers_used`.
- `app/friends.py` + routes dans `app/main.py` :
  `GET /social`, `GET /players/search`, `POST /friends/requests`, `.../{id}/accept|decline`,
  `POST /friends/remove`, `POST /friends/challenges`, `.../{id}/accept|decline`.
- **Présence** = dernier `/social` : le jeu l'interroge toutes les 15 s tant qu'il est ouvert.
  En ligne ≤ 45 s, absent ≤ 15 min.
- **Salle privée** : message WebSocket `join_friend` (`challenge_id`) au lieu de `join_queue`
  (`app/live_match.py`, `_friend_rooms`). Jamais de bot.
- **Jokers** : stock = jokers des paliers récupérés (toutes saisons) − `jokers_used` ;
  renvoyé dans `GET /pass` (`jokers`) et dans `match_found` ; message `joker` → `joker_result`
  (`removed` ou `bonus`) et `opponent_joker` chez l'adversaire.
- **Quêtes du jour** : `POST /pass/quest` reçoit le jour local du téléphone (`day`) ; le plafond de 3 se
  compte par ce jour (±1 jour autour de l'UTC accepté). Le jeu garde les réclamations non envoyées
  (`user://quest_outbox.json`) et les renvoie.
- Tests : `tools/test_friends.py`.

## Côté jeu

- `NetworkManager` : sondage `/social`, recherche, demandes, défis, `start_friend_match`, `send_joker`,
  file des quêtes.
- `social_tab.gd` : `SHOW_DEMO_WHEN_OFFLINE` garde les données de démo tant que le serveur n'a pas répondu.
- `live_match_screen.gd` : `GameManager.friend_challenge` = duel amical ; boutons de jokers.
- `SaveManager.record_friend_duel_result`, `SaveManager.set_jokers` (le serveur fait foi).

## Pas encore fait

- Retirer un ami depuis la fiche (route serveur prête : `POST /friends/remove`).
- Si j'ai défié un ami et qu'il accepte pendant que je suis dans une autre partie, le duel ne s'ouvre pas
  (il faut être dans l'application, hors partie).
- Comptes : l'identité reste l'identifiant de l'appareil ; pseudo non unique (la recherche montre le niveau
  et les trophées pour distinguer).
