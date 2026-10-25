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

### 2.1 Rythme du passe — dès la saison 2
- Palier : **800 → 1 000 XP**.
- Duels : XP pleine pour les **5 premiers duels du jour**, **moitié** au-delà
  (défi du jour, quêtes et défis hebdo inchangés).
- Résultat simulé : régulier fini **vers le jour 35** (semaine 5), accro vers le
  jour 24, occasionnel au palier 17.
- La saison 1 reste telle quelle : changer `tier_xp` en cours de saison ferait
  reculer le palier affiché des joueurs. **Elle finit le 2026-11-09 : la saison 2
  doit exister avant.**

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

### 2.5 Achats en euros (avec Google Play Billing, après les comptes)
- **Passe premium** (proposition : 3,99 €).
- **Packs de Neurones** (proposition : 500 = 0,99 € · 1 200 = 1,99 € ·
  3 500 = 4,99 €). Prix bas, public ado.
- **« Récompense sans pub »** (remplace « sans pub ») : l'acheteur touche la
  récompense d'une pub sans regarder la vidéo (même plafond par jour).

## 3. Lots

| Lot | Contenu | Qui |
|---|---|---|
| E1 | Saison 2 (`season_2.json`, palier 1 000 XP, piste premium refaite) + XP de duel dégressive | serveur |
| E2 | Type d'objet « titre » (fait : 6 titres en boutique 300-1 500, 6 de saison 2, Casier « Titre », affiché sous le pseudo à l'Accueil, au Profil, au Classement, dans Social et en duel) ; catalogue agrandi avec E3 | serveur + jeu |
| E3 | Boutique tournante (sélection du jour, refus hors sélection, compte à rebours) | serveur + jeu |
| E4 | Achats en euros (premium, packs, récompense sans pub) | après Play Billing |

E1 est urgent (fin de saison 1 le 2026-11-09).
