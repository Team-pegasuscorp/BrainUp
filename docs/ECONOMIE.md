# Économie de BrainUp — récompenses, passe, boutique

État au 2026-10-25 et refonte décidée par Yannick. Les choix déjà actés sont sur la
page « Décisions boutique » (une seule monnaie : les **Neurones**, gagnés en jouant ;
pas d'objet aléatoire ; pub récompensée seulement, au choix du joueur ; jokers
jamais en duel classé ; public ado).

## 1. Constat (saison 1, chiffres du serveur)

Simulation sur une saison de 6 semaines :

| Profil | Palier du passe | Neurones gagnés en jouant | Toute la boutique en |
|---|---|---|---|
| Occasionnel : 4 j/sem, 2 duels/j, 2 quêtes, pas de pub | 21/40 | ~2 600 (+400 du passe) | 67 jours |
| Régulier : 7 j/sem, 4 duels, défi, 3 quêtes, 2 pubs | 40/40 **au jour 28** | ~8 400 (+1 250) | **37 jours** |
| Accro : 7 j/sem, 10 duels, 5 pubs | 40/40 **au jour 16** | ~15 500 (+1 250) | 21 jours |

Problèmes :
1. **Passe fini trop tôt** : plus rien à viser pendant 2 à 4 semaines.
2. **Neurones sans valeur** : 12 objets payants (8 400 en tout), rachetés en un
   mois ; ensuite seuls les jokers coûtent. Un pack de Neurones en euros
   n'aurait aucun intérêt.
3. **Passe premium = 3 100 Neurones**, plus du tiers de la boutique : il nourrit
   l'inflation au lieu de valoir pour son contenu.
4. **« Sans pub »** ne veut rien dire : aucune pub n'est imposée.

## 2. Décisions (2026-10-25)

### 2.1 Rythme du passe — Saison 1 de la sortie
- Palier : **800 → 1 000 XP**.
- Duels : XP pleine pour les **5 premiers duels du jour**, **moitié** au-delà
  (défi du jour, quêtes et défis hebdo inchangés).
- Résultat simulé : régulier fini **vers le jour 35** (semaine 5), accro vers le
  jour 24, occasionnel au palier 17.
- Mise à jour du 2026-10-25 : l'app ne sort pas avant le 2026-11-09, donc pas de
  saison 2 maintenant. La saison **« Givre » devient la Saison 1 de la sortie**
  (`data/pass/season_1.json`, id `givre`) ; l'ancienne saison « Éveil » est rangée
  dans `data/pass/drafts/eveil.json` (non chargée) pour une saison future.

### 2.2 Passe premium (euros) : le contenu avant la monnaie
- Neurones de la piste premium : **3 100 → ~1 000** (10 paliers de 100).
- Les paliers libérés reçoivent des **titres** exclusifs, des **jokers** et les
  objets de saison (avatars, cadres, bannières), qui restent introuvables ailleurs.
- La piste gratuite garde ses ~1 250 Neurones, ses jokers et 2 objets ; on y
  ajoute 2 ou 3 titres.

### 2.3 Boutique tournante
- La boutique montre **une sélection qui change chaque jour** (proposition :
  6 objets = 2 communs, 2 rares, 1 épique, 1 légendaire), plus « À la une ».
- Sélection **calculée par le serveur** à partir de la date (identique pour tous) ;
  le serveur **refuse l'achat** d'un objet hors sélection.
- Catalogue agrandi pour qu'un objet revienne environ une fois par semaine :
  **~35-40 objets** (cadres et bannières sont dessinés en code, donc peu chers à
  multiplier ; titres sans graphisme).
- Revient sur la décision « rotation : fixe » du 30/09.

### 2.4 Nouveaux types d'objets
- **Titres** (premier) : un texte sous le pseudo (« Cerveau d'or », « Roi de la
  géo »…), vu au profil, au classement et au face-à-face du duel. Rareté et prix
  comme les autres objets, plus des titres de saison dans le passe.
- Ensuite, à discuter : **emotes en duel** (protocole live + interface), **effets
  de victoire**.

### 2.5 Saison 1 « Givre » (sortie)
- 40 paliers de 1 000 XP, 6 semaines. Piste premium : 13 objets exclusifs
  (4 cadres, 4 bannières, 4 titres, **3 avatars** : Lynx des neiges et Manchot
  des glaces épiques, Ours des neiges légendaire), 1 000 Neurones, 7 paliers de
  jokers. Piste gratuite : 1 250 Neurones, jokers, 2 objets, 2 titres.
- Pendant les tests, la saison démarre le 2026-10-25.

### 2.6 Achats en euros (avec Google Play Billing, après les comptes)
- **Passe premium** (proposition : 3,99 €).
- **Packs de Neurones** (proposition : 500 = 0,99 € · 1 200 = 1,99 € ·
  3 500 = 4,99 €). Prix bas, public ado.
- **« Récompense sans pub »** (remplace « sans pub ») : l'acheteur touche la
  récompense d'une pub sans regarder la vidéo (même plafond par jour).

## 3. Lots

| Lot | Contenu | Qui |
|---|---|---|
| E1 | Saison de sortie « Givre » (`season_1.json`, palier 1 000 XP, piste premium refaite) + XP de duel dégressive (fait) | serveur |
| E2 | Type d'objet « titre » (fait : 6 titres en boutique 300-1 500, 6 de la saison Givre, Casier « Titre », affiché sous le pseudo à l'Accueil, au Profil, au Classement, dans Social et en duel) ; catalogue agrandi avec E3 | serveur + jeu |
| E3 | Boutique tournante (fait : 6 objets/jour, même sélection pour tous, nouvelle à 00:00 UTC, achat refusé hors sélection `not_in_rotation`, « Nouveautés dans … » ; catalogue 38 objets en vente = 12 communs, 12 rares, 8 épiques, 6 légendaires ; chaque objet revient une fois par cycle de 6 à 8 jours ; `SHOP_ROTATION=0` en local) | serveur + jeu |
| E4 | Achats en euros (premium, packs, récompense sans pub) | après Play Billing |

## 4. Le jour du lancement

1. **Avatars Givre** générés (pipeline RunPod des mascottes) : `avatar_givre_1..3`
   ont encore `art_todo` (cercle vide en jeu).
2. **Date de la saison** : `start` de `data/pass/season_1.json` = jour de la sortie.
3. **Remise à zéro des comptes de test** (décidé le 2026-10-25) : comptes et
   pseudos gardés ; progression du passe, Neurones et objets effacés :
   `DELETE FROM pass_progress; DELETE FROM coin_ledger; DELETE FROM player_items;`
   (sauvegarde `deploy/backup.sh` juste avant). Trophées : à décider.
4. Prix des achats en euros (E4) et vraie clé de signature.
