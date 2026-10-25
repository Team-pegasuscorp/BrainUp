# Déploiement production (Hetzner)

Stack : Caddy (HTTPS auto) → API FastAPI → Postgres 16 (interne, port non exposé).

## Mise en route (résumé)

```bash
# 1. Copier le dépôt sur le serveur
rsync -a --exclude .git --exclude __pycache__ --exclude .env ./ root@<serveur>:/opt/brainup/

# 2. Créer /opt/brainup/.env (voir ci-dessous)

# 3. Lancer
ssh root@<serveur> 'cd /opt/brainup && docker compose -f docker-compose.prod.yml up -d --build'
```

Le dossier `db/init` est monté dans l'initdb : une base **neuve** applique toutes
les migrations dans l'ordre au premier démarrage.

## .env de production

```env
POSTGRES_DB=quizz
POSTGRES_USER=quizz
POSTGRES_PASSWORD=<mot de passe fort généré>
GOOGLE_PLAY_WEB_CLIENT_ID=10739877812-avqodv9g1tpipudcrmcaamor6ufnt1up.apps.googleusercontent.com
GOOGLE_PLAY_WEB_CLIENT_SECRET=<secret du client Web (GOCSPX-...)>
```

Ne jamais définir `GOOGLE_AUTH_MOCK_SUB` ici (la prod ne doit jamais mocker
l'échange Google) ; `PASS_DEV_UNLOCK` et `SHOP_DEMO_ITEMS` restent à 0.

## DNS

Enregistrement **A** : `api.philia-interactive.com` → IP du VPS. Sans lui,
Let's Encrypt ne peut pas délivrer le certificat et Caddy sert une erreur TLS.
Toujours passer par `docker compose -f docker-compose.prod.yml logs caddy` pour
diagnostiquer.

## Sauvegardes

**Sur le serveur** : `deploy/backup.sh`, lancé chaque nuit à 03:30 par cron
(`pg_dump -Fc`, vérifié par `pg_restore --list`, 14 jours gardés dans
`/opt/brainup/backups`, journal `/var/log/brainup-backup.log`). Installation :

```bash
ssh brainup-hetzner 'install -m 644 /opt/brainup/deploy/brainup-backup.cron /etc/cron.d/brainup-backup \
  && /opt/brainup/deploy/backup.sh'
```

**Copie hors serveur** : le PC de Yannick rapatrie les dumps puis les pousse sur
Google Drive (`gdrive:BrainUp/backups`), aucune clé Google sur le serveur :

```bash
install -m 755 deploy/pull-backups.sh ~/.local/bin/brainup-pull-backups
cp deploy/systemd/brainup-pull-backups.* ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now brainup-pull-backups.timer
```

**Restaurer** (dans une base vide) :

```bash
docker compose -f docker-compose.prod.yml exec -T postgres \
  pg_restore -U quizz -d quizz --clean --if-exists --no-owner < backups/brainup-AAAA-MM-JJ_HHMM.dump
```

Essayer le script sur la pile locale :
`BRAINUP_ROOT=$PWD BRAINUP_BACKUP_DIR=/tmp/bk BRAINUP_COMPOSE="docker compose -p quizz-backend" sh deploy/backup.sh`

## Limites de requêtes

`app/rate_limit.py` : par joueur (`device_id` / `player_id`) 120 req/min (20/min
sur achats, pub, inscription, recherche, demandes d'amis), et 600 req/min par IP.
Au-delà : 429 + `Retry-After`. Actif en prod (`RATE_LIMIT_ENABLED=1`), coupé par
défaut en local pour les suites `tools/`. Test : `python tools/test_rate_limit.py`.
