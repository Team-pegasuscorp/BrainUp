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

La base vit dans le volume `pgdata`. Dump manuel :

```bash
docker compose -f docker-compose.prod.yml exec postgres \
  pg_dump -U quizz quizz > backup-$(date +%F).sql
```

À automatiser (cron + rclone) avant la mise en ligne réelle des joueurs.
