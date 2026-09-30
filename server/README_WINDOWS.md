# Faire tourner le serveur BrainUp sous Windows

Ce dossier est une copie du dépôt `brainup-backend` (branche `test-boutique`, commit `91386e4`, 30/09/2026).
Il contient l'API (FastAPI, Python) et la base PostgreSQL : comptes par appareil, classements,
défi du jour, défis 1v1, duels classés en direct (Classique / Survie / Chrono, draft de catégorie),
cosmétiques partagés.

Godot ignore ce dossier (fichier `.gdignore`) : il n'entre ni dans le projet ni dans l'APK.

Toutes les commandes ci-dessous se tapent dans **PowerShell**, depuis ce dossier `server`.

---

## Option A — avec Docker Desktop (recommandé)

Rien à installer côté Python ni PostgreSQL : Docker fait tout.

1. Installer **Docker Desktop** : https://www.docker.com/products/docker-desktop/
   (il active WSL 2 si besoin ; redémarrer Windows si demandé). Le lancer une fois.
2. Créer le fichier de configuration :
   ```powershell
   Copy-Item .env.example .env
   notepad .env
   ```
   Mettre un mot de passe de ton choix sur la ligne `POSTGRES_PASSWORD=`.
3. Démarrer :
   ```powershell
   docker compose up -d --build
   ```
   Le premier démarrage crée la base avec tous les fichiers `db\init\*.sql`.
4. Vérifier dans le navigateur : http://localhost:8000/health doit afficher `{"status":"ok"}`.

Commandes utiles :

| Action | Commande |
|--------|----------|
| Voir les logs de l'API | `docker compose logs -f api` |
| Arrêter | `docker compose down` |
| Redémarrer après une mise à jour du code | `docker compose up -d --build` |
| Tout effacer (base comprise) et repartir de zéro | `docker compose down -v` puis `docker compose up -d --build` |

### Mettre à jour une base existante

Les fichiers `db\init\*.sql` ne s'exécutent **qu'au tout premier démarrage** (base vide).
Si un nouveau fichier SQL arrive plus tard (ex. `007_cosmetics.sql`), l'appliquer à la main :

```powershell
Get-Content db\init\007_cosmetics.sql | docker compose exec -T postgres psql -U quizz -d quizz
```

(Ou repartir de zéro avec `docker compose down -v`, si les données de test ne comptent pas.)

---

## Option B — sans Docker

1. Installer **Python 3.12** (https://www.python.org/downloads/, cocher « Add python.exe to PATH »)
   et **PostgreSQL 16** (https://www.postgresql.org/download/windows/, noter le mot de passe de `postgres`).
2. Créer l'utilisateur et la base (adapter `MOTDEPASSE`) :
   ```powershell
   psql -U postgres -c "CREATE USER quizz WITH PASSWORD 'MOTDEPASSE';"
   psql -U postgres -c "CREATE DATABASE quizz OWNER quizz;"
   ```
   (`psql` est dans `C:\Program Files\PostgreSQL\16\bin` si la commande n'est pas trouvée.)
3. Créer les tables, **dans l'ordre** :
   ```powershell
   Get-ChildItem db\init\*.sql | Sort-Object Name | ForEach-Object { psql -U quizz -d quizz -f $_.FullName }
   ```
   `001_schema.sql` crée l'extension `pgcrypto` : si elle est refusée, lancer ce fichier une fois avec `-U postgres`.
4. Installer les dépendances et lancer l'API :
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r app\requirements.txt
   $env:DATABASE_URL = "postgresql+psycopg://quizz:MOTDEPASSE@localhost:5432/quizz"
   cd app
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```
   Si PowerShell refuse `Activate.ps1` : `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
5. Vérifier http://localhost:8000/health.

---

## Brancher le jeu

- Le jeu vise `http://127.0.0.1:8000` (`BASE_URL` dans `scripts/autoload/network_manager.gd`) :
  **Godot sur le même PC** fonctionne directement.
- **Téléphone branché en USB** : `adb reverse tcp:8000 tcp:8000` redirige le `127.0.0.1:8000` du téléphone
  vers le PC. À refaire à chaque rebranchement (et après un export Godot, qui relance adb).
- **Téléphone en Wi-Fi** : remplacer `127.0.0.1` par l'adresse IP du PC (`ipconfig`) dans `BASE_URL`,
  et ouvrir le port dans le pare-feu (PowerShell **administrateur**) :
  ```powershell
  New-NetFirewallRule -DisplayName "BrainUp API" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
  ```
- L'APK Android doit avoir la permission **Internet** : préréglage d'export Android →
  Permissions → `Internet` coché (dans `export_presets.cfg` : `permissions/internet=true`).
  Sans elle, le jeu ne joint aucun serveur.

## Tests (facultatif)

Avec le serveur lancé :

```powershell
pip install websockets
python tools\test_live_modes.py     # un duel par mode contre le bot + un draft à deux (~3 min)
python tools\test_live_cosmetics.py
```

`tools\test_live_trophies.py` lit la base via `docker exec quizz-backend-postgres-1` : il ne marche qu'avec
l'option A, en démarrant sous ce nom de projet : `docker compose -p quizz-backend up -d --build`.

## Pour aller plus loin

- `README.md` : routes de l'API, défi du jour, trophées, bots.
- Côté jeu : `docs/MULTIPLAYER_PLAN.md`, et sur la branche `test-boutique` `docs/DUELS_CLASSES.md`
  (duels classés, draft, protocole). Le jeu de `main` utilise encore l'ancien match en direct à
  catégorie fixe : le serveur le comprend toujours.
