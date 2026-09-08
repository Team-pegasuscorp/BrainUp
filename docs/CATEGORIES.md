# Catégories — Quizz & OpenTDB

Référence des catégories du jeu et leur correspondance avec l'API [Open Trivia DB](https://opentdb.com/api_config.php).

**Licence OpenTDB :** [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) — créditer la source si redistribution du contenu.

---

## Catégories Quizz (actuelles)

Définies dans [`data/categories.json`](../data/categories.json). Fichier de questions associé : `data/questions/{id}.json`.

| ID Quizz | OpenTDB id | FR | EN | Questions |
|----------|------------|----|----|-----------|
| `sport` | 21 — Sports | Sport | Sports | 59 |
| `cinema` | 11 — Entertainment: Film | Cinéma | Cinema | 57 |
| `history` | 23 — History | Histoire | History | 57 |
| `music` | 12 — Entertainment: Music | Musique | Music | 50 |
| `geography` | 22 — Geography | Géographie | Geography | 50 |
| `science` | 17 — Science & Nature | Sciences & Nature | Science & Nature | 50 |
| `general` | 9 — General Knowledge | Culture générale | General Knowledge | 50 |
| `television` | 14 — Entertainment: Television | Télévision | Television | 50 |

**Total :** 8 catégories, ~423 questions (FR + EN).

### Import de contenu

```bash
tools/.venv/bin/python tools/import_opentdb.py --amount 30
tools/.venv/bin/python tools/import_opentdb.py --categories sport --amount 20
```

Le script lit `opentdb_id` depuis `categories.json` et écrit les JSON locaux avec traduction FR (Argos Translate).

---

## Toutes les catégories OpenTDB (24)

Source : `https://opentdb.com/api_category.php`  
Comptages : questions **vérifiées** / **totales** (`api_count_global.php`).

| ID | Catégorie OpenTDB | Vérifiées | Total | Utilisée dans Quizz |
|----|-------------------|-----------|-------|---------------------|
| 9 | General Knowledge | 469 | 5 422 | ✅ `general` |
| 10 | Entertainment: Books | 120 | 512 | |
| 11 | Entertainment: Film | 301 | 1 119 | ✅ `cinema` |
| 12 | Entertainment: Music | 495 | 1 269 | ✅ `music` |
| 13 | Entertainment: Musicals & Theatres | 36 | 152 | |
| 14 | Entertainment: Television | 196 | 799 | ✅ `television` |
| 15 | Entertainment: Video Games | 1 185 | 4 068 | |
| 16 | Entertainment: Board Games | 78 | 261 | |
| 17 | Science & Nature | 299 | 935 | ✅ `science` |
| 18 | Science: Computers | 192 | 950 | |
| 19 | Science: Mathematics | 80 | 389 | |
| 20 | Mythology | 71 | 219 | |
| 21 | Sports | 176 | 809 | ✅ `sport` |
| 22 | Geography | 383 | 821 | ✅ `geography` |
| 23 | History | 411 | 980 | ✅ `history` |
| 24 | Politics | 77 | 333 | |
| 25 | Art | 59 | 212 | |
| 26 | Celebrities | 53 | 240 | |
| 27 | Animals | 99 | 370 | |
| 28 | Vehicles | 87 | 304 | |
| 29 | Entertainment: Comics | 79 | 184 | |
| 30 | Science: Gadgets | 40 | 152 | |
| 31 | Entertainment: Japanese Anime & Manga | 204 | 778 | |
| 32 | Entertainment: Cartoon & Animations | 108 | 334 | |

**Global OpenTDB :** ~5 300 questions vérifiées / ~21 600 au total.

> Seules les questions **vérifiées** sont fiables. Le reste est en attente ou rejeté.

---

## Affichage en jeu

| Élément | Détail |
|---------|--------|
| Écran | Onglet **Quiz** → `category_select.tscn` |
| Chargement | `QuestionLoader.get_categories(locale)` |
| Ordre | Alphabétique sur le **nom traduit** |
| Couleurs | `UiTokens.accent_for_category()` |
| Profil | Stats par catégorie dans l'onglet Profil |

---

## Pistes pour de futures catégories

| Idée id Quizz | OpenTDB id | Nom API | Vérifiées |
|---------------|------------|---------|-----------|
| `gaming` | 15 | Entertainment: Video Games | 1 185 |
| `anime` | 31 | Entertainment: Japanese Anime & Manga | 204 |
| `animals` | 27 | Animals | 99 |

### Ajouter une catégorie

1. Entrée dans `data/categories.json`
2. Créer `data/questions/{id}.json` : `{ "category": "…", "questions": [] }`
3. Importer : `tools/.venv/bin/python tools/import_opentdb.py --categories {id} --amount 50`
4. (Optionnel) Couleur dans `scripts/config/ui_tokens.gd` → `accent_for_category()`.

---

*Mis à jour le 2026-09-08.*
