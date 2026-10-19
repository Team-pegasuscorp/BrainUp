# Boutique côté serveur

> Branche `test-boutique-serveur` (jeu + `brainup-backend`), 2026-10-19.
> Choix (page de décisions + Yannick le 19/10) : avatars + cadres (+ bannières), petit catalogue fixe,
> exclusifs gagnés en jouant, **une seule monnaie, les Neurones (« coins » dans le code), gagnée en jouant**, rythme ≈ 15-20 duels pour
> un objet commun, **jokers vendus contre des pièces** (pas d'argent réel), **soldes repartis de zéro**.

## Ce qui change pour le joueur

- Le solde, les objets possédés et les jokers viennent du serveur (`GET /shop`) à chaque lancement,
  à l'ouverture de la boutique et après chaque gain. Les 2 000 pièces de démo et les achats locaux
  de test disparaissent ; un objet porté mais plus possédé repasse à l'apparence par défaut.
- Acheter = demande au serveur (`NetworkManager.buy_shop_item`) ; la page se redessine à la réponse.
- Nouveau rayon **Jokers** sous les objets : 50/50 et +5 s, stock affiché, un toucher = un joker acheté.
  Utilisables en duel entre amis et dans le défi du jour (1 de chaque au plus par partie), jamais en classé.
- La boutique ne liste que ce que le serveur vend (les avatars « demo » sont masqués, sauf
  `SHOP_DEMO_ITEMS=1` sur le serveur de dev).

## Gains (`brainup-backend/app/shop.py`)

| Source | Pièces |
|--------|--------|
| Duel classé terminé (bots compris, pas les duels entre amis) | 15, +10 si victoire |
| Défi du jour (premier résultat du jour) | 30 |
| Quête du jour récupérée | 20, 3 par jour au plus |
| Palier « pièces » du passe | montant du palier |
| Première montée en Argent / Or / Platine / Diamant | 100 / 200 / 300 / 500 (une fois par ligue, à vie) |

Prix (catalogue) : commun 300, rare 600, épique 900, légendaire 1 500 ; joker 150.

## Technique

- `coin_ledger` = le porte-monnaie : solde = somme des lignes ; la clé `(reason, ref)` empêche de
  payer deux fois (`duel`/id du match, `daily`/jour, `quest`/jour:quête, `league`/ligue,
  `pass`/saison:voie:palier). Un achat = ligne négative.
- `player_items` : objets achetés ; les objets du passe viennent des paliers réclamés.
  `players.jokers_bought` s'ajoute aux jokers du passe dans `jokers_available`.
- Achats sérialisés par joueur (`FOR UPDATE`) : deux appuis simultanés ne dépensent pas deux fois.
- `POST /players` remet à `""` les objets portés non possédés (anti-triche des tenues).
- Routes : `GET /shop?device_id=`, `POST /shop/buy {device_id, item_id}`,
  `POST /shop/joker {device_id, item_id}` → état complet (`coins`, `owned`, `prices`, `jokers`,
  `joker_prices`, `rules`) ou erreur `not_enough_coins` (402), `already_owned`, `not_for_sale`,
  `unknown_item` (404).
- `match_over`, `/daily-challenge/result`, `/pass/quest`, `/pass/claim` renvoient `coins_gained`.
- `app/data/shop/catalog.json` est une **copie à la main** de `data/shop/catalog.json` du jeu :
  la recopier à chaque changement d'objet ou de prix. Les seuils de ligue sont recopiés de
  `scripts/profile/trophy_leagues.gd` (provisoires).

## Mise à jour d'une base existante

```
docker exec -i quizz-backend-postgres-1 psql -U quizz -d quizz < db/init/011_shop.sql
```

Test : `python tools/test_shop.py` (pile lancée sous `-p quizz-backend`, `pip install websockets`).

## Reste à faire

- Retours visuels du rayon Jokers et du parcours d'achat sur téléphone (domaine de Sylou7 pour le style).
- ~~« +N pièces » à la fin du duel~~ : fait (ligne « Pièces » de l'écran de fin, total serveur + bonus de nouvelle ligue).
- Argent réel (packs, retrait des pubs) : plus tard, après les comptes Google Play Jeux.
