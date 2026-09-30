# Passe de combat

> Branche `test-boutique` (jeu + `brainup-backend`), 2026-09-30.
> Choix : saisons de **6 semaines**, XP venant des **duels, du défi du jour, des quêtes du jour et de défis hebdo**,
> récompenses **pièces, cadres/bannières exclusifs, avatars exclusifs, jokers**. La voie premium sera vendue
> **en euros via Google Play** (avec comptes Google Play Jeux) : pas encore branché.

## Pour le joueur

- Onglet Quiz : bandeau « Passe de combat · palier N » → ouvre l'onglet **Passe** de la boutique.
- Onglet Passe (`scripts/ui/shop_page.gd`, `_build_pass`) :
  - en-tête : saison, semaine, jours restants, palier, barre d'XP du palier, état premium ;
  - « Tout récupérer (N) » quand des récompenses attendent ;
  - piste horizontale des 40 paliers : premium en haut (or), gratuit en bas (bleu) ; toucher une case prête = la récupérer ;
  - défis de la semaine avec leur progression, et le rappel des gains d'XP.
- Fin de duel : « +N XP de passe ».

## Règles (saison 1 : `brainup-backend/app/data/pass/season_1.json`)

| Source | XP |
|--------|----|
| Duel classé terminé | +100, +60 si victoire |
| Défi du jour (premier résultat du jour) | +150 |
| Quête du jour récupérée | +100, 3 par jour au plus |
| Défi de la semaine terminé | +400 à +800 |

800 XP par palier, 40 paliers (32 000 XP). Un joueur régulier (4 duels, défi et quêtes par jour ≈ 950 XP/jour + défis hebdo)
finit en 4 à 5 semaines.

Récompenses : pièces presque à chaque palier ; gratuit : 2 jokers 50/50 + 1 joker +5 s, bannière Aube, cadre Menthe glacée ;
premium : bannières Circuit, Forge, Aurore boréale, cadres Braise, Vague néon, Couronne de l'Éveil, 3 avatars exclusifs, jokers.
Les objets du passe sont dans `data/shop/catalog.json` avec `"source": "pass"` : jamais en vente, possédés seulement une fois gagnés.

## Serveur = arbitre

- Table `pass_progress` (`db/init/008_battle_pass.sql`), module `app/battle_pass.py`.
- L'XP des duels et du défi du jour est ajoutée par le serveur lui-même ; les quêtes (calculées dans le téléphone)
  sont réclamées mais plafonnées à 3 par jour ; les défis hebdo sont comptés à partir des résultats de duel.
- Routes (écritures identifiées par `device_id`, comme l'inscription) :
  `GET /pass?device_id=` · `POST /pass/claim {device_id, tier, track}` · `POST /pass/quest {device_id, quest_id}` ·
  `POST /pass/premium {device_id, receipt}`.
- Une récompense réclamée est appliquée à l'inventaire du téléphone (`SaveManager.apply_pass_reward`) : pièces,
  objet ou joker. L'inventaire lui-même reste local pour l'instant.

## Premium : état actuel

- `POST /pass/premium` refuse tout (402) **sauf** sur un serveur de développement lancé avec `PASS_DEV_UNLOCK=1`,
  qui accepte le reçu de test `"dev"` : le bouton « Débloquer le premium (test) » n'apparaît que dans ce cas.
- À faire : Google Play Jeux (connexion = compte joueur) + Google Play Billing (achat du passe), le serveur vérifiant
  le jeton d'achat auprès de Google (`battle_pass.unlock_premium`, marqué TODO).

## À faire ensuite

- Utiliser les jokers (50/50, +5 s) : prévus pour le défi du jour et les parties non classées, jamais en duel classé.
- Images des 3 avatars exclusifs (générées sur RunPod) : pour l'instant des images provisoires (`"art_todo": true`).
- Saison 2 : nouveau fichier `season_2.json` qui démarre à la fin de la saison 1.
